import Foundation

enum MissKonDetailResolver {
    private static let requestCoalescer = MissKonDetailHTMLRequestCoalescer()
    private static let pageLinkCurrentRegex = regex(#"<span\s+class=["'][^"']*post-page-numbers\s+current[^"']*["'][^>]*>\s*(\d+)\s*</span>"#)
    private static let pageLinkAnchorRegex = regex(#"<a[^>]+class=["'][^"']*post-page-numbers[^"']*["'][^>]+href=["']([^"']+)["'][^>]*>\s*(\d+)\s*</a>"#)

    static func resolve(pageURL: URL) async throws -> MissKonResolvedImagePage {
        let html = try await requestCoalescer.value(for: pageURL) {
            try await fetchHTML(pageURL)
        }

        let imageURLs = extractImageURLs(from: html)
        guard !imageURLs.isEmpty else { throw URLError(.cannotParseResponse) }

        let pageURLs = resolvePageURLs(from: html, baseURL: pageURL)
        return MissKonResolvedImagePage(pageURL: pageURL, imageURLs: imageURLs, pageURLs: pageURLs)
    }

    private static func fetchHTML(_ url: URL) async throws -> String {
        let request = MissKonRequestFactory.makeHTMLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let lower = html.lowercased()

        // Find entry div start
        guard let entryStart = lower.range(of: "<div class=\"entry\">")?.upperBound
                ?? lower.range(of: "<div class=\"entry ")?.upperBound else {
            return []
        }
        let afterEntryStart = html.index(entryStart, offsetBy: 0)
        let entryTail = String(html[afterEntryStart...])

        // Find all page-link divs within the entry area
        let pageLinkPattern = regex(#"<div\s+class=["']page-link["']"#)
        let pageLinkMatches = pageLinkPattern.matches(
            in: entryTail.lowercased(),
            range: NSRange(entryTail.startIndex..<entryTail.endIndex, in: entryTail)
        )

        // Find entry end marker
        let entryEndMarker = "</div><!-- .entry"
        let entryEndRange = entryTail.lowercased().range(of: entryEndMarker)

        // Determine the content range for image extraction
        let contentStart: String.Index
        let contentEnd: String.Index

        if pageLinkMatches.count >= 2,
           let topRange = Range(pageLinkMatches[0].range, in: entryTail),
           let bottomRange = Range(pageLinkMatches[1].range, in: entryTail) {
            // Standard case: images between top and bottom page-link divs
            let topEnd = topRange.upperBound
            let afterTop = entryTail[topEnd...]
            if let divClose = afterTop.range(of: "</div>") {
                contentStart = afterTop.index(divClose.upperBound, offsetBy: 0)
            } else {
                contentStart = topEnd
            }
            contentEnd = bottomRange.lowerBound
        } else if pageLinkMatches.count == 1,
                  let plRange = Range(pageLinkMatches[0].range, in: entryTail) {
            // Only one page-link: extract content after it
            let plEnd = plRange.upperBound
            let afterPL = entryTail[plEnd...]
            if let divClose = afterPL.range(of: "</div>") {
                contentStart = afterPL.index(divClose.upperBound, offsetBy: 0)
            } else {
                contentStart = plEnd
            }
            if let endRange = entryEndRange {
                contentEnd = endRange.lowerBound
            } else {
                contentEnd = entryTail.endIndex
            }
        } else {
            // No page-link: extract from entry start to entry end
            contentStart = entryTail.startIndex
            if let endRange = entryEndRange {
                contentEnd = endRange.lowerBound
            } else {
                contentEnd = entryTail.endIndex
            }
        }

        guard contentStart < contentEnd else { return [] }
        let content = String(entryTail[contentStart..<contentEnd])

        // Extract image URLs — misskon uses data-src for lazy loading, with src fallback
        let dataSrcPattern = #"<img[^>]+data-src=["']([^"']+)["']"#
        let srcPattern = #"<img[^>]+src=["'](https?://[^"']+)["']"#
        let dataSrcUrls = matches(pattern: dataSrcPattern, in: content)
        let srcUrls = matches(pattern: srcPattern, in: content)
            .filter { !$0.hasPrefix("data:image/svg") }
        let allUrls = dataSrcUrls + srcUrls
        let urls = allUrls
            .compactMap { $0.removingPercentEncoding }
            .compactMap(URL.init(string:))
            .filter { url in
                let host = url.host?.lowercased() ?? ""
                return host.contains("misskon.com")
            }
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

        let baseString = baseURL.absoluteString.hasSuffix("/")
            ? baseURL.absoluteString
            : baseURL.absoluteString + "/"

        return (1...maxPage).compactMap { pageNum in
            if pageNum == 1 { return baseURL }
            return URL(string: "\(baseString)\(pageNum)/")
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
