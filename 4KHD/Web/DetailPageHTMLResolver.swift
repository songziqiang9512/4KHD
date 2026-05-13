import Foundation

enum DetailPageHTMLResolver {
    static func resolve(pageURL: URL) async throws -> ResolvedImagePage {
        if let cached = DetailPageImageCache.shared.urls(for: pageURL) {
            return cached
        }

        let html = try await fetchHTML(pageURL)
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
        // 4khd 的页导航是 WordPress page-link-box：
        //   <li class="numpages current"><span>1</span></li>
        //   <li class="numpages"><a class="page-numbers" href=".../N">N</a></li>
        // 当画廊页数较多时，会出现 `1 2 3 ... 20` 这种省略号写法，锚点里只有首尾几页。
        // 所以这里不直接用锚点列表，而是：
        //   1) 找出所有锚点指向 + 当前页（li.current）+ baseURL 自身能读到的最大页号
        //   2) 按 URL 模板 `<detail.html>/N` 把 1..max 全部生成出来
        // 这样不论画廊有 5 页还是 50 页，中间也不会漏。
        let anchorPattern = #"<a[^>]+class=["'][^"']*page-numbers[^"']*["'][^>]+href=["']([^"']+)["']"#
        // current 既可能挂在 li 上（4khd 现状），也可能挂在 span 上（其它 WP 主题），都兼容。
        let currentLiPattern = #"<li[^>]+class=["'][^"']*current[^"']*["'][^>]*>\s*<span[^>]*>\s*([0-9,]+)\s*</span>"#
        let currentSpanPattern = #"<span[^>]+class=["'][^"']*(?:page-numbers\s+current|current\s+page-numbers)[^"']*["'][^>]*>\s*([0-9,]+)\s*</span>"#

        let anchorURLs = matches(pattern: anchorPattern, in: html)
            .compactMap { decodeHTML($0) }
            .compactMap(URL.init(string:))

        // 用字符串方式精确剥掉 baseURL 末尾的 `/N`，保证 page1 URL 和 detailURL 字面相等。
        let basePage = stripTrailingPageSegment(from: baseURL)
        let basePageString = basePage.absoluteString

        let sameGalleryAnchors = anchorURLs.filter { $0.isSameDetailPath(as: basePage) }

        var maxPageNumber = 1
        for url in sameGalleryAnchors {
            if let n = url.trailingPageNumber { maxPageNumber = max(maxPageNumber, n) }
        }
        for pattern in [currentLiPattern, currentSpanPattern] {
            if let text = matches(pattern: pattern, in: html).first,
               let n = Int(text.replacingOccurrences(of: ",", with: "")) {
                maxPageNumber = max(maxPageNumber, n)
            }
        }
        if let n = baseURL.trailingPageNumber {
            maxPageNumber = max(maxPageNumber, n)
        }

        guard maxPageNumber >= 1 else { return [basePage] }

        return (1...maxPageNumber).compactMap { pageNum -> URL? in
            if pageNum == 1 { return basePage }
            return URL(string: "\(basePageString)/\(pageNum)")
        }
    }

    /// 如果 URL 形如 `.../foo.html/N`，把末尾 `/N` 整段剥掉；否则原样返回。
    /// 用纯字符串处理，避开 `URL.deletingLastPathComponent()` 会引入尾斜杠的问题。
    private nonisolated static func stripTrailingPageSegment(from url: URL) -> URL {
        guard let pageNumber = url.trailingPageNumber else { return url }
        let suffix = "/\(pageNumber)"
        let raw = url.absoluteString
        guard raw.hasSuffix(suffix) else { return url }
        let stripped = String(raw.dropLast(suffix.count))
        return URL(string: stripped) ?? url
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
