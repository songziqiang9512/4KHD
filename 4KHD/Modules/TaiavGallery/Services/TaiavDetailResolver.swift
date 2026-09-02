import Foundation

nonisolated enum TaiavDetailResolverError: LocalizedError, Equatable {
    case invalidMovie
    case invalidPayload
    case missingPlaylist

    var errorDescription: String? {
        switch self {
        case .invalidMovie: "TaiAV 影片地址无效"
        case .invalidPayload: "TaiAV 播放地址无法解析"
        case .missingPlaylist: "当前页面没有可播放地址"
        }
    }
}

enum TaiavDetailResolver {
    private nonisolated struct GetMoviePayload: Decodable {
        let m3u8: String?
    }

    static func resolve(pageURL: URL) async throws -> OnlineVideoResolvedDetail {
        try OnlineSourcePolicy.validate(pageURL, source: .taiav, resource: .html)
        guard let movieID = TaiavFavoritesBridge.movieID(from: pageURL) else {
            throw TaiavDetailResolverError.invalidMovie
        }
        let request = try TaiavRequestFactory.makeGetMovieRequest(movieID: movieID, pageURL: pageURL)
        let (data, _) = try await TaiavHTTPClient.apiData(for: request)
        return try await parseConcurrently(data: data, movieID: movieID)
    }

    @concurrent
    private nonisolated static func parseConcurrently(
        data: Data,
        movieID: String
    ) async throws -> OnlineVideoResolvedDetail {
        try Task.checkCancellation()
        let detail = try parse(data: data, movieID: movieID)
        try Task.checkCancellation()
        return detail
    }

    nonisolated static func parse(data: Data, movieID: String) throws -> OnlineVideoResolvedDetail {
        guard let videoURL = try playlistURL(from: data, movieID: movieID) else {
            throw TaiavDetailResolverError.missingPlaylist
        }
        return OnlineVideoResolvedDetail(videoURL: videoURL, coverURL: nil)
    }

    nonisolated static func playlistURL(from data: Data, movieID: String) throws -> URL? {
        guard TaiavFavoritesBridge.isMovieID(movieID) else {
            throw TaiavDetailResolverError.invalidMovie
        }
        let payload: GetMoviePayload
        do {
            payload = try JSONDecoder().decode(GetMoviePayload.self, from: data)
        } catch {
            throw TaiavDetailResolverError.invalidPayload
        }
        guard let raw = payload.m3u8?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let decoded = httpsMediaValue(raw)
        guard let mediaOrigin = URL(string: TaiavRequestFactory.mediaOrigin),
              let videoURL = OnlineSourcePolicy.resolvedURL(
                  decoded,
                  relativeTo: mediaOrigin,
                  source: .taiav,
                  resource: .media
              ),
              videoURL.pathExtension.lowercased() == "m3u8",
              videoURL.path.lowercased().contains(movieID.lowercased())
        else {
            return nil
        }
        return videoURL
    }

    private nonisolated static func httpsMediaValue(_ raw: String) -> String {
        let decoded = raw.replacingOccurrences(of: "&amp;", with: "&")
        if decoded.lowercased().hasPrefix("http://") {
            return "https://" + decoded.dropFirst(7)
        }
        return decoded
    }
}
