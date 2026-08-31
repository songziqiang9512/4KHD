import Foundation

nonisolated enum PornyDetailResolverError: LocalizedError, Equatable {
    case invalidPayload
    case missingPlaylist

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "91PORNY 详情无法解析"
        case .missingPlaylist: "当前页面没有可播放地址"
        }
    }
}

enum PornyDetailResolver {
    private nonisolated static let dataSrcRegex = regex(
        #"<video[^>]*id="video-play"[^>]*data-src="([^"]+)""#
    )
    private nonisolated static let dataSrcAltRegex = regex(
        #"data-src="([^"]+)"[^>]*id="video-play""#
    )
    private nonisolated static let dataSrcFallbackRegex = regex(
        #"id="video-play"[^>]*data-src="([^"]+)""#
    )
    private nonisolated static let ogImageRegex = regex(
        #"<meta[^>]+property="og:image"[^>]+content="([^"]+)""#
    )

    static func resolve(pageURL: URL) async throws -> OnlineVideoResolvedDetail {
        try OnlineSourcePolicy.validate(pageURL, source: .porny, resource: .html)
        let requestURL = publicPlaybackURL(from: pageURL) ?? pageURL
        if requestURL != pageURL {
            try OnlineSourcePolicy.validate(requestURL, source: .porny, resource: .html)
        }
        let request = try PornyRequestFactory.makeHTMLRequest(url: requestURL)
        let (data, _) = try await PornyHTTPClient.data(for: request)
        return try await parseConcurrently(data: data, pageURL: requestURL)
    }

    /// 高清观看页公开 HTML 只有共享 `/hlsd/` 预告。同一 id 的普通观看页才有可播清单。
    nonisolated static func publicPlaybackURL(from pageURL: URL) -> URL? {
        let parts = pageURL.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3, parts[0] == "video", parts[1] == "viewhd" else { return nil }
        let id = parts[2]
        guard !id.isEmpty else { return nil }
        return OnlineSourcePolicy.resolvedURL(
            "/video/view/\(id)",
            relativeTo: pageURL,
            source: .porny,
            resource: .html
        )
    }

    @concurrent
    private nonisolated static func parseConcurrently(
        data: Data,
        pageURL: URL
    ) async throws -> OnlineVideoResolvedDetail {
        try Task.checkCancellation()
        let detail = try parse(data: data, pageURL: pageURL)
        try Task.checkCancellation()
        return detail
    }

    nonisolated static func parse(data: Data, pageURL: URL) throws -> OnlineVideoResolvedDetail {
        guard let html = String(data: data, encoding: .utf8) else {
            throw PornyDetailResolverError.invalidPayload
        }
        let raw = firstMatch(dataSrcRegex, in: html)
            ?? firstMatch(dataSrcAltRegex, in: html)
            ?? firstMatch(dataSrcFallbackRegex, in: html)
        guard let raw, !isUnplayablePublicTeaser(raw) else {
            throw PornyDetailResolverError.missingPlaylist
        }
        let decoded = httpsMediaValue(raw)
        guard let videoURL = OnlineSourcePolicy.resolvedURL(
            decoded,
            relativeTo: pageURL,
            source: .porny,
            resource: .media
        ),
            videoURL.pathExtension.lowercased() == "m3u8"
        else {
            throw PornyDetailResolverError.missingPlaylist
        }
        return OnlineVideoResolvedDetail(
            videoURL: videoURL,
            coverURL: coverURL(in: html, pageURL: pageURL)
        )
    }

    private nonisolated static func coverURL(in html: String, pageURL: URL) -> URL? {
        guard let raw = firstMatch(ogImageRegex, in: html) else { return nil }
        return OnlineSourcePolicy.resolvedURL(
            httpsMediaValue(raw),
            relativeTo: pageURL,
            source: .porny,
            resource: .media
        )
    }

    /// 高清分类公开页常见的会员预告清单，不是该条目自己的可播放地址。
    private nonisolated static func isUnplayablePublicTeaser(_ raw: String) -> Bool {
        decodeHTML(raw).lowercased().contains("/hlsd/")
    }

    private nonisolated static func httpsMediaValue(_ raw: String) -> String {
        let decoded = decodeHTML(raw)
        if decoded.lowercased().hasPrefix("http://") {
            return "https://" + decoded.dropFirst(7)
        }
        return decoded
    }

    private nonisolated static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: range),
              result.numberOfRanges > 1,
              let matchRange = Range(result.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[matchRange])
    }

    private nonisolated static func decodeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
    }

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid Porny detail regex: \(pattern)")
        }
    }
}
