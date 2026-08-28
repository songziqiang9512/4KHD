import Foundation

nonisolated enum KnitDetailResolverError: LocalizedError, Equatable {
    case invalidDetailURL
    case invalidPayload
    case unrecognizedMarkup
    case unreasonablePagination

    var errorDescription: String? {
        switch self {
        case .invalidDetailURL: "爱妹子图集地址无效"
        case .invalidPayload: "爱妹子详情分页数据无法解析"
        case .unrecognizedMarkup: "爱妹子详情页面结构已变化"
        case .unreasonablePagination: "爱妹子详情分页数量异常"
        }
    }
}

enum KnitDetailResolver {
    nonisolated static let maximumDetailPageCount = 500
    nonisolated static let maximumDetailImageCount = 10_000
    private nonisolated struct AJAXPayload: Decodable, Sendable {
        let html: String
        let pagination: Pagination
    }

    private nonisolated struct Pagination: Decodable, Sendable {
        let currentPage: Int
        let totalPages: Int

        enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case totalPages = "total_pages"
        }
    }

    private nonisolated static let imageTagRegex = regex(#"<img[^>]+class=[\"'][^\"']*\bitem-image__img\b[^\"']*[\"'][^>]*>"#)
    private nonisolated static let dataSourceRegex = regex(#"data-src=[\"']([^\"']+)[\"']"#)
    private nonisolated static let sourceRegex = regex(#"\bsrc=[\"']([^\"']+)[\"']"#)
    private nonisolated static let videoRegex = regex(#"<source[^>]+src=[\"'](https://media\.knit\.bid/[^\"']+\.m3u8)[\"']"#)
    private nonisolated static let videoObjectRegex = regex(#"\"contentUrl\"\s*:\s*\"(https:\\/\\/media\.knit\.bid\\/[^\"]+\.m3u8)\""#)
    private nonisolated static let totalPagesRegex = regex(#"\"total_pages\"\s*:\s*([0-9]+)"#)
    private nonisolated static let totalItemsRegex = regex(#"\"numberOfItems\"\s*:\s*([0-9]+)"#)
    private nonisolated static let descriptionRegex = regex(#"<meta[^>]+property=[\"']og:description[\"'][^>]+content=[\"']([^\"']*)[\"']"#)
    private nonisolated static let keywordsRegex = regex(#"\"keywords\"\s*:\s*\"([^\"]*)\""#)
    private nonisolated static let recommendationContainerStartRegex = regex(
        #"<div\b[^>]*\bid\s*=\s*[\"']recommend-container[\"'][^>]*>"#
    )
    private nonisolated static let divTagRegex = regex(#"<\s*(/?)\s*div\b[^>]*>"#)

    static func resolve(pageURL: URL) async throws -> KnitResolvedDetailPage {
        guard let identity = KnitDetailURL(url: pageURL) else {
            throw KnitDetailResolverError.invalidDetailURL
        }

        let data: Data
        if identity.page == 1 {
            let request = try KnitRequestFactory.makeHTMLRequest(url: identity.pageURL, isAJAX: false)
            (data, _) = try await KnitHTTPClient.data(for: request)
        } else {
            guard let ajaxURL = identity.ajaxURL else { throw KnitDetailResolverError.invalidDetailURL }
            let request = try KnitRequestFactory.makeHTMLRequest(url: ajaxURL, isAJAX: true)
            (data, _) = try await KnitHTTPClient.data(for: request)
        }
        return try await parseConcurrently(data: data, identity: identity)
    }

    @concurrent
    private nonisolated static func parseConcurrently(
        data: Data,
        identity: KnitDetailURL
    ) async throws -> KnitResolvedDetailPage {
        try Task.checkCancellation()
        let page = try parse(data: data, identity: identity)
        try Task.checkCancellation()
        return page
    }

    private nonisolated static func parse(
        data: Data,
        identity: KnitDetailURL
    ) throws -> KnitResolvedDetailPage {
        let html: String
        let totalPages: Int
        if identity.page == 1 {
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw KnitDetailResolverError.invalidPayload
            }
            html = decoded
            totalPages = firstMatch(totalPagesRegex, in: decoded).flatMap(Int.init) ?? 1
        } else {
            let payload: AJAXPayload
            do {
                payload = try JSONDecoder().decode(AJAXPayload.self, from: data)
            } catch {
                throw KnitDetailResolverError.invalidPayload
            }
            html = payload.html
            totalPages = payload.pagination.totalPages
        }
        return try makeResolvedPage(html: html, totalPages: totalPages, identity: identity)
    }

    private nonisolated static func makeResolvedPage(
        html: String,
        totalPages: Int,
        identity: KnitDetailURL
    ) throws -> KnitResolvedDetailPage {
        guard totalPages >= identity.page,
              totalPages <= maximumDetailPageCount else {
            throw KnitDetailResolverError.unreasonablePagination
        }
        let safeTotalPages = max(totalPages, 1)
        let imageURLs: [URL] = imageTags(in: html).compactMap { tag -> URL? in
            let value = firstMatch(dataSourceRegex, in: tag) ?? firstMatch(sourceRegex, in: tag)
            guard let value else { return nil }
            return OnlineSourcePolicy.resolvedURL(
                decodeHTML(value),
                relativeTo: identity.pageURL,
                source: .knit,
                resource: .media
            )
        }.filter { url in
            !url.path.hasSuffix("/static/zde/timg.gif")
        }.uniqued()

        guard !imageURLs.isEmpty else {
            throw KnitDetailResolverError.unrecognizedMarkup
        }

        let pageURLs = (1...safeTotalPages).compactMap { identity.base.pageURL(page: $0) }
        let videoURL = videoURL(in: html, relativeTo: identity.pageURL)
        let metadata: KnitDetailMetadata?
        if identity.page == 1 {
            let description = firstMatch(descriptionRegex, in: html).map(decodeHTML) ?? ""
            let tags = firstMatch(keywordsRegex, in: html)
                .map(decodeJSONString)
                .map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
                ?? []
            let reportedTotalImages = firstMatch(totalItemsRegex, in: html).flatMap(Int.init)
                ?? imageURLs.count * safeTotalPages
            let totalImages = min(max(reportedTotalImages, imageURLs.count), maximumDetailImageCount)
            metadata = KnitDetailMetadata(
                description: description,
                tags: tags.filter { !$0.isEmpty },
                totalImages: totalImages,
                totalPages: safeTotalPages
            )
        } else {
            metadata = nil
        }
        let recommendations = identity.page == 1
            ? recommendations(in: html, pageURL: identity.pageURL)
            : []

        return KnitResolvedDetailPage(
            pageURL: identity.pageURL,
            imageURLs: imageURLs,
            pageURLs: pageURLs,
            videoURL: videoURL,
            metadata: metadata,
            recommendations: recommendations
        )
    }

    nonisolated static func parseFirstPage(html: String, pageURL: URL) throws -> KnitResolvedDetailPage {
        guard let identity = KnitDetailURL(url: pageURL), identity.page == 1 else {
            throw KnitDetailResolverError.invalidDetailURL
        }
        let totalPages = firstMatch(totalPagesRegex, in: html).flatMap(Int.init) ?? 1
        return try makeResolvedPage(html: html, totalPages: totalPages, identity: identity)
    }

    private nonisolated static func recommendations(
        in html: String,
        pageURL: URL
    ) -> [OnlineGalleryRecommendation] {
        guard let container = recommendationContainer(in: html) else { return [] }
        var seen = Set<String>()

        return KnitListResolver.parseItems(html: container).compactMap { item in
            guard !item.detailURL.isSameDetailPath(as: pageURL),
                  seen.insert(item.detailURL.absoluteString).inserted else {
                return nil
            }
            return OnlineGalleryRecommendation(
                title: item.title,
                detailURL: item.detailURL,
                coverURL: item.coverURL,
                coverAspectRatio: item.coverAspectRatio,
                imageCount: item.reportedPhotoCount > 0 ? item.reportedPhotoCount : nil
            )
        }
    }

    private nonisolated static func recommendationContainer(in html: String) -> String? {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        guard let startMatch = recommendationContainerStartRegex.firstMatch(in: html, range: fullRange) else {
            return nil
        }

        let contentStart = NSMaxRange(startMatch.range)
        let searchRange = NSRange(location: contentStart, length: nsHTML.length - contentStart)
        var depth = 1

        for match in divTagRegex.matches(in: html, range: searchRange) {
            let slashRange = match.range(at: 1)
            let isClosing = slashRange.location != NSNotFound && slashRange.length > 0
            if isClosing {
                depth -= 1
                if depth == 0 {
                    guard match.range.location >= contentStart else { return nil }
                    return nsHTML.substring(
                        with: NSRange(location: contentStart, length: match.range.location - contentStart)
                    )
                }
            } else {
                let tag = nsHTML.substring(with: match.range)
                if !tag.hasSuffix("/>") {
                    depth += 1
                }
            }
        }
        return nil
    }

    private nonisolated static func imageTags(in html: String) -> [String] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return imageTagRegex.matches(in: html, range: range).compactMap { result in
            guard let matchRange = Range(result.range, in: html) else { return nil }
            return String(html[matchRange])
        }
    }

    private nonisolated static func videoURL(in html: String, relativeTo baseURL: URL) -> URL? {
        let raw = firstMatch(videoRegex, in: html)
            ?? firstMatch(videoObjectRegex, in: html).map {
                $0.replacingOccurrences(of: #"\/"#, with: "/")
            }
        guard let raw else { return nil }
        return OnlineSourcePolicy.resolvedURL(raw, relativeTo: baseURL, source: .knit, resource: .media)
    }

    private nonisolated static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: range),
              result.numberOfRanges > 1,
              let matchRange = Range(result.range(at: 1), in: text) else { return nil }
        return String(text[matchRange])
    }

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid Knit detail regex: \(pattern)")
        }
    }

    private nonisolated static func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .removingPercentEncoding ?? value
    }

    private nonisolated static func decodeJSONString(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/", options: .caseInsensitive)
    }
}

private nonisolated struct KnitDetailURL: Sendable {
    nonisolated struct Base: Sendable {
        let articleID: String

        func pageURL(page: Int) -> URL? {
            let safePage = max(page, 1)
            let path = safePage == 1
                ? "/article/\(articleID)/"
                : "/article/\(articleID)/page/\(safePage)/"
            var components = URLComponents()
            components.scheme = "https"
            components.host = "xx.knit.bid"
            components.path = path
            return components.url
        }
    }

    let base: Base
    let page: Int

    init?(url: URL) {
        guard OnlineSourcePolicy.allows(url, source: .knit, resource: .html) else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2 || components.count == 4,
              components[0] == "article",
              Int(components[1]) != nil else { return nil }
        if components.count == 4 {
            guard components[2] == "page", let page = Int(components[3]), page > 1 else { return nil }
            self.page = page
        } else {
            self.page = 1
        }
        base = Base(articleID: components[1])
    }

    var pageURL: URL { base.pageURL(page: page)! }

    var ajaxURL: URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "ajax", value: "1")]
        return components.url
    }
}

private extension Array where Element: Hashable {
    nonisolated func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
