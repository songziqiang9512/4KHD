import Foundation

nonisolated enum MrdsListResolverError: LocalizedError, Equatable {
    case invalidURL
    case invalidPayload
    case unrecognizedMarkup

    var errorDescription: String? {
        switch self {
        case .invalidURL: "每日大赛分页地址无效"
        case .invalidPayload: "每日大赛列表数据无法解析"
        case .unrecognizedMarkup: "每日大赛列表页面结构已变化"
        }
    }
}

enum MrdsListResolver {
    private nonisolated static let cardIDRegex = regex(#"id=["']post-card-([0-9]+)["']"#)
    private nonisolated static let archiveHrefRegex = regex(#"href=["']((?:https://www\.mrds66\.com)?/archives/[0-9]+/)["']"#)
    private nonisolated static let coverRegex = regex(#"loadBannerDirect\(\s*['"]([^'"]+)['"]"#)
    private nonisolated static let picCoverRegex = regex(#"(https://pic\.sbhioa\.cn/+[^\s\"'<>\\]+)"#)
    private nonisolated static let titleRegex = regex(#"class=["'][^"']*post-card-title[^"']*["'][^>]*>\s*([\s\S]*?)\s*</h2>"#)
    private nonisolated static let dateRegex = regex(#"itemprop=["']datePublished["'][^>]*content=["']([^"']+)["']"#)
    private nonisolated static let dateTextRegex = regex(#"itemprop=["']datePublished["'][^>]*>\s*([^<]+)"#)
    private nonisolated static let categoryRegex = regex(#"<span>\s*([^<]{1,80})\s*</span>\s*</div>"#)
    private nonisolated static let nextPageRegex = regex(#"class=["']next["']\s*>\s*<a[^>]+href=["']([^"']+)["']"#)
    private nonisolated static let activePageRegex = regex(#"class=["']active["']\s*>\s*<a[^>]*>\s*([0-9]+)"#)
    private nonisolated static let numberedPageRegex = regex(#"<a[^>]+href=["'][^"']+["'][^>]*>\s*([0-9]+)\s*</a>"#)

    static func resolve(context: MrdsListContext, page: Int = 1) async throws -> MrdsListPage {
        guard let url = context.pageURL(page: page) else { throw MrdsListResolverError.invalidURL }
        let request = try MrdsRequestFactory.makeHTMLRequest(url: url)
        let (data, _) = try await MrdsHTTPClient.data(for: request)
        return try await parseConcurrently(data: data, context: context, requestedPage: page)
    }

    @concurrent
    private nonisolated static func parseConcurrently(
        data: Data,
        context: MrdsListContext,
        requestedPage: Int
    ) async throws -> MrdsListPage {
        try Task.checkCancellation()
        let page = try parse(data: data, context: context, requestedPage: requestedPage)
        try Task.checkCancellation()
        return page
    }

    nonisolated static func parse(
        data: Data,
        context: MrdsListContext,
        requestedPage: Int = 1
    ) throws -> MrdsListPage {
        guard let html = String(data: data, encoding: .utf8) else {
            throw MrdsListResolverError.invalidPayload
        }
        let items = parseItems(html: html)
        guard !items.isEmpty else {
            throw MrdsListResolverError.unrecognizedMarkup
        }
        let currentPage = firstMatch(activePageRegex, in: html).flatMap(Int.init) ?? requestedPage
        let numberedPages = matches(numberedPageRegex, in: html).compactMap(Int.init)
        let totalPages = max(numberedPages.max() ?? currentPage, currentPage)
        let nextPageURL: URL?
        if let href = firstMatch(nextPageRegex, in: html) {
            nextPageURL = OnlineSourcePolicy.resolvedURL(
                decodeHTML(href),
                relativeTo: URL(string: "https://www.mrds66.com/")!,
                source: .mrds,
                resource: .html
            ) ?? context.pageURL(page: currentPage + 1)
        } else if currentPage < totalPages {
            nextPageURL = context.pageURL(page: currentPage + 1)
        } else {
            nextPageURL = nil
        }
        return MrdsListPage(
            items: items,
            currentPage: currentPage,
            totalPages: totalPages,
            nextPageURL: nextPageURL
        )
    }

    nonisolated static func parseItems(html: String) -> [MrdsGalleryItem] {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        var items: [MrdsGalleryItem] = []
        var seen = Set<String>()
        for match in cardIDRegex.matches(in: html, range: fullRange) {
            guard match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: html),
                  let articleHTML = enclosingArticle(around: match.range, in: nsHTML),
                  !isAdvertisement(articleHTML) else { continue }
            let id = String(html[idRange])
            guard let item = makeItem(from: articleHTML, fallbackID: id),
                  seen.insert(item.id).inserted else { continue }
            items.append(item)
        }
        return items
    }

    private nonisolated static func coverURL(from html: String, relativeTo detailURL: URL) -> URL? {
        if let banner = firstMatch(coverRegex, in: html),
           let url = resolvedMediaURL(banner, relativeTo: detailURL)
        {
            return url
        }
        for candidate in matches(picCoverRegex, in: html) {
            if let url = resolvedMediaURL(candidate, relativeTo: detailURL) {
                return url
            }
        }
        return nil
    }

    private nonisolated static func resolvedMediaURL(_ value: String, relativeTo detailURL: URL) -> URL? {
        let cleaned = decodeHTML(value)
            .replacingOccurrences(of: "://pic.sbhioa.cn//", with: "://pic.sbhioa.cn/")
        return OnlineSourcePolicy.resolvedURL(
            cleaned,
            relativeTo: detailURL,
            source: .mrds,
            resource: .media
        )
    }

    private nonisolated static func enclosingArticle(around range: NSRange, in html: NSString) -> String? {
        let prefixRange = NSRange(location: 0, length: range.location)
        let open = html.range(of: "<article", options: [.backwards, .caseInsensitive], range: prefixRange)
        guard open.location != NSNotFound else { return nil }
        let closeSearch = NSRange(location: range.location, length: html.length - range.location)
        let close = html.range(of: "</article>", options: .caseInsensitive, range: closeSearch)
        guard close.location != NSNotFound else { return nil }
        return html.substring(with: NSRange(location: open.location, length: NSMaxRange(close) - open.location))
    }

    private nonisolated static func isAdvertisement(_ html: String) -> Bool {
        let nsHTML = html as NSString
        let tagEnd = nsHTML.range(of: ">")
        guard tagEnd.location != NSNotFound else { return false }
        let openTag = nsHTML.substring(to: tagEnd.location).lowercased()
        return openTag.contains("ad-item") || openTag.contains("ad-card")
    }

    private nonisolated static func makeItem(from html: String, fallbackID: String) -> MrdsGalleryItem? {
        guard let detailValue = firstMatch(archiveHrefRegex, in: html),
              let detailURL = OnlineSourcePolicy.resolvedURL(
                  decodeHTML(detailValue),
                  relativeTo: URL(string: "https://www.mrds66.com/")!,
                  source: .mrds,
                  resource: .html
              ),
              detailURL.path.range(of: #"^/archives/[0-9]+/?$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        let id = detailURL.pathComponents.filter { $0 != "/" }.last ?? fallbackID
        let coverURL = coverURL(from: html, relativeTo: detailURL)
        let parsedTitle = firstMatch(titleRegex, in: html)
            .map(stripTags)
            .map(decodeHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTitle = parsedTitle?.isEmpty == false ? parsedTitle! : id
        let category = firstMatch(categoryRegex, in: html)
            .map(decodeHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "•", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "每日大赛"
        let publishedDate = firstMatch(dateTextRegex, in: html)
            .map { $0.replacingOccurrences(of: "•", with: "") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? firstMatch(dateRegex, in: html)
            ?? ""
        return MrdsGalleryItem(
            id: id,
            title: rawTitle,
            rawTitle: rawTitle,
            category: category,
            publishedDate: publishedDate,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 1.6,
            hasVideo: false
        )
    }

    private nonisolated static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private nonisolated static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: range),
              result.numberOfRanges > 1,
              let matchRange = Range(result.range(at: 1), in: text) else { return nil }
        return String(text[matchRange])
    }

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid Mrds list regex: \(pattern)")
        }
    }

    private nonisolated static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private nonisolated static func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
