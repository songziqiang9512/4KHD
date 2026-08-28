import AVFoundation
import Foundation

nonisolated struct KnitVideoDownloadProgress: Sendable, Equatable {
    enum Stage: Sendable, Equatable {
        case resolvingPlaylist
        case downloadingSegments
        case exportingMP4
        case installingFile
    }

    let stage: Stage
    let completedSegments: Int
    let totalSegments: Int
    let downloadedBytes: Int64
    let totalBytes: Int64?
    let bytesPerSecond: Double
    let averageBytesPerSecond: Double

    init(
        stage: Stage,
        completedSegments: Int,
        totalSegments: Int,
        downloadedBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        bytesPerSecond: Double = 0,
        averageBytesPerSecond: Double = 0
    ) {
        self.stage = stage
        self.completedSegments = max(completedSegments, 0)
        self.totalSegments = max(totalSegments, 0)
        let normalizedDownloadedBytes = max(downloadedBytes, 0)
        self.downloadedBytes = normalizedDownloadedBytes
        self.totalBytes = totalBytes.map { max($0, normalizedDownloadedBytes) }
        self.bytesPerSecond = max(bytesPerSecond, 0)
        self.averageBytesPerSecond = max(averageBytesPerSecond, 0)
    }

    var fractionCompleted: Double {
        switch stage {
        case .resolvingPlaylist:
            return 0
        case .downloadingSegments:
            guard totalSegments > 0 else { return 0 }
            return min(Double(completedSegments) / Double(totalSegments) * 0.9, 0.9)
        case .exportingMP4:
            return 0.95
        case .installingFile:
            return 1
        }
    }

    var statusText: String {
        switch stage {
        case .resolvingPlaylist:
            "正在读取视频清单…"
        case .downloadingSegments:
            "正在下载视频片段 \(completedSegments) / \(totalSegments)"
        case .exportingMP4:
            "正在封装 MP4…"
        case .installingFile:
            "正在保存文件…"
        }
    }
}

nonisolated struct KnitVideoTransferMetrics: Sendable, Equatable {
    let downloadedBytes: Int64
    let estimatedTotalBytes: Int64?
    let bytesPerSecond: Double
    let averageBytesPerSecond: Double
}

/// Tracks bytes at completed HLS segment boundaries. The recent speed is
/// exponentially smoothed so the task center does not jump between segments;
/// the average always spans the whole segment-download phase.
nonisolated struct KnitVideoTransferMeter: Sendable {
    private let startedAt: Date
    private var lastSampleAt: Date
    private(set) var downloadedBytes: Int64 = 0
    private(set) var bytesPerSecond: Double = 0
    private(set) var averageBytesPerSecond: Double = 0

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
        self.lastSampleAt = startedAt
    }

    mutating func record(
        segmentBytes: Int64,
        completedSegments: Int,
        totalSegments: Int,
        at recordedAt: Date = Date()
    ) -> KnitVideoTransferMetrics {
        let additionalBytes = max(segmentBytes, 0)
        downloadedBytes += additionalBytes

        let sampleDuration = max(recordedAt.timeIntervalSince(lastSampleAt), 0.05)
        let instantaneousSpeed = Double(additionalBytes) / sampleDuration
        bytesPerSecond = bytesPerSecond > 0
            ? bytesPerSecond * 0.75 + instantaneousSpeed * 0.25
            : instantaneousSpeed
        let totalDuration = max(recordedAt.timeIntervalSince(startedAt), 0.05)
        averageBytesPerSecond = Double(downloadedBytes) / totalDuration
        lastSampleAt = recordedAt

        let estimatedTotalBytes: Int64?
        if completedSegments > 0, totalSegments > 0 {
            let estimate = Double(downloadedBytes)
                / Double(completedSegments)
                * Double(totalSegments)
            estimatedTotalBytes = max(
                downloadedBytes,
                Int64(min(estimate.rounded(), Double(Int64.max)))
            )
        } else {
            estimatedTotalBytes = nil
        }
        return KnitVideoTransferMetrics(
            downloadedBytes: downloadedBytes,
            estimatedTotalBytes: estimatedTotalBytes,
            bytesPerSecond: bytesPerSecond,
            averageBytesPerSecond: averageBytesPerSecond
        )
    }
}

