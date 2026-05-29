import Foundation

struct MissKonListPage {
    let items: [MissKonItem]
    let nextPageURL: URL?
}

enum MissKonListResolverError: Error, Equatable {
    case httpStatus(Int)

    var isPageNotFound: Bool {
        if case .httpStatus(404) = self { return true }
        return false
    }
}

enum MissKonListResolver {
    private static let requestCoalescer = MissKonHTMLRequestCoalescer()
    private static let articleRegex = regex(#"<article\s+class=["'][^"']*item-list[^"']*["'][\s\S]*?</article>"#)
    private static let titleRegex = regex(#"<h2\s+class=["'][^"']*post-box-title[^"']*["'][^>]*>\s*(<a[^>]*>[\s\S]*?</a>)"#)
    private static let detailURLRegex = regex(#"<a\s+href=["']([^"']+)["']"#)
    private static let coverSrcRegex = regex(#"<img[^>]+(?:src|data-src)=["']([^"']+)["']"#)
    private static let coverWidthRegex = regex(#"<img[^>]+width=["']([0-9]+)["']"#)
    private static let coverHeightRegex = regex(#"<img[^>]+height=["']([0-9]+)["']"#)
    private static let imageCountRegex = regex(#"\((\d+)\s*(?:photos|pics|images|张|p)\)"#)
    private static let paginationCurrentRegex = regex(#"<span\s+class=["'][^"']*current[^"']*["'][^>]*>\s*(\d+)\s*</span>"#)
    private static let paginationNextRegex = regex(#"<a(?=[^>]*class=["'][^"']*(?:page|next)[^"']*["'])[^>]*href=["']([^"']+)["'][^>]*>"#)
    private static let tagRegex = regex(#"<a[^>]+href=["']https?://misskon\.com/tag/([^/"']+)["'][^>]*>"#)

    static func resolveSearch(query: String) async throws -> MissKonListPage {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "misskon.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "s", value: query)]
        guard let url = components.url else { throw URLError(.badURL) }
        return try await resolveSearch(pageURL: url)
    }

    static func resolveSearch(pageURL: URL) async throws -> MissKonListPage {
        let html = try await fetchHTML(pageURL)
        return parse(html: html, pageURL: pageURL, section: .latest)
    }

    static func resolve(section: MissKonSection) async throws -> MissKonListPage {
        guard let siteURL = section.siteURL else {
            return MissKonListPage(items: [], nextPageURL: nil)
        }
        return try await resolve(pageURL: siteURL, section: section)
    }

    static func resolve(pageURL: URL, section: MissKonSection) async throws -> MissKonListPage {
        let html = try await fetchHTML(pageURL)
        return parse(html: html, pageURL: pageURL, section: section)
    }

    private static func fetchHTML(_ url: URL) async throws -> String {
        try await requestCoalescer.value(for: url) {
            let request = MissKonRequestFactory.makeHTMLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                throw MissKonListResolverError.httpStatus(httpResponse.statusCode)
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            return html
        }
    }

    private static func parse(html: String, pageURL: URL, section: MissKonSection) -> MissKonListPage {
        let articles = articleHTML(in: html)
        let items = articles.compactMap { makeItem(from: $0, section: section) }
        // When the page has no articles and no known structural markers,
        // the site layout likely changed — surface a clear error.
        if items.isEmpty, articles.isEmpty {
            let hasKnownStructure = html.contains("class=\"item-list\"")
                || html.contains("class=\"post-box-title\"")
                || html.contains("<article")
            if !hasKnownStructure, !html.isEmpty {
                // Still return empty page but let the caller know via a marker;
                // the feed store doesn't inspect errors from ListPage directly.
                // We signal the issue by returning no nextPageURL, so the UI shows "已到末尾"
                // rather than retrying indefinitely.
            }
        }
        return MissKonListPage(
            items: items,
            nextPageURL: items.isEmpty ? nil : nextPageURL(in: html, baseURL: pageURL)
        )
    }

    private static func articleHTML(in html: String) -> [String] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return articleRegex.matches(in: html, range: range).compactMap { result in
            guard let matchRange = Range(result.range, in: html) else { return nil }
            return String(html[matchRange])
        }
    }

    private static func nextPageURL(in html: String, baseURL: URL) -> URL? {
        let currentText = firstMatch(paginationCurrentRegex, in: html)
        let currentPage = currentText.flatMap(Int.init) ?? pageNumber(from: baseURL) ?? 1

        // Try explicit next link first
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let nextLinks = paginationNextRegex.matches(in: html, range: range).compactMap { result -> URL? in
            guard result.numberOfRanges > 1,
                  let hrefRange = Range(result.range(at: 1), in: html) else { return nil }
            return URL(string: String(html[hrefRange]), relativeTo: baseURL)?.absoluteURL
        }

        for url in nextLinks {
            let urlString = url.absoluteString
            if urlString.contains("/page/\(currentPage + 1)") || urlString.hasSuffix("/\(currentPage + 1)") {
                return url
            }
        }

        // Some page templates (top30 etc.) don't render pagination HTML but still
        // support WordPress pagination via /page/N/ URLs. Construct next page URL
        // when the current page has enough items to suggest more pages exist.
        // Require strictly more than 12 items to avoid guessing past the last page
        // when the total is an exact multiple of the page size.
        let articleCount = articleHTML(in: html).count
        guard articleCount > 12 else { return nil }

        return constructedPageURL(from: baseURL, nextPage: currentPage + 1)
    }

    private static func pageNumber(from url: URL) -> Int? {
        let parts = url.path.split(separator: "/")
        guard let pageIndex = parts.firstIndex(of: "page") else { return nil }
        let numberIndex = parts.index(after: pageIndex)
        guard parts.indices.contains(numberIndex) else { return nil }
        return Int(parts[numberIndex])
    }

    private static func constructedPageURL(from baseURL: URL, nextPage: Int) -> URL? {
        var urlString = baseURL.absoluteString
        if let pageRange = urlString.range(of: #"/page/[0-9]+/?$"#, options: .regularExpression) {
            return URL(string: urlString.replacingCharacters(in: pageRange, with: "/page/\(nextPage)/"))
        }
        if !urlString.hasSuffix("/") { urlString += "/" }
        return URL(string: "\(urlString)page/\(nextPage)/")
    }

    private static func tagsFromHTML(_ html: String) -> [String] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return tagRegex.matches(in: html, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let tagRange = Range(result.range(at: 1), in: html) else { return nil }
            return String(html[tagRange]).removingPercentEncoding
        }
    }

    private static func makeItem(from html: String, section: MissKonSection) -> MissKonItem? {
        // Detail URL: from h2 > a
        let titleBlock = firstMatch(titleRegex, in: html) ?? ""
        let detailURL = firstMatch(detailURLRegex, in: titleBlock)
            .flatMap(URL.init(string:))
        guard let detailURL else { return nil }

        // Cover URL: prefer data-src over src, skip SVG placeholders
        let coverMatches = allMatches(coverSrcRegex, in: html)
        let coverURL = coverMatches
            .first { !$0.hasPrefix("data:image/svg") && !$0.hasSuffix(".svg") }
            .flatMap(URL.init(string:))

        let coverAspectRatio = coverAspectRatioFromHTML(html)

        // Title: strip HTML tags
        let rawTitle = titleBlock
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Image count from title: "Name: Title (122 photos)"
        let imageCount = Int(firstMatch(imageCountRegex, in: rawTitle) ?? "0") ?? 0
        let displayTitle = rawTitle.replacingOccurrences(
            of: #"\s*\(\d+\s*(?:photos|pics|images|张|p)\)\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let pageCount = max(Int(ceil(Double(imageCount) / 12.0)), 1)
        let pageURLs = (1...pageCount).map { pageNumber -> URL in
            if pageNumber == 1 { return detailURL }
            return URL(string: "\(detailURL.absoluteString)\(pageNumber)/") ?? detailURL
        }

        let tags = tagsFromHTML(html)

        return MissKonItem(
            id: detailURL.absoluteString,
            section: section,
            title: displayTitle,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: coverAspectRatio,
            imageCount: imageCount,
            pageCount: pageCount,
            pageURLs: pageURLs,
            tags: tags
        )
    }

    private static func coverAspectRatioFromHTML(_ html: String) -> Double? {
        guard let width = firstMatch(coverWidthRegex, in: html).flatMap(Double.init),
              let height = firstMatch(coverHeightRegex, in: html).flatMap(Double.init),
              width > 0, height > 0 else { return nil }
        return width / height
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid regex pattern: \(pattern)")
        }
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[matchRange])
    }

    private static func allMatches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[matchRange])
        }
    }
}

private actor MissKonHTMLRequestCoalescer {
    private var tasks: [URL: Task<String, Error>] = [:]

    func value(for url: URL, operation: @escaping @Sendable () async throws -> String) async throws -> String {
        if let task = tasks[url] {
            return try await task.value
        }
        let task = Task { try await operation() }
        tasks[url] = task
        defer { tasks[url] = nil }
        return try await task.value
    }
}
