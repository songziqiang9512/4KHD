import Foundation

nonisolated enum PornyListResolverError: LocalizedError, Equatable {
    case invalidURL
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidURL: "91PORNY 分页地址无效"
        case .invalidPayload: "91PORNY 列表数据无法解析"
        }
    }
}

enum PornyListResolver {
    private nonisolated static let cardRegex = regex(#"<div class="video-elem">([\s\S]*?)</div>\s*</div>"#)
    private nonisolated static let viewRegex = regex(#"href="(?:https://91porny\.com)?(/video/view(?:hd)?/([A-Za-z0-9]+))""#)
    private nonisolated static let coverRegex = regex(#"background-image:\s*url\('([^']+)'\)"#)
    private nonisolated static let durationRegex = regex(#"<small class="layer">([^<]*)</small>"#)
    private nonisolated static let titleRegex = regex(#"class="title[^"]*"[^>]*>([^<]+)"#)
    private nonisolated static let nextPageRegex = regex(#"href="([^"]+)"[^>]*>&raquo;"#)
    private nonisolated static let numberedPageRegex = regex(#"/video/category/[^/"']+/([0-9]+)"#)
    private nonisolated static let searchNumberedRegex = regex(#"/search/([0-9]+)"#)
    private nonisolated static let activePageRegex = regex(#"page-item active[\s\S]{0,80}>([0-9]+)<"#)

    static func resolve(url: URL) async throws -> OnlineVideoListPage {
        let request = try PornyRequestFactory.makeHTMLRequest(url: url)
        let (data, _) = try await PornyHTTPClient.data(for: request)
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
            throw PornyListResolverError.invalidPayload
        }
        let items = parseItems(html: html)
        let currentPage = currentPageNumber(html: html, pageURL: pageURL)
        let numberedPages = matches(numberedPageRegex, in: html).compactMap(Int.init)
            + matches(searchNumberedRegex, in: html).compactMap(Int.init)
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
        for match in cardRegex.matches(in: html, range: fullRange) {
            guard match.numberOfRanges > 1,
                  let innerRange = Range(match.range(at: 1), in: html) else { continue }
            let inner = String(html[innerRange])
            guard let item = makeItem(from: inner),
                  seen.insert(item.id).inserted else { continue }
            items.append(item)
        }
        return items
    }

    private nonisolated static func makeItem(from html: String) -> OnlineVideoItem? {
        guard let path = firstMatch(viewRegex, group: 1, in: html),
              let id = firstMatch(viewRegex, group: 2, in: html),
              let detailURL = OnlineSourcePolicy.resolvedURL(
                  path,
                  relativeTo: URL(string: PornyRequestFactory.htmlOrigin)!,
                  source: .porny,
                  resource: .html
              )
        else {
            return nil
        }
        let coverURL = firstMatch(coverRegex, in: html).flatMap {
            OnlineSourcePolicy.resolvedURL(
                decodeHTML($0),
                relativeTo: detailURL,
                source: .porny,
                resource: .media
            )
        }
        let title = firstMatch(titleRegex, in: html)
            .map { decodeHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? id
        let duration = firstMatch(durationRegex, in: html)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return OnlineVideoItem(
            id: id,
            title: title.isEmpty ? id : title,
            subtitle: "91PORNY",
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 16.0 / 9.0,
            durationText: duration
        )
    }

    private nonisolated static func nextPageURL(html: String, pageURL: URL) -> URL? {
        guard let href = firstMatch(nextPageRegex, in: html) else { return nil }
        return OnlineSourcePolicy.resolvedURL(
            decodeHTML(href),
            relativeTo: pageURL,
            source: .porny,
            resource: .html
        )
    }

    private nonisolated static func currentPageNumber(html: String, pageURL: URL) -> Int {
        if let active = firstMatch(activePageRegex, in: html).flatMap(Int.init) {
            return max(active, 1)
        }
        let last = pageURL.path.split(separator: "/", omittingEmptySubsequences: true).last
            .map(String.init)
        return Int(last ?? "") ?? 1
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
            preconditionFailure("Invalid Porny list regex: \(pattern)")
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