nonisolated enum KnitVideoDownloadError: LocalizedError, Equatable {
    case invalidPlaylistURL
    case badStatus(Int)
    case challengeNotResolved
    case invalidPlaylist
    case emptyPlaylist
    case livePlaylist
    case playlistTooLarge
    case tooManySegments
    case encryptedPlaylist
    case separateAudioTrack
    case byteRangePlaylist
    case fragmentedMP4Playlist
    case discontinuousPlaylist
    case unsupportedTransportStream
    case exportUnavailable
    case exportFailed(String)
    case invalidExportedFile

    var errorDescription: String? {
        switch self {
        case .invalidPlaylistURL:
            "影片源地址无效"
        case .badStatus(let status):
            "影片服务器返回状态码 \(status)"
        case .challengeNotResolved:
            "影片访问验证未通过"
        case .invalidPlaylist:
            "影片清单格式无法识别"
        case .emptyPlaylist:
            "影片清单中没有可下载的片段"
        case .livePlaylist:
            "暂不支持保存仍在更新的直播清单"
        case .playlistTooLarge:
            "影片清单异常过大，已停止下载"
        case .tooManySegments:
            "影片片段数量异常，已停止下载"
        case .encryptedPlaylist:
            "该影片使用了加密清单，暂时无法保存为 MP4"
        case .separateAudioTrack:
            "该影片使用了独立音轨，暂时无法完整保存为 MP4"
        case .byteRangePlaylist:
            "该影片使用了分段字节范围，暂时无法保存为 MP4"
        case .fragmentedMP4Playlist:
            "该影片不是站点当前使用的 MPEG-TS 格式，暂时无法保存"
        case .discontinuousPlaylist:
            "该影片包含不连续的媒体片段，暂时无法可靠保存为 MP4"
        case .unsupportedTransportStream:
            "下载到的影片片段无法封装为 MP4"
        case .exportUnavailable:
            "系统无法创建 MP4 导出任务"
        case .exportFailed(let message):
            "MP4 封装失败：\(message)"
        case .invalidExportedFile:
            "生成的 MP4 未通过系统播放校验"
        }
    }
}

