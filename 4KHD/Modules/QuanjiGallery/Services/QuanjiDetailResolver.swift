import Foundation

nonisolated enum QuanjiDetailResolverError: LocalizedError, Equatable {
    case invalidPayload
    case missingPlaylist

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "木瓜视频详情无法解析"
        case .missingPlaylist: "木瓜视频未提供可播放地址"
        }
    }
}

enum QuanjiDetailResolver {
    private nonisolated static let evalRegex = regex(#"eval\(I\("([^"]+)"\)\)"#)
    private nonisolated static let coverRegex = regex(
        #"https://pics\.mugua01\.cfd/[^"'<\s]+\.(?:jpg|jpeg|png|webp)"#
    )

    static func resolve(pageURL: URL) async throws -> OnlineVideoResolvedDetail {
        try OnlineSourcePolicy.validate(pageURL, source: .quanji, resource: .html)
        let request = try QuanjiRequestFactory.makeHTMLRequest(url: pageURL)
        let (data, _) = try await QuanjiHTTPClient.data(for: request)
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
            throw QuanjiDetailResolverError.invalidPayload
        }
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        guard let match = evalRegex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let encodedRange = Range(match.range(at: 1), in: html)
        else {
            throw QuanjiDetailResolverError.missingPlaylist
        }
        let decoded = decodeXOR80(String(html[encodedRange]))
        guard let playlist = playlistURL(in: decoded),
              let videoURL = OnlineSourcePolicy.resolvedURL(
                  decodeHTML(playlist),
                  relativeTo: pageURL,
                  source: .quanji,
                  resource: .media
              ),
              videoURL.pathExtension.lowercased() == "m3u8"
        else {
            throw QuanjiDetailResolverError.missingPlaylist
        }
        return OnlineVideoResolvedDetail(
            videoURL: videoURL,
            coverURL: coverURL(in: html, pageURL: pageURL)
        )
    }

    private nonisolated static func playlistURL(in decoded: String) -> String? {
        if let range = decoded.range(of: #"url:\s*'([^']+)'"#, options: .regularExpression) {
            return quotedValue(in: String(decoded[range]), delimiter: "'")
        }
        if let range = decoded.range(of: #"url:\s*"([^"]+)""#, options: .regularExpression) {
            return quotedValue(in: String(decoded[range]), delimiter: "\"")
        }
        return nil
    }

    private nonisolated static func quotedValue(in text: String, delimiter: Character) -> String? {
        guard let start = text.firstIndex(of: delimiter) else { return nil }
        let after = text.index(after: start)
        guard let end = text[after...].firstIndex(of: delimiter) else { return nil }
        return String(text[after ..< end])
    }

    private nonisolated static func coverURL(in html: String, pageURL: URL) -> URL? {
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        guard let match = coverRegex.firstMatch(in: html, range: range),
              let matchRange = Range(match.range, in: html)
        else {
            return nil
        }
        return OnlineSourcePolicy.resolvedURL(
            String(html[matchRange]),
            relativeTo: pageURL,
            source: .quanji,
            resource: .media
        )
    }

    private nonisolated static func decodeXOR80(_ encoded: String) -> String {
        var decoded = ""
        decoded.reserveCapacity(encoded.utf16.count)
        for unit in encoded.utf16 {
            let value = unit ^ 128
            if let scalar = UnicodeScalar(value) {
                decoded.append(Character(scalar))
            }
        }
        return decoded
    }

    private nonisolated static func decodeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
    }

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid Quanji detail regex: \(pattern)")
        }
    }
}
