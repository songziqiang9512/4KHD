import Foundation

enum DetailPageHTMLResolver {
    static func resolve(pageURL: URL) async throws -> ResolvedImagePage {
        if let cached = DetailPageImageCache.shared.urls(for: pageURL) {
            return cached
        }

        let html: String
        do {
            html = try await fetchHTML(pageURL)
        } catch {
            guard let localHTML = LocalDetailHTMLStore.html(for: pageURL) else {
                throw error
            }
            html = localHTML
        }
        try Task.checkCancellation()

        let page = try parse(html: html, pageURL: pageURL)
        try Task.checkCancellation()
        DetailPageImageCache.shared.store(page)
        return page
    }

    private nonisolated static func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .returnCacheDataElseLoad
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

    private nonisolated static func parse(html: String, pageURL: URL) throws -> ResolvedImagePage {
        let content = galleryContent(in: html)
        let imageURLs = orderedUnique(urls(in: content).map(GalleryImageURLNormalizer.normalized).filter(isGalleryImageURL))
        let pageURLs = orderedUnique(pageLinks(in: html, baseURL: pageURL))

        guard !imageURLs.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        return ResolvedImagePage(pageURL: pageURL, imageURLs: imageURLs, pageURLs: pageURLs)
    }

    private nonisolated static func galleryContent(in html: String) -> String {
        let lower = html.lowercased()
        let contentStart = lower.range(of: "entry-content")?.lowerBound ?? html.startIndex
        let start = lower[contentStart...].range(of: ">")?.upperBound ?? contentStart
        let endMarkers = [
            "<div class=\"page-link-box\"",
            "<div id=\"basice\"",
            "<p id=\"khd\""
        ]
        let end = endMarkers
            .compactMap { lower[start...].range(of: $0)?.lowerBound }
            .min() ?? html.endIndex
        return String(html[start..<end])
    }

    private nonisolated static func urls(in html: String) -> [URL] {
        let pattern = #"(?:href|src|data-src|data-lazy-src)=["']([^"']+)["']"#
        return matches(pattern: pattern, in: html)
            .compactMap { decodeHTML($0) }
            .compactMap(URL.init(string:))
    }

    private nonisolated static func pageLinks(in html: String, baseURL: URL) -> [URL] {
        let pattern = #"<a[^>]+class=["'][^"']*page-numbers[^"']*["'][^>]+href=["']([^"']+)["']"#
        let explicitPages = matches(pattern: pattern, in: html)
            .compactMap { decodeHTML($0) }
            .compactMap(URL.init(string:))

        guard !explicitPages.isEmpty else { return [baseURL] }
        let basePage = baseURL.trailingPageNumber == nil ? baseURL : baseURL.deletingLastPathComponent()
        return [basePage] + explicitPages.filter { $0.isSameDetailPath(as: basePage) }
    }

    private nonisolated static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: text) else {
                return nil
            }
            return String(text[matchRange])
        }
    }

    private nonisolated static func orderedUnique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private nonisolated static func isGalleryImageURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        guard value.contains("pic.4khd.com") || value.contains("img.4khd.com") || value.contains("i0.wp.com") else {
            return false
        }
        return !value.contains("w1090-h1500-p-k-no-rw")
    }

    private nonisolated static func decodeHTML(_ value: String) -> String? {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#038;", with: "&")
            .removingPercentEncoding ?? value
    }
}