nonisolated enum KnitHLSPlaylist: Equatable, Sendable {
    struct Variant: Equatable, Sendable {
        let url: URL
        let bandwidth: Int
    }

    case master([Variant])
    case media([URL])

    static func parse(_ text: String, baseURL: URL) throws -> KnitHLSPlaylist {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.first(where: { !$0.isEmpty })?.uppercased() == "#EXTM3U" else {
            throw KnitVideoDownloadError.invalidPlaylist
        }
        if lines.contains(where: { line in
            let upper = line.uppercased()
            return upper.hasPrefix("#EXT-X-KEY:") && !upper.contains("METHOD=NONE")
        }) {
            throw KnitVideoDownloadError.encryptedPlaylist
        }
        if lines.contains(where: { line in
            let upper = line.uppercased()
            return upper.hasPrefix("#EXT-X-MEDIA:")
                && upper.contains("TYPE=AUDIO")
                && upper.contains("URI=")
        }) {
            throw KnitVideoDownloadError.separateAudioTrack
        }
        if lines.contains(where: { $0.uppercased().hasPrefix("#EXT-X-BYTERANGE:") }) {
            throw KnitVideoDownloadError.byteRangePlaylist
        }
        if lines.contains(where: { $0.uppercased().hasPrefix("#EXT-X-MAP:") }) {
            throw KnitVideoDownloadError.fragmentedMP4Playlist
        }
        if lines.contains(where: { $0.uppercased() == "#EXT-X-DISCONTINUITY" }) {
            throw KnitVideoDownloadError.discontinuousPlaylist
        }

        var variants: [Variant] = []
        for index in lines.indices {
            let line = lines[index]
            guard line.uppercased().hasPrefix("#EXT-X-STREAM-INF:") else { continue }
            guard let rawURL = nextResourceLine(after: index, in: lines),
                  let url = validatedMediaURL(rawURL, relativeTo: baseURL),
                  url.pathExtension.lowercased() == "m3u8" else {
                throw KnitVideoDownloadError.invalidPlaylist
            }
            variants.append(Variant(url: url, bandwidth: bandwidth(in: line)))
        }
        if !variants.isEmpty {
            return .master(variants.sorted { lhs, rhs in
                if lhs.bandwidth == rhs.bandwidth {
                    return lhs.url.absoluteString < rhs.url.absoluteString
                }
                return lhs.bandwidth > rhs.bandwidth
            })
        }

        guard lines.contains(where: { $0.uppercased().hasPrefix("#EXTINF:") }) else {
            throw KnitVideoDownloadError.invalidPlaylist
        }
        guard lines.contains(where: { $0.uppercased() == "#EXT-X-ENDLIST" }) else {
            throw KnitVideoDownloadError.livePlaylist
        }
        let segmentURLs = try lines.compactMap { line -> URL? in
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            guard let url = validatedMediaURL(line, relativeTo: baseURL) else {
                throw OnlineSourcePolicy.PolicyError.rejectedURL
            }
            return url
        }
        guard !segmentURLs.isEmpty else { throw KnitVideoDownloadError.emptyPlaylist }
        guard segmentURLs.count <= KnitVideoDownloadService.maximumSegmentCount else {
            throw KnitVideoDownloadError.tooManySegments
        }
        return .media(segmentURLs)
    }

    private static func nextResourceLine(after index: Int, in lines: [String]) -> String? {
        guard index < lines.index(before: lines.endIndex) else { return nil }
        for candidate in lines[lines.index(after: index)...] where !candidate.isEmpty {
            if candidate.hasPrefix("#") { continue }
            return candidate
        }
        return nil
    }

    private static func validatedMediaURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        OnlineSourcePolicy.resolvedURL(
            value,
            relativeTo: baseURL,
            source: .knit,
            resource: .media
        )
    }

    private static func bandwidth(in streamInfoLine: String) -> Int {
        let attributeList = streamInfoLine
            .split(separator: ":", maxSplits: 1)
            .last
            .map(String.init) ?? streamInfoLine
        let attributes = attributeList.split(separator: ",")
        for attribute in attributes {
            let pair = attribute.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "BANDWIDTH" else {
                continue
            }
            return Int(pair[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return 0
    }
}

nonisolated enum KnitVideoDownloadService {
    static let maximumSegmentCount = 10_000
    private static let maximumPlaylistBytes = 5 * 1_024 * 1_024
    private static let maximumPlaylistDepth = 3
    private static let copyBufferSize = 1_024 * 1_024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 600
        return URLSession(
            configuration: configuration,
            delegate: OnlineRedirectGuard.shared,
            delegateQueue: nil
        )
    }()

    /// A save operation may surface the managed Cloudflare window only once.
    /// The download is sequential today, but the lock keeps that boundary safe
    /// if playlist or segment fetching is parallelized later.
    private final class ChallengeRecoveryContext: @unchecked Sendable {
        private let lock = NSLock()
        private var didClaimRecovery = false

        func claimRecovery() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didClaimRecovery else { return false }
            didClaimRecovery = true
            return true
        }
    }

    static func suggestedFilename(for item: KnitGalleryItem) -> String {
        "\(AlbumDownloadFileNaming.sanitizedFolderName(item.title))-\(item.id).mp4"
    }

    static func saveMP4(
        from playlistURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (KnitVideoDownloadProgress) -> Void
    ) async throws {
        guard destinationURL.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        try validatePlaylistURL(playlistURL)
        progress(.init(stage: .resolvingPlaylist, completedSegments: 0, totalSegments: 0))
        let challengeRecovery = ChallengeRecoveryContext()
        let segmentURLs = try await resolveMediaPlaylist(
            at: playlistURL,
            depth: 0,
            challengeRecovery: challengeRecovery
        )
        try Task.checkCancellation()

        let fileManager = FileManager.default
        cleanupStaleTemporaryDirectories(fileManager: fileManager)
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("4KHD-KnitVideo-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let transportStreamURL = temporaryDirectory.appendingPathComponent("video.ts")
        guard fileManager.createFile(atPath: transportStreamURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let outputHandle = try FileHandle(forWritingTo: transportStreamURL)
        var transferMeter = KnitVideoTransferMeter()
        do {
            for (index, segmentURL) in segmentURLs.enumerated() {
                try Task.checkCancellation()
                let request = try makeMediaRequest(url: segmentURL, kind: .segment)
                let temporarySegmentURL = try await downloadMediaFile(
                    for: request,
                    challengeRecovery: challengeRecovery,
                    fileManager: fileManager
                )
                defer { try? fileManager.removeItem(at: temporarySegmentURL) }
                let segmentBytes = try fileSize(at: temporarySegmentURL)
                try appendFile(at: temporarySegmentURL, to: outputHandle)
                let transferMetrics = transferMeter.record(
                    segmentBytes: segmentBytes,
                    completedSegments: index + 1,
                    totalSegments: segmentURLs.count
                )
                progress(.init(
                    stage: .downloadingSegments,
                    completedSegments: index + 1,
                    totalSegments: segmentURLs.count,
                    downloadedBytes: transferMetrics.downloadedBytes,
                    totalBytes: transferMetrics.estimatedTotalBytes,
                    bytesPerSecond: transferMetrics.bytesPerSecond,
                    averageBytesPerSecond: transferMetrics.averageBytesPerSecond
                ))
            }
            try outputHandle.close()
        } catch {
            try? outputHandle.close()
            throw error
        }
        try Task.checkCancellation()

        progress(.init(
            stage: .exportingMP4,
            completedSegments: segmentURLs.count,
            totalSegments: segmentURLs.count,
            downloadedBytes: transferMeter.downloadedBytes,
            totalBytes: transferMeter.downloadedBytes,
            averageBytesPerSecond: transferMeter.averageBytesPerSecond
        ))
        let exportedURL = temporaryDirectory.appendingPathComponent("video.mp4")
        let asset = AVURLAsset(url: transportStreamURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw KnitVideoDownloadError.exportUnavailable
        }
        do {
            try await exporter.export(to: exportedURL, as: .mp4)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw KnitVideoDownloadError.exportFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: exportedURL.path) else {
            throw KnitVideoDownloadError.unsupportedTransportStream
        }
        let exportedBytes = try fileSize(at: exportedURL)
        guard exportedBytes > 0 else { throw KnitVideoDownloadError.unsupportedTransportStream }
        try await validateExportedMP4(at: exportedURL)

        progress(.init(
            stage: .installingFile,
            completedSegments: segmentURLs.count,
            totalSegments: segmentURLs.count,
            downloadedBytes: exportedBytes,
            totalBytes: exportedBytes,
            averageBytesPerSecond: transferMeter.averageBytesPerSecond
        ))
        try installAtomically(exportedURL, at: destinationURL)
    }

    private static func resolveMediaPlaylist(
        at url: URL,
        depth: Int,
        challengeRecovery: ChallengeRecoveryContext
    ) async throws -> [URL] {
        guard depth <= maximumPlaylistDepth else { throw KnitVideoDownloadError.invalidPlaylist }
        let request = try makeMediaRequest(url: url, kind: .playlist)
        let data = try await loadMediaData(for: request, challengeRecovery: challengeRecovery)
        guard data.count <= maximumPlaylistBytes else { throw KnitVideoDownloadError.playlistTooLarge }
        guard let text = String(data: data, encoding: .utf8) else {
            throw KnitVideoDownloadError.invalidPlaylist
        }
        switch try KnitHLSPlaylist.parse(text, baseURL: url) {
        case .media(let segments):
            return segments
        case .master(let variants):
            guard let preferred = variants.first else { throw KnitVideoDownloadError.emptyPlaylist }
            return try await resolveMediaPlaylist(
                at: preferred.url,
                depth: depth + 1,
                challengeRecovery: challengeRecovery
            )
        }
    }

    private enum MediaRequestKind {
        case playlist
        case segment
    }

    private static func makeMediaRequest(url: URL, kind: MediaRequestKind) throws -> URLRequest {
        try OnlineSourcePolicy.validate(url, source: .knit, resource: .media)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.setValue(KnitRequestFactory.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://xx.knit.bid/", forHTTPHeaderField: "Referer")
        switch kind {
        case .playlist:
            request.setValue(
                "application/vnd.apple.mpegurl,application/x-mpegURL,application/octet-stream;q=0.9,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
        case .segment:
            request.setValue("video/mp2t,application/octet-stream;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        return request
    }

    private static func validatePlaylistURL(_ url: URL) throws {
        try OnlineSourcePolicy.validate(url, source: .knit, resource: .media)
        guard url.pathExtension.lowercased() == "m3u8" else {
            throw KnitVideoDownloadError.invalidPlaylistURL
        }
    }

    private static func loadMediaData(
        for request: URLRequest,
        challengeRecovery: ChallengeRecoveryContext
    ) async throws -> Data {
        // Playlists are downloaded to URLSession's temporary file first. This
        // keeps a malformed/oversized response from being materialized in RAM
        // before the 5 MB contract can be enforced.
        let fileManager = FileManager.default
        let temporaryURL = try await downloadMediaFile(
            for: request,
            challengeRecovery: challengeRecovery,
            fileManager: fileManager
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        let fileSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= maximumPlaylistBytes else {
            throw KnitVideoDownloadError.playlistTooLarge
        }
        try Task.checkCancellation()
        return try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
    }

    private static func downloadMediaFile(
        for request: URLRequest,
        challengeRecovery: ChallengeRecoveryContext,
        fileManager: FileManager
    ) async throws -> URL {
        let first = try await session.download(for: request)
        let firstResponse: HTTPURLResponse
        do {
            firstResponse = try validatedHTTPResponse(first.1)
        } catch {
            try? fileManager.removeItem(at: first.0)
            throw error
        }

        guard isChallenge(firstResponse) else {
            do {
                try validateSuccessfulResponse(firstResponse)
                return first.0
            } catch {
                try? fileManager.removeItem(at: first.0)
                throw error
            }
        }

        // URLSession owns this temporary response body. Remove the challenge
        // page before waiting for user verification or issuing the sole retry.
        try? fileManager.removeItem(at: first.0)
        let retriedRequest = try await challengeRetryRequest(
            for: request,
            challengeRecovery: challengeRecovery
        )
        let retry = try await session.download(for: retriedRequest)
        do {
            try validateSuccessfulResponse(retry.1)
            return retry.0
        } catch {
            try? fileManager.removeItem(at: retry.0)
            throw error
        }
    }

    private static func challengeRetryRequest(
        for request: URLRequest,
        challengeRecovery: ChallengeRecoveryContext
    ) async throws -> URLRequest {
        guard challengeRecovery.claimRecovery() else {
            throw KnitVideoDownloadError.challengeNotResolved
        }
        try Task.checkCancellation()
        let cookies = try await KnitWebSessionBootstrapper.shared.prepare()
        try Task.checkCancellation()
        return await KnitRequestFactory.addingCookies(cookies, to: request)
    }

    private static func validatedHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        try OnlineSourcePolicy.validate(response, source: .knit, resource: .media)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return response
    }

    private static func validateSuccessfulResponse(_ response: URLResponse) throws {
        let response = try validatedHTTPResponse(response)
        guard !isChallenge(response) else {
            throw KnitVideoDownloadError.challengeNotResolved
        }
        guard (200..<300).contains(response.statusCode) else {
            throw KnitVideoDownloadError.badStatus(response.statusCode)
        }
    }

    private static func isChallenge(_ response: HTTPURLResponse) -> Bool {
        response.statusCode == 403
            || response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge"
    }

    private static func appendFile(at sourceURL: URL, to outputHandle: FileHandle) throws {
        let inputHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? inputHandle.close() }
        while let data = try inputHandle.read(upToCount: copyBufferSize), !data.isEmpty {
            try Task.checkCancellation()
            try outputHandle.write(contentsOf: data)
        }
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }

    private static func installAtomically(_ sourceURL: URL, at destinationURL: URL) throws {
        let fileManager = FileManager.default
        let destinationFolder = destinationURL.deletingLastPathComponent()
        let stagingURL = destinationFolder.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).4khd-\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: stagingURL) }
        try copyFileCancellable(from: sourceURL, to: stagingURL, fileManager: fileManager)
        try Task.checkCancellation()
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        }
    }

    private static func copyFileCancellable(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        do {
            while let data = try input.read(upToCount: copyBufferSize), !data.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: data)
            }
            try input.close()
            try output.close()
        } catch {
            try? input.close()
            try? output.close()
            throw error
        }
    }

    private static func cleanupStaleTemporaryDirectories(fileManager: FileManager) {
        let root = fileManager.temporaryDirectory
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        for candidate in candidates where candidate.lastPathComponent.hasPrefix("4KHD-KnitVideo-") {
            guard let values = try? candidate.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < cutoff else { continue }
            try? fileManager.removeItem(at: candidate)
        }
    }

    private static func validateExportedMP4(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        do {
            let isPlayable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard isPlayable,
                  duration.seconds.isFinite,
                  duration.seconds > 0,
                  !videoTracks.isEmpty else {
                throw KnitVideoDownloadError.invalidExportedFile
            }
        } catch let error as KnitVideoDownloadError {
            throw error
        } catch {
            throw KnitVideoDownloadError.invalidExportedFile
        }
    }
}
