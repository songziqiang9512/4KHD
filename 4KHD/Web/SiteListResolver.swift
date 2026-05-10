import Foundation

enum SiteListResolver {
    static func resolve(section: GallerySection) async throws -> [GalleryItem] {
        guard let siteURL = section.siteURL else { return [] }
        let html = try await fetchHTML(siteURL)
        return parse(html: html, section: section)
    }

    private static func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("https://www.4khd.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }

    private static func parse(html: String, section: GallerySection) -> [GalleryItem] {
        listItemHTML(in: html).compactMap { makeItem(from: $0, section: section) }
    }

    private static func listItemHTML(in html: String) -> [String] {
        let pattern = #"<li[^>]+class=["'][^"']*wp-block-post[^"']*["'][\s\S]*?</li>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { result in
            guard let matchRange = Range(result.range, in: html) else { return nil }
            return String(html[matchRange])
        }
    }

    private static func makeItem(from html: String, section: GallerySection) -> GalleryItem? {
        guard let detailURL = firstMatch(#"<a[^>]+href=["']([^"']+/content/[^"']+\.html)["']"#, in: html)
            .flatMap(URL.init(string:)) else {
            return nil
        }
        let coverURL = firstMatch(#"<img[^>]+src=["']([^"']+)["']"#, in: html)
            .flatMap(decodeHTML)
            .flatMap(URL.init(string:))
            .map(GalleryImageURLNormalizer.normalized)
        let rawTitle = firstMatch(#"<h2[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#, in: html)
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
            imageCount: metadata.imageCount ?? 0,
            pageCount: pageCount,
            pageURLs: pageURLs,
            sampleImageURLs: coverURL.map { [$0] } ?? []
        )
    }

    private static func metadataFromTitle(_ rawTitle: String) -> (displayTitle: String, size: String?, imageCount: Int?) {
        let pattern = #"\[([^\]-]+)-(\d+)photos\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: rawTitle, range: NSRange(rawTitle.startIndex..<rawTitle.endIndex, in: rawTitle)),
              let sizeRange = Range(match.range(at: 1), in: rawTitle),
              let countRange = Range(match.range(at: 2), in: rawTitle) else {
            return (rawTitle, nil, nil)
        }
        let title = regex.stringByReplacingMatches(
            in: rawTitle,
            range: NSRange(rawTitle.startIndex..<rawTitle.endIndex, in: rawTitle),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, String(rawTitle[sizeRange]), Int(rawTitle[countRange]))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[matchRange])
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
