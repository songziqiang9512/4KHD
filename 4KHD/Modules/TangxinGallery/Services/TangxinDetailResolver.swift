import Foundation

nonisolated enum TangxinDetailResolverError: LocalizedError, Equatable {
    case invalidPayload
    case missingPlaylist

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "糖心Vlog 详情无法解析"
        case .missingPlaylist: "当前页面没有可播放地址"
        }
    }
}

enum TangxinDetailResolver {
    private nonisolated static let constM3U8Regex = regex(#"const\s+m3u8\s*=\s*"([^"]+)""#)
    private nonisolated static let contentURLRegex = regex(#""contentUrl"\s*:\s*"([^"]+)""#)

    static func resolve(pageURL: URL) async throws -> OnlineVideoResolvedDetail {
        try OnlineSourcePolicy.validate(pageURL, source: .tangxin, resource: .html)
        let request = try TangxinRequestFactory.makeHTMLRequest(url: pageURL)
        let (data, _) = try await TangxinHTTPClient.data(for: request)
        return try await parseConcurrently(data: data, pageURL: pageURL)
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
            throw TangxinDetailResolverError.invalidPayload
        }
        guard let videoID = TangxinFavoritesBridge.videoID(from: pageURL) else {
            throw TangxinDetailResolverError.missingPlaylist
        }
        let candidates = [firstMatch(constM3U8Regex, in: html), firstMatch(contentURLRegex, in: html)]
            .compactMap { $0 }
        let matching = candidates.compactMap { raw in
            playlistURL(from: raw, pageURL: pageURL, videoID: videoID)
        }
        guard let videoURL = matching.first else {
            throw TangxinDetailResolverError.missingPlaylist
        }
        return OnlineVideoResolvedDetail(
            videoURL: videoURL,
            coverURL: coverURL(videoID: videoID)
        )
    }

    private nonisolated static func playlistURL(from raw: String, pageURL: URL, videoID: String) -> URL? {
        let decoded = decodeHTML(raw)
        guard let url = OnlineSourcePolicy.resolvedURL(
            decoded,
            relativeTo: pageURL,
            source: .tangxin,
            resource: .media
        ),
            url.pathExtension.lowercased() == "m3u8",
            url.path.lowercased().contains("/videos/\(videoID)/")
        else {
            return nil
        }
        return url
    }

    private nonisolated static func coverURL(videoID: String) -> URL? {
        OnlineSourcePolicy.resolvedURL(
            "https://t.5gcdn.xyz/videos/\(videoID)/cover.jpg",
            relativeTo: URL(string: TangxinRequestFactory.htmlOrigin)!,
            source: .tangxin,
            resource: .media
        )
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
            preconditionFailure("Invalid Tangxin detail regex: \(pattern)")
        }
    }
}
