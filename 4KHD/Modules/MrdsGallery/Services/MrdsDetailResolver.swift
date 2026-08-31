import Foundation

nonisolated enum MrdsDetailResolverError: LocalizedError, Equatable {
    case invalidDetailURL
    case invalidPayload
    case unrecognizedMarkup

    var errorDescription: String? {
        switch self {
        case .invalidDetailURL: "每日大赛图集地址无效"
        case .invalidPayload: "每日大赛详情数据无法解析"
        case .unrecognizedMarkup: "每日大赛详情页面结构已变化"
        }
    }
}

enum MrdsDetailResolver {
    nonisolated static let maximumDetailImageCount = 10000
    private nonisolated static let articleBodyStartRegex = regex(
        #"<div\b[^>]*class=["'][^"']*post-content[^"']*["'][^>]*itemprop=["']articleBody["'][^>]*>"#
    )
    private nonisolated static let articleBodyStartAltRegex = regex(
        #"<div\b[^>]*itemprop=["']articleBody["'][^>]*>"#
    )
    private nonisolated static let divTagRegex = regex(#"<\s*(/?)\s*div\b[^>]*>"#)
    private nonisolated static let hiddenImageRegex = regex(#"data-xkrkllgl=["']([^"']+)["']"#)
    private nonisolated static let videoURLRegex = regex(#""video"\s*:\s*\{\s*"url"\s*:\s*"([^"]+)"#)
    private nonisolated static let coverRegex = regex(#"loadBannerDirect\(\s*['"]([^'"]+)['"]"#)
    private nonisolated static let descriptionRegex = regex(
        #"<meta[^>]+(?:property=["']og:description["']|name=["']description["'])[^>]+content=["']([^"']*)["']"#
    )
    private nonisolated static let tagNameRegex = regex(#"data-video_tag_name=["']([^"']+)["']"#)
    private nonisolated static let nearLinkRegex = regex(
        #"<div class=["']post-near["']>[\s\S]*?</div>"#
    )
    private nonisolated static let archiveLinkRegex = regex(
        #"<a[^>]+href=["']((?:https://www\.mrds66\.com)?/archives/[0-9]+/)["'][^>]*title=["']([^"']+)["']"#
    )

    static func resolve(pageURL: URL) async throws -> MrdsResolvedDetailPage {
        guard pageURL.path.range(of: #"^/archives/[0-9]+/?$"#, options: .regularExpression) != nil else {
            throw MrdsDetailResolverError.invalidDetailURL
        }
        let request = try MrdsRequestFactory.makeHTMLRequest(url: pageURL)
        let (data, _) = try await MrdsHTTPClient.data(for: request)
        let page = try await parseConcurrently(data: data, pageURL: pageURL)
        let recommendations = await enrichRecommendationCovers(page.recommendations)
        return MrdsResolvedDetailPage(
            pageURL: page.pageURL,
            imageURLs: page.imageURLs,
            pageURLs: page.pageURLs,
            videoURL: page.videoURL,
            metadata: page.metadata,
            recommendations: recommendations
        )
    }

    @concurrent
    private nonisolated static func parseConcurrently(
        data: Data,
        pageURL: URL
    ) async throws -> MrdsResolvedDetailPage {
        try Task.checkCancellation()
        guard let html = String(data: data, encoding: .utf8) else {
            throw MrdsDetailResolverError.invalidPayload
        }
        let page = try parse(html: html, pageURL: pageURL)
        try Task.checkCancellation()
        return page
    }

    nonisolated static func parse(html: String, pageURL: URL) throws -> MrdsResolvedDetailPage {
        let body = articleBody(in: html) ?? html
        let imageURLs: [URL] = matches(hiddenImageRegex, in: body).compactMap { value in
            OnlineSourcePolicy.resolvedURL(
                decodeHTML(value),
                relativeTo: pageURL,
                source: .mrds,
                resource: .media
            )
        }.uniqued()
        let videoURL = videoURL(in: html, relativeTo: pageURL)
        guard !imageURLs.isEmpty || videoURL != nil else {
            throw MrdsDetailResolverError.unrecognizedMarkup
        }
        let cappedImages = Array(imageURLs.prefix(maximumDetailImageCount))
        let description = firstMatch(descriptionRegex, in: html).map(decodeHTML) ?? ""
        let tags = firstMatch(tagNameRegex, in: html)?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        return MrdsResolvedDetailPage(
            pageURL: pageURL,
            imageURLs: cappedImages,
            pageURLs: [pageURL],
            videoURL: videoURL,
            metadata: MrdsDetailMetadata(
                description: description,
                tags: tags,
                totalImages: cappedImages.count,
                totalPages: 1
            ),
            recommendations: recommendations(in: html, pageURL: pageURL)
        )
    }

    private nonisolated static func articleBody(in html: String) -> String? {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        let startMatch = articleBodyStartRegex.firstMatch(in: html, range: fullRange)
            ?? articleBodyStartAltRegex.firstMatch(in: html, range: fullRange)
        guard let startMatch else { return nil }
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

    /// `.post-near` has titles only. Cover comes from that archive's
    /// `loadBannerDirect`, falling back to the first `data-xkrkllgl` image.
    nonisolated static func coverURL(fromArchiveHTML html: String, pageURL: URL) -> URL? {
        if let raw = firstMatch(coverRegex, in: html) {
            let normalized = decodeHTML(raw)
                .replacingOccurrences(of: "://pic.sbhioa.cn//", with: "://pic.sbhioa.cn/")
            if let url = OnlineSourcePolicy.resolvedURL(
                normalized,
                relativeTo: pageURL,
                source: .mrds,
                resource: .media
            ) {
                return url
            }
        }
        if let raw = firstMatch(hiddenImageRegex, in: html) {
            return OnlineSourcePolicy.resolvedURL(
                decodeHTML(raw),
                relativeTo: pageURL,
                source: .mrds,
                resource: .media
            )
        }
        return nil
    }

    private static func enrichRecommendationCovers(
        _ recommendations: [OnlineGalleryRecommendation]
    ) async -> [OnlineGalleryRecommendation] {
        guard !recommendations.isEmpty else { return recommendations }
        return await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, recommendation) in recommendations.enumerated() {
                group.addTask {
                    let cover = await fetchCover(for: recommendation.detailURL)
                    return (index, cover)
                }
            }
            var covers: [Int: URL] = [:]
            for await (index, cover) in group {
                if let cover {
                    covers[index] = cover
                }
            }
            return recommendations.enumerated().map { index, recommendation in
                if recommendation.coverURL != nil { return recommendation }
                guard let cover = covers[index] else { return recommendation }
                return OnlineGalleryRecommendation(
                    title: recommendation.title,
                    detailURL: recommendation.detailURL,
                    coverURL: cover,
                    coverAspectRatio: recommendation.coverAspectRatio,
                    imageCount: recommendation.imageCount
                )
            }
        }
    }

    private static func fetchCover(for detailURL: URL) async -> URL? {
        do {
            try Task.checkCancellation()
            let request = try MrdsRequestFactory.makeHTMLRequest(url: detailURL)
            let (data, _) = try await MrdsHTTPClient.data(for: request)
            try Task.checkCancellation()
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            return coverURL(fromArchiveHTML: html, pageURL: detailURL)
        } catch {
            return nil
        }
    }

    private nonisolated static func videoURL(in html: String, relativeTo _: URL) -> URL? {
        guard let raw = firstMatch(videoURLRegex, in: html) else { return nil }
        let unescaped = raw.replacingOccurrences(of: #"\/"#, with: "/")
        guard let url = URL(string: unescaped),
              url.pathExtension.lowercased() == "m3u8" else { return nil }
        return OnlineSourcePolicy.allows(url, source: .mrds, resource: .media) ? url : nil
    }

    private nonisolated static func recommendations(
        in html: String,
        pageURL: URL
    ) -> [OnlineGalleryRecommendation] {
        guard let container = firstFullMatch(nearLinkRegex, in: html) else { return [] }
        var seen = Set<String>()
        var items: [OnlineGalleryRecommendation] = []
        let range = NSRange(container.startIndex ..< container.endIndex, in: container)
        for match in archiveLinkRegex.matches(in: container, range: range) {
            guard match.numberOfRanges > 2,
                  let hrefRange = Range(match.range(at: 1), in: container),
                  let titleRange = Range(match.range(at: 2), in: container),
                  let detailURL = OnlineSourcePolicy.resolvedURL(
                      decodeHTML(String(container[hrefRange])),
                      relativeTo: pageURL,
                      source: .mrds,
                      resource: .html
                  ),
                  !detailURL.isSameDetailPath(as: pageURL),
                  seen.insert(detailURL.absoluteString).inserted else { continue }
            let title = decodeHTML(String(container[titleRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(
                OnlineGalleryRecommendation(
                    title: title.isEmpty ? detailURL.lastPathComponent : title,
                    detailURL: detailURL,
                    coverURL: nil,
                    coverAspectRatio: 1.6,
                    imageCount: nil
                )
            )
        }
        return items
    }

    private nonisolated static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private nonisolated static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        matches(regex, in: text).first
    }

    private nonisolated static func firstFullMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: range),
              let matchRange = Range(result.range, in: text) else { return nil }
        return String(text[matchRange])
    }

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid Mrds detail regex: \(pattern)")
        }
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

private extension Array where Element: Hashable {
    nonisolated func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
