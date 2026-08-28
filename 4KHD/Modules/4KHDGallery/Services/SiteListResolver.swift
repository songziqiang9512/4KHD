import Foundation

struct SiteListPage {
    let items: [GalleryItem]
    let nextPageURL: URL?
}

enum SiteListResolverError: LocalizedError, Equatable {
    case unrecognizedListMarkup

    var errorDescription: String? {
        switch self {
        case .unrecognizedListMarkup:
            "4KHD 列表页面结构无法解析，请稍后重试"
        }
    }
}

enum SiteListResolver {
    private static let requestCoalescer = HTMLRequestCoalescer()
    private static let listItemRegex = regex(#"<li[^>]+class=["'][^"']*wp-block-post[^"']*["'][\s\S]*?</li>"#)
    private static let explicitNextRegex = regex(#"<link[^>]+rel=["']next["'][^>]+href=["']([^"']+)["']"#)
    private static let nextLinkRegex = regex(#"<a[^>]+class=["'][^"']*(?:next|wp-block-query-pagination-next)[^"']*["'][^>]+href=["']([^"']+)["']"#)
    private static let currentPageRegex = regex(#"<span[^>]+class=["'][^"']*page-numbers current[^"']*["'][^>]*>\s*([0-9,]+)\s*</span>"#)
    private static let queryPageRegex = regex(#"<a[^>]+class=["'][^"']*page-numbers[^"']*["'][^>]+href=["']([^"']+)["'][^>]*>\s*([0-9,]+)\s*</a>"#)
    private static let detailURLRegex = regex(#"<a[^>]+href=["']([^"']+/content/[^"']+\.html)["']"#)
    private static let coverURLRegex = regex(#"<img[^>]+src=["']([^"']+)["']"#)
    private static let coverWidthRegex = regex(#"<img[^>]+width=["']([0-9]+)["']"#)
    private static let coverHeightRegex = regex(#"<img[^>]+height=["']([0-9]+)["']"#)
    private static let titleRegex = regex(#"<h2[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#)
    private static let metadataRegex = regex(#"\[([^\]-]+)-(\d+)photos\]"#)

    static func resolve(section: GallerySection) async throws -> SiteListPage {
        guard let siteURL = section.siteURL else {
            return SiteListPage(items: [], nextPageURL: nil)
        }
        return try await resolve(pageURL: siteURL, section: section)
    }

    static func resolveSearch(query: String) async throws -> SiteListPage {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.4khd.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "s", value: query)]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return try await resolveSearch(pageURL: url)
    }

    static func resolveSearch(pageURL: URL) async throws -> SiteListPage {
        let html = try await fetchHTML(pageURL)
        return try parse(
            html: html,
            pageURL: pageURL,
            section: .latest,
            usesLatestPagination: false,
            allowsEmptyResults: true
        )
    }

    static func resolve(pageURL: URL, section: GallerySection) async throws -> SiteListPage {
        let html = try await fetchHTML(pageURL)
        return try parse(html: html, pageURL: pageURL, section: section)
    }

    private static func fetchHTML(_ url: URL) async throws -> String {
        try await requestCoalescer.value(for: url) {
            try await fetchHTMLFromNetwork(url)
        }
    }

    private static func fetchHTMLFromNetwork(_ url: URL) async throws -> String {
        let request = try GalleryRequestFactory.makeHTMLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await OnlineSourceSession.galleryHTML.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }

    static func parse(
        html: String,
        pageURL: URL,
        section: GallerySection,
        usesLatestPagination: Bool = true,
        allowsEmptyResults: Bool = false
    ) throws -> SiteListPage {
        let itemHTML = listItemHTML(in: html)
        let items = itemHTML.compactMap { makeItem(from: $0, section: section) }
        let isRecognizedEmptyResult = allowsEmptyResults && containsRecognizedEmptyState(in: html)
        guard !items.isEmpty || isRecognizedEmptyResult else {
            throw SiteListResolverError.unrecognizedListMarkup
        }
        return SiteListPage(
            items: items,
            nextPageURL: nextPageURL(in: html, baseURL: pageURL, section: section, usesLatestPagination: usesLatestPagination)
        )
    }

    private static func listItemHTML(in html: String) -> [String] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return listItemRegex.matches(in: html, range: range).compactMap { result in
            guard let matchRange = Range(result.range, in: html) else { return nil }
            return String(html[matchRange])
        }
    }

    private static func containsRecognizedEmptyState(in html: String) -> Bool {
        html.range(
            of: #"(?:no-results|search-no-results|nothing\s+found|no\s+posts)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func nextPageURL(in html: String, baseURL: URL, section: GallerySection, usesLatestPagination: Bool) -> URL? {
        if section == .latest, usesLatestPagination {
            return latestNextPageURL(in: html)
        }

        if let explicitNext = firstMatch(explicitNextRegex, in: html)
            .flatMap(decodeHTML)
            .flatMap({ OnlineSourcePolicy.resolvedURL($0, relativeTo: baseURL, source: .gallery, resource: .html) }) {
            return explicitNext
        }

        if let nextLink = firstMatch(nextLinkRegex, in: html)
            .flatMap(decodeHTML)
            .flatMap({ OnlineSourcePolicy.resolvedURL($0, relativeTo: baseURL, source: .gallery, resource: .html) }) {
            return nextLink
        }

        return queryPaginationNextPageURL(in: html, baseURL: baseURL)
    }

    private static func latestNextPageURL(in html: String) -> URL? {
        let baseURL = URL(string: "https://www.4khd.com/")!
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let hasPageLinks = queryPageRegex.firstMatch(in: html, range: range) != nil
        if hasPageLinks {
            // 首页同时带有 SEO 全站分页 `/page/2` 和“最新”Query Block
            // 分页 `?query-3-page=2`。两套游标不可混用，否则全站分页会在第三次
            // 请求返回重复项，导致 feed 误判到达末页。
            return queryPaginationNextPageURL(in: html, baseURL: baseURL)
        }

        // 某些版本只输出 Query Block 的“下一页”按钮而没有数字页码。
        // 只接受属于“最新”查询的游标，忽略 Yoast 生成的全站 rel=next。
        if let nextLink = firstMatch(nextLinkRegex, in: html)
            .flatMap(decodeHTML)
            .flatMap({ OnlineSourcePolicy.resolvedURL($0, relativeTo: baseURL, source: .gallery, resource: .html) }),
           isLatestQueryPageURL(nextLink) {
            return nextLink
        }

        // 无页码链接的旧版分页：保持原有 +1 递增行为。
        let currentPage = firstMatch(currentPageRegex, in: html)
            .flatMap { Int($0.replacingOccurrences(of: ",", with: "")) } ?? 1
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.4khd.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "query-3-page", value: "\(currentPage + 1)")]
        return components.url
    }

    private static func isLatestQueryPageURL(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { item in
            item.name == "query-3-page" && item.value.flatMap(Int.init) != nil
        } == true
    }

    private static func queryPaginationNextPageURL(in html: String, baseURL: URL) -> URL? {
        let currentPage = firstMatch(currentPageRegex, in: html)
            .flatMap { Int($0.replacingOccurrences(of: ",", with: "")) } ?? 1
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let candidates = queryPageRegex.matches(in: html, range: range).compactMap { result -> (page: Int, url: URL)? in
            guard result.numberOfRanges > 2,
                  let hrefRange = Range(result.range(at: 1), in: html),
                  let pageRange = Range(result.range(at: 2), in: html),
                  let pageNumber = Int(html[pageRange].replacingOccurrences(of: ",", with: "")),
                  pageNumber > currentPage,
                  let href = decodeHTML(String(html[hrefRange])),
                  let url = OnlineSourcePolicy.resolvedURL(href, relativeTo: baseURL, source: .gallery, resource: .html) else {
                return nil
            }
            return (pageNumber, url)
        }
        return candidates.min { $0.page < $1.page }?.url
    }

    private static func makeItem(from html: String, section: GallerySection) -> GalleryItem? {
        guard let detailURL = firstMatch(detailURLRegex, in: html)
            .flatMap(URL.init(string:)),
              OnlineSourcePolicy.allows(detailURL, source: .gallery, resource: .html) else {
            return nil
        }
        let coverURL = firstMatch(coverURLRegex, in: html)
            .flatMap(decodeHTML)
            .flatMap(URL.init(string:))
            .map(GalleryImageURLNormalizer.normalized)
            .flatMap { OnlineSourcePolicy.allows($0, source: .gallery, resource: .media) ? $0 : nil }
        let coverAspectRatio = coverAspectRatioFromHTML(html) ?? coverURL.flatMap(RemoteImageURLAspectRatio.aspectRatio)
        let rawTitle = firstMatch(titleRegex, in: html)
            .map(stripTags)
            .flatMap(decodeHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? detailURL.deletingPathExtension().lastPathComponent

        let metadata = metadataFromTitle(rawTitle)
        let displayTitle = metadata.displayTitle
        let pageCount = max(Int(ceil(Double(metadata.imageCount ?? 0) / 20.0)), 1)
        let pageURLs = (1...pageCount).map { pageNumber -> URL in
            if pageNumber == 1 { return detailURL }
            return detailURL.appendingPathComponent("\(pageNumber)")
        }

        return GalleryItem(
            id: detailURL.deletingPathExtension().lastPathComponent,
            section: section,
            kind: section == .popular ? .recommended : .gallery,
            title: displayTitle,
            rawTitle: rawTitle,
            subtitle: metadata.size.map { "4KHD 图集，\($0)" } ?? "4KHD 图集",
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: coverAspectRatio,
            imageCount: metadata.imageCount ?? 0,
            pageCount: pageCount,
            pageURLs: pageURLs,
            sampleImageURLs: coverURL.map { [$0] } ?? []
        )
    }

    private static func coverAspectRatioFromHTML(_ html: String) -> Double? {
        guard let width = firstMatch(coverWidthRegex, in: html).flatMap(Double.init),
              let height = firstMatch(coverHeightRegex, in: html).flatMap(Double.init),
              width > 0,
              height > 0 else {
            return nil
        }
        return width / height
    }

    private static func metadataFromTitle(_ rawTitle: String) -> (displayTitle: String, size: String?, imageCount: Int?) {
        guard let match = metadataRegex.firstMatch(in: rawTitle, range: NSRange(rawTitle.startIndex..<rawTitle.endIndex, in: rawTitle)),
              let sizeRange = Range(match.range(at: 1), in: rawTitle),
              let countRange = Range(match.range(at: 2), in: rawTitle) else {
            return (rawTitle, nil, nil)
        }
        let title = metadataRegex.stringByReplacingMatches(
            in: rawTitle,
            range: NSRange(rawTitle.startIndex..<rawTitle.endIndex, in: rawTitle),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, String(rawTitle[sizeRange]), Int(rawTitle[countRange]))
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid regex pattern: \(pattern)")
        }
    }

    private nonisolated static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private nonisolated static func decodeHTML(_ value: String) -> String? {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&#8211;", with: "-")
            .removingPercentEncoding ?? value
    }
}

private actor HTMLRequestCoalescer {
    private var tasks: [URL: Task<String, Error>] = [:]

    func value(for url: URL, operation: @escaping @Sendable () async throws -> String) async throws -> String {
        if let task = tasks[url] {
            return try await task.value
        }

        let task = Task {
            try await operation()
        }
        tasks[url] = task

        defer {
            tasks[url] = nil
        }
        return try await task.value
    }
}
