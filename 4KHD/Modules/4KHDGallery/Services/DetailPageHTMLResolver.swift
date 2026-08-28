import Foundation

enum DetailPageHTMLResolver {
    private static let requestCoalescer = DetailHTMLRequestCoalescer()

    static func resolve(pageURL: URL) async throws -> ResolvedImagePage {
        if let cached = DetailPageImageCache.shared.urls(for: pageURL) {
            return cached
        }

        let html = try await requestCoalescer.value(for: pageURL) {
            try await fetchHTML(pageURL)
        }
        try Task.checkCancellation()

        let page = try parse(html: html, pageURL: pageURL)
        try Task.checkCancellation()
        DetailPageImageCache.shared.store(page)
        return page
    }

    private nonisolated static func fetchHTML(_ url: URL) async throws -> String {
        let request = try GalleryRequestFactory.makeHTMLRequest(url: url)
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

    private nonisolated static func parse(html: String, pageURL: URL) throws -> ResolvedImagePage {
        let content = galleryContent(in: html)
        let imageURLs = orderedUnique(urls(in: content).map(GalleryImageURLNormalizer.normalized).filter(isGalleryImageURL))
        let pageURLs = orderedUnique(pageLinks(in: html, baseURL: pageURL))
        let recommendations = extractRecommendations(from: html, pageURL: pageURL)

        guard !imageURLs.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        return ResolvedImagePage(
            pageURL: pageURL,
            imageURLs: imageURLs,
            pageURLs: pageURLs,
            recommendations: recommendations
        )
    }

    /// Extracts the cards inside 4KHD's `#basicE` "Read More" block.
    /// This is deliberately separate from `galleryContent(in:)`, whose end marker
    /// prevents recommendation covers from becoming image slots.
    nonisolated static func extractRecommendations(
        from html: String,
        pageURL: URL
    ) -> [OnlineGalleryRecommendation] {
        guard let container = matches(regex: recommendationContainerRegex, in: html).first else { return [] }
        let range = NSRange(container.startIndex..<container.endIndex, in: container)
        var seen = Set<String>()

        return recommendationAnchorRegex.matches(in: container, range: range).compactMap { result in
            guard let anchorRange = Range(result.range, in: container) else { return nil }
            let anchor = String(container[anchorRange])
            guard let href = matches(regex: recommendationHrefRegex, in: anchor).first.flatMap(decodeHTML),
                  let detailURL = OnlineSourcePolicy.resolvedURL(
                    href,
                    relativeTo: pageURL,
                    source: .gallery,
                    resource: .html
                  ),
                  detailURL.path.contains("/content/"),
                  detailURL.pathExtension.lowercased() == "html",
                  !detailURL.isSameDetailPath(as: pageURL),
                  seen.insert(detailURL.absoluteString).inserted else {
                return nil
            }

            let coverURL = matches(regex: recommendationImageRegex, in: anchor).first
                .flatMap(decodeHTML)
                .flatMap {
                    OnlineSourcePolicy.resolvedURL(
                        $0,
                        relativeTo: pageURL,
                        source: .gallery,
                        resource: .media
                    )
                }
                .map(GalleryImageURLNormalizer.normalized)
            let rawTitle = matches(regex: recommendationTitleRegex, in: anchor).first
                .map(stripTags)
                .flatMap(decodeHTML)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? detailURL.deletingPathExtension().lastPathComponent
            let title = recommendationDisplayTitle(rawTitle)

            return OnlineGalleryRecommendation(
                title: title,
                detailURL: detailURL,
                coverURL: coverURL,
                coverAspectRatio: nil,
                imageCount: recommendationImageCount(rawTitle)
            )
        }
    }

    private nonisolated static func galleryContent(in html: String) -> String {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        let contentRange = nsHTML.range(of: "entry-content", options: .caseInsensitive, range: fullRange)
        let contentStart = contentRange.location == NSNotFound ? 0 : contentRange.location
        let startSearchRange = NSRange(location: contentStart, length: nsHTML.length - contentStart)
        let startMarker = nsHTML.range(of: ">", options: [], range: startSearchRange)
        let start = startMarker.location == NSNotFound ? contentStart : startMarker.upperBound
        let endMarkers = [
            "<div class=\"page-link-box\"",
            "<div id=\"basice\"",
            "<p id=\"khd\""
        ]
        let endSearchRange = NSRange(location: start, length: nsHTML.length - start)
        let end = endMarkers
            .map { nsHTML.range(of: $0, options: .caseInsensitive, range: endSearchRange).location }
            .filter { $0 != NSNotFound }
            .min() ?? nsHTML.length
        guard start < end else { return "" }
        return nsHTML.substring(with: NSRange(location: start, length: end - start))
    }

    private nonisolated static func urls(in html: String) -> [URL] {
        return matches(regex: urlExtractionRegex, in: html)
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
        let anchorURLs = matches(regex: pageAnchorRegex, in: html)
            .compactMap { decodeHTML($0) }
            .compactMap(URL.init(string:))

        let basePage = stripTrailingPageSegment(from: baseURL)
        let basePageString = basePage.absoluteString

        let sameGalleryAnchors = anchorURLs.filter { $0.isSameDetailPath(as: basePage) }

        var maxPageNumber = 1
        for url in sameGalleryAnchors {
            if let n = url.detailPageNumber { maxPageNumber = max(maxPageNumber, n) }
        }
        for regex in [currentLiRegex, currentSpanRegex] {
            if let text = matches(regex: regex, in: html).first,
               let n = Int(text.replacingOccurrences(of: ",", with: "")) {
                maxPageNumber = max(maxPageNumber, n)
            }
        }
        if let n = baseURL.detailPageNumber {
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
        url.canonicalDetailPageURL
    }

    // Cached regexes to avoid recompilation on every call.
    // Invalid patterns trigger an assertion in debug builds and gracefully
    // fall back to a no-match regex in release, rather than crashing.
    private nonisolated static let urlExtractionRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"(?:href|src|data-src|data-lazy-src)=["']([^"']+)["']"#,
                options: [.caseInsensitive]
            )
        } catch {
            assertionFailure("Invalid urlExtractionRegex: \(error)")
            return DetailPageHTMLResolver.noMatchRegex
        }
    }()
    private nonisolated static let pageAnchorRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"<a[^>]+class=["'][^"']*page-numbers[^"']*["'][^>]+href=["']([^"']+)["']"#,
                options: [.caseInsensitive]
            )
        } catch {
            assertionFailure("Invalid pageAnchorRegex: \(error)")
            return DetailPageHTMLResolver.noMatchRegex
        }
    }()
    private nonisolated static let currentLiRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"<li[^>]+class=["'][^"']*current[^"']*["'][^>]*>\s*<span[^>]*>\s*([0-9,]+)\s*</span>"#,
                options: [.caseInsensitive]
            )
        } catch {
            assertionFailure("Invalid currentLiRegex: \(error)")
            return DetailPageHTMLResolver.noMatchRegex
        }
    }()
    private nonisolated static let currentSpanRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"<span[^>]+class=["'][^"']*(?:page-numbers\s+current|current\s+page-numbers)[^"']*["'][^>]*>\s*([0-9,]+)\s*</span>"#,
                options: [.caseInsensitive]
            )
        } catch {
            assertionFailure("Invalid currentSpanRegex: \(error)")
            return DetailPageHTMLResolver.noMatchRegex
        }
    }()
    private nonisolated static let recommendationContainerRegex = regex(
        #"<div\b[^>]*\bid=["']basicE["'][^>]*>([\s\S]*?)</div>"#
    )
    private nonisolated static let recommendationAnchorRegex = regex(
        #"<a\b[^>]*href=["'][^"']+["'][^>]*>[\s\S]*?</a>"#
    )
    private nonisolated static let recommendationHrefRegex = regex(
        #"<a\b[^>]*href=["']([^"']+)["']"#
    )
    private nonisolated static let recommendationImageRegex = regex(
        #"<img\b[^>]*(?:data-src|src)=["']([^"']+)["']"#
    )
    private nonisolated static let recommendationTitleRegex = regex(
        #"<p\b[^>]*>([\s\S]*?)</p>"#
    )
    private nonisolated static let recommendationImageCountRegex = regex(
        #"(\d+)\s*photos?"#
    )

    /// A regex that matches nothing — safe fallback for invalid pattern errors.
    private nonisolated static let noMatchRegex = try! NSRegularExpression(pattern: "$^", options: [])

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            assertionFailure("Invalid recommendation regex: \(error)")
            return noMatchRegex
        }
    }

    private nonisolated static func matches(regex: NSRegularExpression, in text: String) -> [String] {
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

    private nonisolated static func recommendationImageCount(_ title: String) -> Int? {
        matches(regex: recommendationImageCountRegex, in: title).first.flatMap(Int.init)
    }

    private nonisolated static func recommendationDisplayTitle(_ title: String) -> String {
        title.replacingOccurrences(
            of: #"\s*[\[(][^\])]*\d+\s*photos?[^\])]*[\])]\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private nonisolated static func isGalleryImageURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        guard OnlineSourcePolicy.allows(url, source: .gallery, resource: .media) else { return false }
        return !value.contains("w1090-h1500-p-k-no-rw")
    }

    private nonisolated static func decodeHTML(_ value: String) -> String? {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&#8211;", with: "-")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8220;", with: "“")
            .replacingOccurrences(of: "&#8221;", with: "”")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .removingPercentEncoding ?? value
    }
}

private actor DetailHTMLRequestCoalescer {
    private struct Entry {
        let task: Task<String, Error>
        var waiters: Set<UUID>
    }

    private var entries: [URL: Entry] = [:]

    func value(for url: URL, operation: @escaping @Sendable () async throws -> String) async throws -> String {
        let waiterID = UUID()
        let task: Task<String, Error>
        if var entry = entries[url] {
            entry.waiters.insert(waiterID)
            entries[url] = entry
            task = entry.task
        } else {
            task = Task { try await operation() }
            entries[url] = Entry(task: task, waiters: [waiterID])
        }

        return try await withTaskCancellationHandler {
            do {
                let value = try await task.value
                try Task.checkCancellation()
                release(waiterID, for: url, cancelsTaskWhenLast: false)
                return value
            } catch {
                release(waiterID, for: url, cancelsTaskWhenLast: error is CancellationError)
                throw error
            }
        } onCancel: {
            Task { await self.release(waiterID, for: url, cancelsTaskWhenLast: true) }
        }
    }

    private func release(_ waiterID: UUID, for url: URL, cancelsTaskWhenLast: Bool) {
        guard var entry = entries[url], entry.waiters.remove(waiterID) != nil else { return }
        guard entry.waiters.isEmpty else {
            entries[url] = entry
            return
        }
        entries[url] = nil
        if cancelsTaskWhenLast {
            entry.task.cancel()
        }
    }
}
