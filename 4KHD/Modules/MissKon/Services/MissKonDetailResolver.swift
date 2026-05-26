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

    private static func extractImageURLs(from html: String) -> [URL] {
        let lower = html.lowercased()
        guard let entryStart = lower.range(of: "<div class=\"entry\">")?.upperBound
                ?? lower.range(of: "<div class=\"entry ")?.upperBound
                ?? lower.range(of: "class=\"entry\"")?.upperBound else {
            return []
        }
        let entryHTML = String(html[entryStart...])

        // Find end of entry content (before page-link, tags, or sharing divs)
        let endMarkers = [
            "<div class=\"page-link\"",
            "<div class=\"post-tag\"",
            "<div class=\"share-post\"",
            "<div class=\"post-navigation\"",
            "<div class=\"article-footer\""
        ]
        let end = endMarkers
            .compactMap { entryHTML.lowercased().range(of: $0)?.lowerBound }
            .min() ?? entryHTML.endIndex
        let content = String(entryHTML[..<end])

        // Extract image URLs from data-src attributes (misskon uses lazy loading)
        let pattern = #"<img[^>]+data-src=["']([^"']+)["']"#
        let urls = matches(pattern: pattern, in: content)
            .compactMap { $0.removingPercentEncoding }
            .compactMap(URL.init(string:))
            .filter { url in
                let host = url.host?.lowercased() ?? ""
                return host.contains("misskon.com") || host.contains("tez.misskon.com")
            }
        return orderedUnique(urls)
    }

    private static func resolvePageURLs(from html: String, baseURL: URL) -> [URL] {
        guard let currentText = firstMatch(pageLinkCurrentRegex, in: html),
              let currentPage = Int(currentText) else {
            return [baseURL]
        }

        // Find all page anchors
        let anchorMatches = allMatches(pageLinkAnchorRegex, in: html)
        var pageNumbers = Set([currentPage])
        for (_, pageText) in anchorMatches {
            if let pageNum = Int(pageText) {
                pageNumbers.insert(pageNum)
            }
        }

        let maxPage = pageNumbers.max() ?? currentPage

        // Construct all page URLs following the pattern: baseURL/N/
        if maxPage <= 1 { return [baseURL] }

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
