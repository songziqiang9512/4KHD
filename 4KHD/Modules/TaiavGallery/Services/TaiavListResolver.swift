import Foundation

nonisolated enum TaiavListResolverError: LocalizedError, Equatable {
    case invalidURL
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidURL: "TaiAV 分页地址无效"
        case .invalidPayload: "TaiAV 列表数据无法解析"
        }
    }
}

enum TaiavListResolver {
    private nonisolated static let cardRegex = regex(#"class="[^"]*\bmovie-card\b[^"]*""#)
    private nonisolated static let firstHrefRegex = regex(#"href="([^"]+)""#)
    private nonisolated static let moviePathRegex = regex(#"^(?:https://taiav\.com)?(/cn/movie/([0-9a-fA-F]{24}))$"#)
    private nonisolated static let coverRegex = regex(#"src="(https://img\.storyofthepast\.xyz/videos/[^"]+)""#)
    private nonisolated static let titleRegex = regex(#"data-full-title="([^"]+)""#)
    private nonisolated static let altRegex = regex(#"alt="([^"]*)""#)
    private nonisolated static let nextPageRegex = regex(#"href="([^"]+)"[^>]*>&raquo;"#)
    private nonisolated static let lastPageRegex = regex(#"href="([^"]+)"[^>]*>尾页"#)
    private nonisolated static let pageQueryRegex = regex(#"[?&]page=([0-9]+)"#)
    private nonisolated static let activePageRegex = regex(#"page-item active[\s\S]{0,160}?[?&]page=([0-9]+)"#)

    static func resolve(url: URL) async throws -> OnlineVideoListPage {
        let request = try TaiavRequestFactory.makeHTMLRequest(url: url)
        let (data, _) = try await TaiavHTTPClient.data(for: request)
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
            throw TaiavListResolverError.invalidPayload
        }
        let items = parseItems(html: html)
        let currentPage = currentPageNumber(html: html, pageURL: pageURL)
        let numberedPages = numberedPageValues(in: html)
        let totalPages = max(numberedPages.max() ?? currentPage, currentPage)
        return OnlineVideoListPage(
            items: items,
            currentPage: currentPage,
            totalPages: totalPages,
            nextPageURL: nextPageURL(html: html, pageURL: pageURL)
        )
    }

    nonisolated static func parseItems(html: String) -> [OnlineVideoItem] {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        var items: [OnlineVideoItem] = []
        var seen = Set<String>()
        let matches = cardRegex.matches(in: html, range: fullRange)
        for (index, match) in matches.enumerated() {
            let location = match.range.location
            guard location != NSNotFound else { continue }
            let nextLocation = index + 1 < matches.count ? matches[index + 1].range.location : nsHTML.length
            let windowLength = max(0, nextLocation - location)
            guard windowLength > 0 else { continue }
            let inner = nsHTML.substring(with: NSRange(location: location, length: windowLength))
            guard let item = makeItem(from: inner),
                  seen.insert(item.id).inserted else { continue }
            items.append(item)
        }
        return items
    }

    private nonisolated static func makeItem(from html: String) -> OnlineVideoItem? {
        guard let href = firstMatch(firstHrefRegex, in: html),
              let path = firstMatch(moviePathRegex, group: 1, in: href),
              let id = firstMatch(moviePathRegex, group: 2, in: href)?.lowercased(),
              let detailURL = OnlineSourcePolicy.resolvedURL(
                  path,
                  relativeTo: URL(string: "https://taiav.com")!,
                  source: .taiav,
                  resource: .html
              )
        else {
            return nil
        }
        let coverURL = firstMatch(coverRegex, in: html).flatMap {
            OnlineSourcePolicy.resolvedURL(
                decodeHTML($0),
                relativeTo: detailURL,
                source: .taiav,
                resource: .media
            )
        }
        let title = (firstMatch(titleRegex, in: html) ?? firstMatch(altRegex, in: html))
            .map { decodeHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? id
        return OnlineVideoItem(
            id: id,
            title: title.isEmpty ? id : title,
            subtitle: "TaiAV",
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 16.0 / 9.0,
            durationText: ""
        )
    }

    private nonisolated static func nextPageURL(html: String, pageURL: URL) -> URL? {
        guard let href = firstMatch(nextPageRegex, in: html) else { return nil }
        return OnlineSourcePolicy.resolvedURL(
            decodeHTML(href),
            relativeTo: pageURL,
            source: .taiav,
            resource: .html
        )
    }

    private nonisolated static func currentPageNumber(html: String, pageURL: URL) -> Int {
        if let active = firstMatch(activePageRegex, in: html).flatMap(Int.init) {
            return max(active, 1)
        }
        if let queryPage = pageQueryValue(in: pageURL.absoluteString) {
            return max(queryPage, 1)
        }
        return 1
    }

    private nonisolated static func numberedPageValues(in html: String) -> [Int] {
        var values = matches(pageQueryRegex, in: html).compactMap(Int.init)
        if let lastHref = firstMatch(lastPageRegex, in: html),
           let lastPage = pageQueryValue(in: decodeHTML(lastHref))
        {
            values.append(lastPage)
        }
        return values
    }

    private nonisolated static func pageQueryValue(in text: String) -> Int? {
        firstMatch(pageQueryRegex, in: text).flatMap(Int.init)
    }

    private nonisolated static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[matchRange])
        }
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
            preconditionFailure("Invalid Taiav list regex: \(pattern)")
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
