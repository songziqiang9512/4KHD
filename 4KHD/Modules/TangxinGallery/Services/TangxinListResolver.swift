import Foundation

nonisolated enum TangxinListResolverError: LocalizedError, Equatable {
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "糖心Vlog 列表数据无法解析"
        }
    }
}

enum TangxinListResolver {
    nonisolated static let searchResultLimit = 200

    private nonisolated static let cardRegex = regex(#"<article class="card"[^>]*>([\s\S]*?)</article>"#)
    private nonisolated static let coverLinkRegex = regex(#"href="(/v/([0-9]+)/)""#)
    private nonisolated static let ariaLabelRegex = regex(#"aria-label="([^"]+)""#)
    private nonisolated static let headingRegex = regex(#"<h[1-6][^>]*>([^<]+)</h[1-6]>"#)
    private nonisolated static let coverImageRegex = regex(#"<img[^>]+src="([^"]+)""#)
    private nonisolated static let durationRegex = regex(#"<span class="duration"[^>]*>([^<]*)</span>"#)
    private nonisolated static let authorLinkRegex = regex(#"href="(/a/([^"]+)/)""#)
    private nonisolated static let authorNameRegex = regex(#"class="nickname"[^>]*>([^<]+)<"#)
    private nonisolated static let tagLinkRegex = regex(
        #"href="(/tag/([^"/]+)/)"[^>]*>([^<]+)</a>"#
    )
    private nonisolated static let tagEntryRegex = regex(
        #"href="(/tag/([^"/]+)/)"[^>]*>\s*<span class="name"[^>]*>([^<]*)</span>\s*<span class="num"[^>]*>([^<]*)</span>"#
    )
    private nonisolated static let authorEntryRegex = regex(
        #"href="(/a/([^"]+)/)"[^>]*>\s*<span class="name"[^>]*>([^<]*)</span>\s*<span class="num"[^>]*>([^<]*)</span>"#
    )
    private nonisolated static let relNextRegex = regex(#"<link[^>]+rel=["']next["'][^>]+href=["']([^"']+)["']"#)
    private nonisolated static let relNextAltRegex = regex(#"<link[^>]+href=["']([^"']+)["'][^>]+rel=["']next["']"#)
    private nonisolated static let pagerNextRegex = regex(
        #"<a[^>]*class="[^"]*pager-link[^"]*"[^>]*href="([^"]+)"[^>]*>[^<]*下一页"#
    )
    private nonisolated static let pagerStatusRegex = regex(#"class="pager-status"[^>]*>\s*([0-9]+)\s*/\s*([0-9]+)"#)
    private nonisolated static let rssItemRegex = regex(#"<item>([\s\S]*?)</item>"#)
    private nonisolated static let rssTitleRegex = regex(#"<title>([\s\S]*?)</title>"#)
    private nonisolated static let rssLinkRegex = regex(#"<link>([\s\S]*?)</link>"#)
    private nonisolated static let rssDescriptionRegex = regex(#"<description>([\s\S]*?)</description>"#)

    static func resolve(url: URL) async throws -> OnlineVideoListPage {
        let requestURL = fetchURL(from: url)
        let request = try TangxinRequestFactory.makeHTMLRequest(url: requestURL)
        let (data, _) = try await TangxinHTTPClient.data(for: request)
        return try await parseConcurrently(data: data, pageURL: url)
    }

    @concurrent
    private nonisolated static func parseConcurrently(data: Data, pageURL: URL) async throws -> OnlineVideoListPage {
        try Task.checkCancellation()
        let page = try parse(data: data, pageURL: pageURL)
        try Task.checkCancellation()
        return page
    }

    nonisolated static func parse(data: Data, pageURL: URL) throws -> OnlineVideoListPage {
        guard let html = String(data: data, encoding: .utf8) else {
            throw TangxinListResolverError.invalidPayload
        }
        if isRSSURL(pageURL) {
            return parseRSS(html: html, pageURL: pageURL)
        }
        let items: [OnlineVideoItem]
        if isTagDirectory(pageURL, html: html) {
            items = parseTagDirectory(html: html)
        } else if isAuthorDirectory(pageURL, html: html) {
            items = parseAuthorDirectory(html: html)
        } else {
            items = parseVideoCards(html: html)
        }
        let (currentPage, totalPages) = pageNumbers(html: html, pageURL: pageURL)
        return OnlineVideoListPage(
            items: items,
            currentPage: currentPage,
            totalPages: totalPages,
            nextPageURL: nextPageURL(html: html, pageURL: pageURL)
        )
    }

    nonisolated static func parseVideoCards(html: String) -> [OnlineVideoItem] {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        var items: [OnlineVideoItem] = []
        var seen = Set<String>()
        for match in cardRegex.matches(in: html, range: fullRange) {
            guard match.numberOfRanges > 1,
                  let innerRange = Range(match.range(at: 1), in: html) else { continue }
            let inner = String(html[innerRange])
            guard let item = makeVideoItem(from: inner),
                  seen.insert(item.id).inserted else { continue }
            items.append(item)
        }
        return items
    }

    private nonisolated static func makeVideoItem(from html: String) -> OnlineVideoItem? {
        guard let path = firstMatch(coverLinkRegex, group: 1, in: html),
              let id = firstMatch(coverLinkRegex, group: 2, in: html),
              !path.lowercased().contains("/zh-tw/"),
              let detailURL = OnlineSourcePolicy.resolvedURL(
                  path,
                  relativeTo: URL(string: TangxinRequestFactory.htmlOrigin)!,
                  source: .tangxin,
                  resource: .html
              )
        else {
            return nil
        }
        let coverURL = firstMatch(coverImageRegex, in: html).flatMap {
            OnlineSourcePolicy.resolvedURL(
                decodeHTML($0),
                relativeTo: detailURL,
                source: .tangxin,
                resource: .media
            )
        }
        let title = (firstMatch(ariaLabelRegex, in: html) ?? firstMatch(headingRegex, in: html))
            .map { decodeHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? id
        let duration = firstMatch(durationRegex, in: html)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let authorPath = firstMatch(authorLinkRegex, group: 1, in: html)
        let authorEncoded = firstMatch(authorLinkRegex, group: 2, in: html)
        let authorFromLabel = firstMatch(authorNameRegex, in: html)
            .map { decodeHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let authorFromPath = authorEncoded.map {
            decodeHTML($0.removingPercentEncoding ?? $0)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let authorName = [authorFromLabel, authorFromPath]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let authorFilter: String? = {
            guard let name = authorFromPath, !name.isEmpty,
                  authorPath?.lowercased().contains("/zh-tw/") != true else { return nil }
            return "author:\(name)"
        }()
        return OnlineVideoItem(
            id: id,
            title: title.isEmpty ? id : title,
            subtitle: authorName ?? "糖心Vlog",
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 16.0 / 9.0,
            durationText: duration,
            authorName: authorName,
            authorFilter: authorFilter,
            tagFilters: parseTagFilters(in: html)
        )
    }

    private nonisolated static func parseTagDirectory(html: String) -> [OnlineVideoItem] {
        parseDirectory(
            html: html,
            regex: tagEntryRegex,
            filterPrefix: "tag:"
        )
    }

    private nonisolated static func parseAuthorDirectory(html: String) -> [OnlineVideoItem] {
        parseDirectory(
            html: html,
            regex: authorEntryRegex,
            filterPrefix: "author:"
        )
    }

    private nonisolated static func directoryCountSubtitle(_ count: String) -> String {
        guard !count.isEmpty else { return "" }
        if Int(count) != nil { return "\(count) 部" }
        return count
    }

    private nonisolated static func parseDirectory(
        html: String,
        regex: NSRegularExpression,
        filterPrefix: String
    ) -> [OnlineVideoItem] {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        var items: [OnlineVideoItem] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: fullRange) {
            guard match.numberOfRanges > 4,
                  let pathRange = Range(match.range(at: 1), in: html),
                  let slugRange = Range(match.range(at: 2), in: html),
                  let nameRange = Range(match.range(at: 3), in: html),
                  let countRange = Range(match.range(at: 4), in: html)
            else { continue }
            let path = String(html[pathRange])
            if path.lowercased().contains("/zh-tw/") { continue }
            let encoded = String(html[slugRange])
            let decoded = (encoded.removingPercentEncoding ?? encoded)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decoded.isEmpty,
                  let detailURL = OnlineSourcePolicy.resolvedURL(
                      path,
                      relativeTo: URL(string: TangxinRequestFactory.htmlOrigin)!,
                      source: .tangxin,
                      resource: .html
                  )
            else { continue }
            let name = decodeHTML(String(html[nameRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            let count = decodeHTML(String(html[countRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            let filter = "\(filterPrefix)\(decoded)"
            guard seen.insert(filter).inserted else { continue }
            items.append(
                OnlineVideoItem(
                    id: filter,
                    title: name.isEmpty ? decoded : name,
                    subtitle: directoryCountSubtitle(count),
                    detailURL: detailURL,
                    coverURL: nil,
                    coverAspectRatio: 16.0 / 9.0,
                    durationText: "",
                    opensFilter: filter
                )
            )
        }
        return items
    }

    private nonisolated static func parseRSS(html: String, pageURL: URL) -> OnlineVideoListPage {
        let query = searchQuery(from: pageURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        var items: [OnlineVideoItem] = []
        var seen = Set<String>()
        for match in rssItemRegex.matches(in: html, range: fullRange) {
            guard items.count < searchResultLimit,
                  match.numberOfRanges > 1,
                  let innerRange = Range(match.range(at: 1), in: html)
            else {
                if items.count >= searchResultLimit { break }
                continue
            }
            let inner = String(html[innerRange])
            guard let item = makeRSSItem(from: inner, query: query),
                  seen.insert(item.id).inserted else { continue }
            items.append(item)
        }
        return OnlineVideoListPage(
            items: items,
            currentPage: 1,
            totalPages: 1,
            nextPageURL: nil
        )
    }

    private nonisolated static func makeRSSItem(from html: String, query: String) -> OnlineVideoItem? {
        guard !query.isEmpty,
              let link = firstMatch(rssLinkRegex, in: html)
              .map({ decodeHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) }),
              let detailURL = URL(string: link),
              OnlineSourcePolicy.allows(detailURL, source: .tangxin, resource: .html),
              let id = TangxinFavoritesBridge.videoID(from: detailURL)
        else {
            return nil
        }
        let title = firstMatch(rssTitleRegex, in: html)
            .map { decodeHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? id
        let description = firstMatch(rssDescriptionRegex, in: html)
            .map { decodeHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let haystack = "\(title)\n\(description)"
        guard haystack.localizedCaseInsensitiveContains(query) else { return nil }
        let coverURL = OnlineSourcePolicy.resolvedURL(
            "https://t.5gcdn.xyz/videos/\(id)/cover.jpg",
            relativeTo: detailURL,
            source: .tangxin,
            resource: .media
        )
        return OnlineVideoItem(
            id: id,
            title: title.isEmpty ? id : title,
            subtitle: description.isEmpty ? "糖心Vlog" : description,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 16.0 / 9.0,
            durationText: ""
        )
    }

    private nonisolated static func nextPageURL(html: String, pageURL: URL) -> URL? {
        let href = firstMatch(relNextRegex, in: html)
            ?? firstMatch(relNextAltRegex, in: html)
            ?? firstMatch(pagerNextRegex, in: html)
        guard let href else { return nil }
        return OnlineSourcePolicy.resolvedURL(
            decodeHTML(href),
            relativeTo: pageURL,
            source: .tangxin,
            resource: .html
        )
    }

    private nonisolated static func pageNumbers(html: String, pageURL: URL) -> (Int, Int) {
        if let current = firstMatch(pagerStatusRegex, group: 1, in: html).flatMap(Int.init),
           let total = firstMatch(pagerStatusRegex, group: 2, in: html).flatMap(Int.init)
        {
            return (max(current, 1), max(total, current))
        }
        let last = pageURL.path.split(separator: "/", omittingEmptySubsequences: true).last
            .map(String.init)
        let current = Int(last ?? "") ?? 1
        return (max(current, 1), 0)
    }

    private nonisolated static func parseTagFilters(in html: String) -> [OnlineVideoTagLink] {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        var links: [OnlineVideoTagLink] = []
        var seen = Set<String>()
        for match in tagLinkRegex.matches(in: html, range: fullRange) {
            guard match.numberOfRanges > 3,
                  let pathRange = Range(match.range(at: 1), in: html),
                  let slugRange = Range(match.range(at: 2), in: html),
                  let titleRange = Range(match.range(at: 3), in: html)
            else { continue }
            if String(html[pathRange]).lowercased().contains("/zh-tw/") { continue }
            let slug = decodeHTML(String(html[slugRange]).removingPercentEncoding ?? String(html[slugRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty else { continue }
            let filter = "tag:\(slug)"
            guard seen.insert(filter).inserted else { continue }
            let title = decodeHTML(String(html[titleRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            links.append(OnlineVideoTagLink(title: title.isEmpty ? slug : title, filter: filter))
        }
        return links
    }

    private nonisolated static func isRSSURL(_ url: URL) -> Bool {
        url.path == "/rss.xml" || url.path.hasSuffix("/rss.xml")
    }

    private nonisolated static func isTagDirectory(_ url: URL, html: String) -> Bool {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count <= 1 && parts.first.map(String.init) == "tag" && html.contains("tag-cloud")
    }

    private nonisolated static func isAuthorDirectory(_ url: URL, html: String) -> Bool {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count <= 1 && parts.first.map(String.init) == "a" && html.contains("artist-cloud")
    }

    private nonisolated static func fetchURL(from url: URL) -> URL {
        guard isRSSURL(url) else { return url }
        return URL(string: "https://tangxinvlog.app/rss.xml") ?? url
    }

    private nonisolated static func searchQuery(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "q" })?
            .value
    }

    private nonisolated static func firstMatch(
        _ regex: NSRegularExpression,
        group: Int = 1,
        in text: String
    ) -> String? {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: range),
              result.numberOfRanges > group,
              let matchRange = Range(result.range(at: group), in: text)
        else {
            return nil
        }
        return String(text[matchRange])
    }

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid Tangxin list regex: \(pattern)")
        }
    }

    private nonisolated static func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
