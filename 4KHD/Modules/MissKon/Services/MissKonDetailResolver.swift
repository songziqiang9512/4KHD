import Foundation

enum MissKonDetailResolver {
    private static let requestCoalescer = MissKonDetailHTMLRequestCoalescer()
    private static let pageLinkCurrentRegex = regex(#"<span\s+class=["'][^"']*post-page-numbers\s+current[^"']*["'][^>]*>\s*(\d+)\s*</span>"#)
    private static let pageLinkAnchorRegex = regex(#"<a(?=[^>]*class=["'][^"']*post-page-numbers[^"']*["'])[^>]*href=["']([^"']+)["'][^>]*>\s*(\d+)\s*</a>"#)
    /// 详情页底部的 "Download link: MediaFire" 按钮。href 是 ouo.io 短链
    /// (Cloudflare 防护,无法在运行时跟随出真实链接),原样提供给用户浏览器打开。
    private static let mediaFireAnchorRegex = regex(#"<a\b(?=[^>]*href=["']([^"']+)["'])[^>]*>(?:(?!</a>).)*Download link:\s*MediaFire"#)

    static func resolve(pageURL: URL) async throws -> MissKonResolvedImagePage {
        if let cached = DetailPageImageCache.shared.page(for: pageURL),
           let metadata = MissKonDetailMetadataCache.shared.metadata(for: pageURL) {
            return MissKonResolvedImagePage(
                pageURL: cached.pageURL,
                imageURLs: cached.imageURLs,
                pageURLs: cached.pageURLs,
                mediaFireURL: metadata.mediaFireURL
            )
        }

        let html = try await requestCoalescer.value(for: pageURL) {
            try await fetchHTML(pageURL)
        }

        try Task.checkCancellation()

        let imageURLs = extractImageURLs(from: html)
        guard !imageURLs.isEmpty else { throw URLError(.cannotParseResponse) }

        try Task.checkCancellation()

        let pageURLs = resolvePageURLs(from: html, baseURL: pageURL)
        let mediaFireURL = extractMediaFireDownloadLink(from: html)
        let page = MissKonResolvedImagePage(
            pageURL: pageURL,
            imageURLs: imageURLs,
            pageURLs: pageURLs,
            mediaFireURL: mediaFireURL
        )
        DetailPageImageCache.shared.store(
            pageURL: page.pageURL,
            imageURLs: page.imageURLs,
            pageURLs: page.pageURLs
        )
        MissKonDetailMetadataCache.shared.store(pageURL: page.pageURL, mediaFireURL: page.mediaFireURL)
        return page
    }

    /// 提取 MediaFire 下载按钮的短链 URL;没有该按钮时返回 nil。
    static func extractMediaFireDownloadLink(from html: String) -> URL? {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = mediaFireAnchorRegex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let urlRange = Range(match.range(at: 1), in: html) else { return nil }
        return URL(string: String(html[urlRange]))
    }

    private static func fetchHTML(_ url: URL) async throws -> String {
        let request = try MissKonRequestFactory.makeHTMLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try OnlineSourcePolicy.validate(response, source: .missKon, resource: .html)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }

    /// Extracts image URLs from the detail page HTML.
    ///
    /// misskon detail pages have this structure:
    /// ```
    /// <div class="entry">
    ///     <div class="page-link"> ...top pagination... </div>
    ///     <p> <img data-src="..." /> <br /> ... </p>
    ///     <div class="page-link"> ...bottom pagination... </div>
    /// </div><!-- .entry /-->
    /// ```
    ///
    /// We need to extract from between the two page-link divs (or after the first
    /// if only one exists, or from the entire entry if none exist).
    private static func extractImageURLs(from html: String) -> [URL] {
        // Use NSString for case-insensitive range searches to avoid String.Index
        // cross-contamination between lowercased and original strings.
        let nsHTML = html as NSString

        // Find entry div start (case-insensitive)
        let entryStartRange = nsHTML.range(of: "<div class=\"entry\">", options: .caseInsensitive)
        let entryAltRange = nsHTML.range(of: "<div class=\"entry \"", options: .caseInsensitive)
        let entryRange = entryStartRange.location != NSNotFound ? entryStartRange : entryAltRange
        guard entryRange.location != NSNotFound else { return [] }
        let entryStart = entryRange.upperBound
        let entryTail = nsHTML.substring(from: entryStart)
        let nsEntryTail = entryTail as NSString

        // Find all page-link divs within the entry area (case-insensitive)
        let pageLinkPattern = regex(#"<div\s+class=["'][^"']*page-link[^"']*["']"#)
        let pageLinkMatches = pageLinkPattern.matches(
            in: entryTail,
            range: NSRange(location: 0, length: nsEntryTail.length)
        )

        // Find entry end marker
        let entryEndMarker = "</div><!-- .entry"
        let entryEndLoc = nsEntryTail.range(of: entryEndMarker, options: .caseInsensitive).location

        // Determine the content range for image extraction (NSRange-based)
        let contentStart: Int
        let contentEnd: Int

        if pageLinkMatches.count >= 2 {
            // Standard case: images between top and bottom page-link divs
            let topRange = pageLinkMatches[0].range
            let bottomRange = pageLinkMatches[1].range
            // Find the closing </div> after the top page-link div
            let afterTop = nsEntryTail.substring(from: topRange.upperBound)
            let divClose = (afterTop as NSString).range(of: "</div>")
            contentStart = topRange.upperBound + (divClose.location != NSNotFound ? divClose.upperBound : 0)
            contentEnd = bottomRange.location
        } else if pageLinkMatches.count == 1 {
            // Only one page-link: extract content after it
            let plRange = pageLinkMatches[0].range
            let afterPL = nsEntryTail.substring(from: plRange.upperBound)
            let divClose = (afterPL as NSString).range(of: "</div>")
            contentStart = plRange.upperBound + (divClose.location != NSNotFound ? divClose.upperBound : 0)
            contentEnd = entryEndLoc != NSNotFound ? entryEndLoc : nsEntryTail.length
        } else {
            // No page-link: extract from entry start to entry end
            contentStart = 0
            contentEnd = entryEndLoc != NSNotFound ? entryEndLoc : nsEntryTail.length
        }

        guard contentStart < contentEnd else { return [] }
        let content = nsEntryTail.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))

        // Extract image URLs — misskon uses data-src for lazy loading, with src fallback
        let dataSrcPattern = #"<img[^>]+data-src=["']([^"']+)["']"#
        let srcPattern = #"<img[^>]+src=["'](https?://[^"']+)["']"#
        let dataSrcUrls = matches(pattern: dataSrcPattern, in: content)
        let srcUrls = matches(pattern: srcPattern, in: content)
            .filter { !$0.hasPrefix("data:image/svg") }
        let allUrls = dataSrcUrls + srcUrls
        let urls = allUrls
            .compactMap { $0.removingPercentEncoding ?? decodeHTML($0) }
            .compactMap(URL.init(string:))
            .filter { OnlineSourcePolicy.allows($0, source: .missKon, resource: .media) }
        return orderedUnique(urls)
    }

    /// Resolves all page URLs for a detail page.
    ///
    /// The page-link nav only shows a few page numbers (e.g. 1-4), but by scanning
    /// all anchor tags and the current page indicator we can determine the max page.
    /// Page URL format: `{baseURL}{N}/` (page 1 = baseURL without number)
    private static func resolvePageURLs(from html: String, baseURL: URL) -> [URL] {
        guard let currentText = firstMatch(pageLinkCurrentRegex, in: html),
              let currentPage = Int(currentText) else {
            return [baseURL]
        }

        let anchorMatches = allMatches(pageLinkAnchorRegex, in: html)
        var pageNumbers = Set([currentPage])
        for (_, pageText) in anchorMatches {
            if let pageNum = Int(pageText) {
                pageNumbers.insert(pageNum)
            }
        }

        let maxPage = pageNumbers.max() ?? currentPage
        guard maxPage > 1 else { return [baseURL] }

        // Strip any existing page number suffix to get the canonical page-1 URL.
        // E.g., "https://misskon.com/post/2/" → "https://misskon.com/post/"
        let absString = baseURL.absoluteString
        let canonicalBase: String
        if currentPage > 1, let slashRange = absString.range(of: "/\(currentPage)/", options: .backwards) {
            canonicalBase = String(absString[..<slashRange.lowerBound]) + "/"
        } else {
            canonicalBase = absString.hasSuffix("/") ? absString : absString + "/"
        }

        return (1...maxPage).compactMap { pageNum in
            if pageNum == 1 { return URL(string: canonicalBase) }
            return URL(string: "\(canonicalBase)\(pageNum)/")
        }
    }

    private static func orderedUnique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
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

    /// Decodes common HTML entities in URL strings (mirrors `DetailPageHTMLResolver.decodeHTML`).
    private nonisolated static func decodeHTML(_ value: String) -> String? {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#038;", with: "&")
            .removingPercentEncoding ?? value
    }

    private static func allMatches(_ regex: NSRegularExpression, in text: String) -> [(url: String, page: String)] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 2,
                  let urlRange = Range(result.range(at: 1), in: text),
                  let pageRange = Range(result.range(at: 2), in: text) else { return nil }
            return (String(text[urlRange]), String(text[pageRange]))
        }
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[matchRange])
        }
    }
}

private actor MissKonDetailHTMLRequestCoalescer {
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
