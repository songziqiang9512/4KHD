import Foundation

nonisolated enum QuanjiListResolverError: LocalizedError, Equatable {
    case invalidURL
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidURL: "木瓜视频分页地址无效"
        case .invalidPayload: "木瓜视频列表数据无法解析"
        }
    }
}

enum QuanjiListResolver {
    private nonisolated static let cardRegex = regex(
        #"href="(watch\.jsp\?v=([A-Za-z0-9]+))"[^>]*>[\s\S]*?<img src="([^"]+)"[\s\S]*?thumb-spot__title">([\s\S]*?)</h5>"#
    )
    private nonisolated static let nextPageRegex = regex(
        #"<a href="(\?t=[^"]+&p=[^"]+)"><i class="icon-chevron-right">"#
    )
    private nonisolated static let numberedPageRegex = regex(
        #"href="\?t=[^"]+&p=[^"]+">\s*([0-9]+)\s*<"#
    )
    private nonisolated static let activePageRegex = regex(
        #"<li class="active"><a>([0-9]+)</a>"#
    )
    private nonisolated static let searchNextRegex = regex(
        #"nextPage\s*=\s*([0-9]+)"#
    )

    static func resolve(url: URL) async throws -> OnlineVideoListPage {
        let request = try QuanjiRequestFactory.makeHTMLRequest(url: url)
        let (data, _) = try await QuanjiHTTPClient.data(for: request)
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
            throw QuanjiListResolverError.invalidPayload
        }
        let items = parseItems(html: html)
        let currentPage = currentPageNumber(html: html, pageURL: pageURL)
        let numberedPages = matches(numberedPageRegex, in: html).compactMap(Int.init)
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
            guard match.numberOfRanges > 4,
                  let idRange = Range(match.range(at: 2), in: html),
                  let coverRange = Range(match.range(at: 3), in: html),
                  let titleRange = Range(match.range(at: 4), in: html) else { continue }
            let id = String(html[idRange])
            guard seen.insert(id).inserted,
                  let detailURL = OnlineSourcePolicy.resolvedURL(
                      "watch.jsp?v=\(id)",
                      relativeTo: URL(string: QuanjiRequestFactory.htmlOrigin)!,
                      source: .quanji,
                      resource: .html
                  ) else { continue }
            let coverURL = OnlineSourcePolicy.resolvedURL(
                decodeHTML(String(html[coverRange])),
                relativeTo: detailURL,
                source: .quanji,
                resource: .media
            )
            let title = decodeHTML(stripTags(String(html[titleRange])))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(
                OnlineVideoItem(
                    id: id,
                    title: title.isEmpty ? id : title,
                    subtitle: "木瓜视频",
                    detailURL: detailURL,
                    coverURL: coverURL,
                    coverAspectRatio: 16.0 / 9.0,
                    durationText: ""
                )
            )
        }
        return items
    }

    private nonisolated static func nextPageURL(html: String, pageURL: URL) -> URL? {
        if let href = firstMatch(nextPageRegex, in: html) {
            return OnlineSourcePolicy.resolvedURL(
                decodeHTML(href),
                relativeTo: pageURL,
                source: .quanji,
                resource: .html
            )
        }
        if pageURL.path.contains("search.jsp"),
           let next = firstMatch(searchNextRegex, in: html).flatMap(Int.init)
        {
            var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
            var items = components?.queryItems ?? []
            items.removeAll { $0.name == "p" }
            items.append(URLQueryItem(name: "p", value: String(next)))
            components?.queryItems = items
            return components?.url.flatMap {
                OnlineSourcePolicy.allows($0, source: .quanji, resource: .html) ? $0 : nil
            }
        }
        return nil
    }

    private nonisolated static func currentPageNumber(html: String, pageURL: URL) -> Int {
        if let active = firstMatch(activePageRegex, in: html).flatMap(Int.init) {
            return max(active, 1)
        }
        let page = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "p" })?.value
        return Int(page ?? "") ?? 1
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
        matches(regex, in: text).first
    }

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid Quanji list regex: \(pattern)")
        }
    }

    private nonisolated static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
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
