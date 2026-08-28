import Foundation

nonisolated enum KnitListResolverError: LocalizedError, Equatable {
    case invalidURL
    case invalidPayload
    case unrecognizedMarkup

    var errorDescription: String? {
        switch self {
        case .invalidURL: "爱妹子分页地址无效"
        case .invalidPayload: "爱妹子分页数据无法解析"
        case .unrecognizedMarkup: "爱妹子列表页面结构已变化"
        }
    }
}

enum KnitListResolver {
    private nonisolated struct ResponsePayload: Decodable, Sendable {
        let html: String
        let pagination: Pagination
    }

    private nonisolated struct Pagination: Decodable, Sendable {
        let currentPage: Int
        let totalPages: Int
        let hasNext: Bool
        let nextPage: Int?

        enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case totalPages = "total_pages"
            case hasNext = "has_next"
            case nextPage = "next_page"
        }
    }

    private nonisolated static let articleRegex = regex(#"<article[^>]+class=[\"'][^\"']*\bexcerpt\b[^\"']*[\"'][\s\S]*?</article>"#)
    private nonisolated static let detailRegex = regex(#"<a[^>]+class=[\"'][^\"']*imgbox-link[^\"']*[\"'][^>]+href=[\"']((?:https://xx\.knit\.bid)?/article/[0-9]+/)[\"']"#)
    private nonisolated static let coverRegex = regex(#"<img[^>]+class=[\"'][^\"']*imgbox-img[^\"']*[\"'][^>]+data-original-src=[\"']([^\"']+)[\"']"#)
    private nonisolated static let titleRegex = regex(#"<h2[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)</a>[\s\S]*?</h2>"#)
    private nonisolated static let categoryRegex = regex(#"<a[^>]+class=[\"'][^\"']*imgbox-a[^\"']*[\"'][^>]+title=[\"']([^\"']+)[\"']"#)
    private nonisolated static let hotRegex = regex(#"<hot[^>]*>[\s\S]*?([0-9][0-9,]*)\s*</hot>"#)
    private nonisolated static let dateRegex = regex(#"<time[^>]*>\s*([^<]+)\s*</time>"#)
    private nonisolated static let photoCountRegex = regex(#"(?:^|\D)([0-9]+)P"#)
    private nonisolated static let gifCountRegex = regex(#"(?:^|\D)([0-9]+)G"#)
    private nonisolated static let videoCountRegex = regex(#"(?:^|\D)([0-9]+)V"#)

    static func resolve(context: KnitListContext, page: Int = 1) async throws -> KnitListPage {
        guard let url = context.pageURL(page: page) else { throw KnitListResolverError.invalidURL }
        let request = try KnitRequestFactory.makeHTMLRequest(url: url, isAJAX: true)
        let (data, _) = try await KnitHTTPClient.data(for: request)
        return try await parseConcurrently(data: data, context: context)
    }

    @concurrent
    private nonisolated static func parseConcurrently(
        data: Data,
        context: KnitListContext
    ) async throws -> KnitListPage {
        try Task.checkCancellation()
        let page = try parse(data: data, context: context)
        try Task.checkCancellation()
        return page
    }

    nonisolated static func parse(data: Data, context: KnitListContext) throws -> KnitListPage {
        let payload: ResponsePayload
        do {
            payload = try JSONDecoder().decode(ResponsePayload.self, from: data)
        } catch {
            throw KnitListResolverError.invalidPayload
        }
        return try parse(payload: payload, context: context)
    }

    nonisolated static func parseItems(html: String) -> [KnitGalleryItem] {
        matches(articleRegex, in: html).compactMap(makeItem(from:))
    }

    private nonisolated static func parse(payload: ResponsePayload, context: KnitListContext) throws -> KnitListPage {
        let items = parseItems(html: payload.html)
        guard !items.isEmpty || payload.pagination.totalPages == 0 else {
            throw KnitListResolverError.unrecognizedMarkup
        }
        let nextPageURL: URL?
        if payload.pagination.hasNext, let nextPage = payload.pagination.nextPage {
            nextPageURL = context.pageURL(page: nextPage)
        } else {
            nextPageURL = nil
        }
        return KnitListPage(
            items: items,
            currentPage: payload.pagination.currentPage,
            totalPages: payload.pagination.totalPages,
            nextPageURL: nextPageURL
        )
    }

    private nonisolated static func makeItem(from html: String) -> KnitGalleryItem? {
        guard let detailValue = firstMatch(detailRegex, in: html),
              let detailURL = OnlineSourcePolicy.resolvedURL(
                decodeHTML(detailValue),
                relativeTo: URL(string: "https://xx.knit.bid/")!,
                source: .knit,
                resource: .html
              ),
              detailURL.path.range(of: #"^/article/[0-9]+/?$"#, options: .regularExpression) != nil else {
            return nil
        }

        let coverURL = firstMatch(coverRegex, in: html).flatMap { value in
            OnlineSourcePolicy.resolvedURL(
                decodeHTML(value),
                relativeTo: detailURL,
                source: .knit,
                resource: .media
            )
        }
        let parsedTitle = firstMatch(titleRegex, in: html)
            .map(stripTags)
            .map(decodeHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTitle = parsedTitle?.isEmpty == false ? parsedTitle! : detailURL.lastPathComponent
        let category = firstMatch(categoryRegex, in: html)
            .map(decodeHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "爱妹子"
        let publishedDate = firstMatch(dateRegex, in: html)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let viewCount = firstMatch(hotRegex, in: html)
            .map { $0.replacingOccurrences(of: ",", with: "") }
            .flatMap(Int.init)
        let reportedPhotoCount = firstMatch(photoCountRegex, in: rawTitle).flatMap(Int.init) ?? 0
        let reportedGIFCount = firstMatch(gifCountRegex, in: rawTitle).flatMap(Int.init) ?? 0
        let parsedVideoCount = firstMatch(videoCountRegex, in: rawTitle).flatMap(Int.init) ?? 0
        let hasPlayIcon = html.range(
            of: #"class=[\"'][^\"']*\bplay-icon\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        return KnitGalleryItem(
            id: detailURL.pathComponents.filter { $0 != "/" }.last ?? detailURL.absoluteString,
            title: rawTitle,
            rawTitle: rawTitle,
            category: category,
            publishedDate: publishedDate,
            viewCount: viewCount,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 1.5,
            reportedPhotoCount: reportedPhotoCount,
            reportedGIFCount: reportedGIFCount,
            reportedVideoCount: max(parsedVideoCount, hasPlayIcon ? 1 : 0)
        )
    }

    private nonisolated static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard let matchRange = Range(result.range, in: text) else { return nil }
            return String(text[matchRange])
        }
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
            preconditionFailure("Invalid Knit regex: \(pattern)")
        }
    }

    private nonisolated static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private nonisolated static func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .removingPercentEncoding ?? value
    }
}
