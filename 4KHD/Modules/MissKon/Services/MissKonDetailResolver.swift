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
           let recommendations = cached.recommendations,
           let metadata = MissKonDetailMetadataCache.shared.metadata(for: pageURL) {
            return MissKonResolvedImagePage(
                pageURL: cached.pageURL,
                imageURLs: cached.imageURLs,
                pageURLs: cached.pageURLs,
                mediaFireURL: metadata.mediaFireURL,
                recommendations: recommendations
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
        let recommendations = extractRecommendations(from: html, pageURL: pageURL)
        let page = MissKonResolvedImagePage(
            pageURL: pageURL,
            imageURLs: imageURLs,
            pageURLs: pageURLs,
            mediaFireURL: mediaFireURL,
            recommendations: recommendations
        )
        DetailPageImageCache.shared.store(
            pageURL: page.pageURL,
            imageURLs: page.imageURLs,
            pageURLs: page.pageURLs,
            recommendations: page.recommendations
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

    /// Extracts cards emitted by Yet Another Related Posts Plugin (YARPP).
    /// The parser keys off the card class rather than surrounding layout so a
    /// theme wrapper change cannot make unrelated page links look recommended.
    nonisolated static func extractRecommendations(
        from html: String,
        pageURL: URL
    ) -> [OnlineGalleryRecommendation] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()

        return recommendationAnchorRegex.matches(in: html, range: range).compactMap { result in
            guard let anchorRange = Range(result.range, in: html) else { return nil }
            let anchor = String(html[anchorRange])
            guard let href = firstMatch(recommendationHrefRegex, in: anchor).flatMap(decodeHTML),
                  let detailURL = OnlineSourcePolicy.resolvedURL(
                    href,
                    relativeTo: pageURL,
                    source: .missKon,
                    resource: .html
                  ),
                  !detailURL.isSameDetailPath(as: pageURL),
                  seen.insert(detailURL.absoluteString).inserted else {
                return nil
            }

            let coverValue = firstMatch(recommendationDataSourceRegex, in: anchor)
                ?? firstMatch(recommendationSourceRegex, in: anchor)
            let coverURL = coverValue
                .flatMap(decodeHTML)
                .flatMap {
                    OnlineSourcePolicy.resolvedURL(
                        $0,
                        relativeTo: pageURL,
                        source: .missKon,
                        resource: .media
                    )
                }
            let rawTitle = (firstMatch(recommendationTitleRegex, in: anchor)
                ?? firstMatch(recommendationAnchorTitleRegex, in: anchor))
                .map(stripTags)
                .flatMap(decodeHTML)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? detailURL.lastPathComponent
            let imageCount = firstMatch(recommendationImageCountRegex, in: rawTitle).flatMap(Int.init)
            let title = recommendationDisplayTitle(rawTitle)
            let width = firstMatch(recommendationWidthRegex, in: anchor).flatMap(Double.init)
            let height = firstMatch(recommendationHeightRegex, in: anchor).flatMap(Double.init)
            let aspectRatio = if let width, let height, width > 0, height > 0 {
                width / height
            } else {
                coverURL.flatMap(RemoteImageURLAspectRatio.aspectRatio)
            }

            return OnlineGalleryRecommendation(
                title: title,
                detailURL: detailURL,
                coverURL: coverURL,
                coverAspectRatio: aspectRatio,
                imageCount: imageCount
            )
        }
    }

    private static func fetchHTML(_ url: URL) async throws -> String {
        let request = try MissKonRequestFactory.makeHTMLRequest(url: url)
        let (data, response) = try await OnlineSourceSession.missKonHTML.data(for: request)
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

    private nonisolated static let recommendationAnchorRegex = regex(
        #"<a\b(?=[^>]*class=["'][^"']*yarpp-thumbnail[^"']*["'])[^>]*>[\s\S]*?</a>"#
    )
    private nonisolated static let recommendationHrefRegex = regex(#"href=["']([^"']+)["']"#)
    private nonisolated static let recommendationDataSourceRegex = regex(#"<img\b[^>]*data-src=["']([^"']+)["']"#)
    private nonisolated static let recommendationSourceRegex = regex(#"<img\b[^>]*src=["']([^"']+)["']"#)
    private nonisolated static let recommendationTitleRegex = regex(
        #"<span\b[^>]*class=["'][^"']*yarpp-thumbnail-title[^"']*["'][^>]*>([\s\S]*?)</span>"#
    )
    private nonisolated static let recommendationAnchorTitleRegex = regex(#"<a\b[^>]*title=["']([^"']+)["']"#)
    private nonisolated static let recommendationImageCountRegex = regex(#"(\d+)\s*(?:photos|pics|images)"#)
    private nonisolated static let recommendationWidthRegex = regex(#"<img\b[^>]*width=["']([0-9]+)["']"#)
    private nonisolated static let recommendationHeightRegex = regex(#"<img\b[^>]*height=["']([0-9]+)["']"#)

    private nonisolated static func recommendationDisplayTitle(_ title: String) -> String {
        title.replacingOccurrences(
            of: #"\s*\([^)]*\d+\s*(?:photos|pics|images)[^)]*\)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid regex pattern: \(pattern)")
        }
    }

    private nonisolated static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
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
            .replacingOccurrences(of: "&#8211;", with: "-")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8220;", with: "“")
            .replacingOccurrences(of: "&#8221;", with: "”")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
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
