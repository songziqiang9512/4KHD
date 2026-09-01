import AVFoundation
import CommonCrypto
import Foundation

nonisolated struct KnitVideoDownloadProgress: Equatable {
    enum Stage: Equatable {
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

nonisolated struct KnitVideoTransferMetrics: Equatable {
    let downloadedBytes: Int64
    let estimatedTotalBytes: Int64?
    let bytesPerSecond: Double
    let averageBytesPerSecond: Double
}

/// Tracks bytes at completed HLS segment boundaries. The recent speed is
/// exponentially smoothed so the task center does not jump between segments;
/// the average always spans the whole segment-download phase.
nonisolated struct KnitVideoTransferMeter {
    private let startedAt: Date
    private var lastSampleAt: Date
    private(set) var downloadedBytes: Int64
    private(set) var bytesPerSecond: Double = 0
    private(set) var averageBytesPerSecond: Double = 0

    init(startedAt: Date = Date(), downloadedBytes: Int64 = 0) {
        self.startedAt = startedAt
        lastSampleAt = startedAt
        self.downloadedBytes = max(downloadedBytes, 0)
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
    case invalidEncryptionKey
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
        case let .badStatus(status):
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
            "该影片使用了不支持的加密方式，暂时无法保存为 MP4"
        case .invalidEncryptionKey:
            "影片密钥无效，无法解密保存为 MP4"
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
        case let .exportFailed(message):
            "MP4 封装失败：\(message)"
        case .invalidExportedFile:
            "生成的 MP4 未通过系统播放校验"
        }
    }
}

nonisolated enum KnitHLSPlaylist: Equatable {
    struct Variant: Equatable {
        let url: URL
        let bandwidth: Int
    }

    struct AES128Encryption: Equatable {
        let keyURL: URL
        let iv: Data
    }

    struct MediaSegment: Equatable {
        let url: URL
        let encryption: AES128Encryption?
    }

    case master([Variant])
    case media([MediaSegment])

    static func parse(
        _ text: String,
        baseURL: URL,
        source: OnlineSourcePolicy.Source = .knit
    ) throws -> KnitHLSPlaylist {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.first(where: { !$0.isEmpty })?.uppercased() == "#EXTM3U" else {
            throw KnitVideoDownloadError.invalidPlaylist
        }
        if lines.contains(where: { line in
            let upper = line.uppercased()
            guard upper.hasPrefix("#EXT-X-KEY:") else { return false }
            let method = hlsAttributeMap(line)["METHOD"]?.uppercased() ?? ""
            return method != "NONE" && method != "AES-128"
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
                  let url = validatedMediaURL(rawURL, relativeTo: baseURL, source: source),
                  url.pathExtension.lowercased() == "m3u8"
            else {
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
        var mediaSequence = 0
        var keyURL: URL?
        var explicitIV: Data?
        var segmentURLs: [MediaSegment] = []
        for line in lines {
            let upper = line.uppercased()
            if upper.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                let value = line.split(separator: ":", maxSplits: 1).last
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                mediaSequence = Int(value) ?? 0
                continue
            }
            if upper.hasPrefix("#EXT-X-KEY:") {
                let attributes = hlsAttributeMap(line)
                let method = attributes["METHOD"]?.uppercased() ?? ""
                if method == "NONE" {
                    keyURL = nil
                    explicitIV = nil
                    continue
                }
                guard method == "AES-128", let uri = attributes["URI"] else {
                    throw KnitVideoDownloadError.invalidPlaylist
                }
                guard let resolvedKeyURL = validatedMediaURL(uri, relativeTo: baseURL, source: source) else {
                    throw OnlineSourcePolicy.PolicyError.rejectedURL
                }
                keyURL = resolvedKeyURL
                if let ivValue = attributes["IV"] {
                    guard let iv = dataFromHexIV(ivValue), iv.count == 16 else {
                        throw KnitVideoDownloadError.invalidPlaylist
                    }
                    explicitIV = iv
                } else {
                    explicitIV = nil
                }
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let url = validatedMediaURL(line, relativeTo: baseURL, source: source) else {
                throw OnlineSourcePolicy.PolicyError.rejectedURL
            }
            let encryption: AES128Encryption?
            if let keyURL {
                encryption = AES128Encryption(
                    keyURL: keyURL,
                    iv: explicitIV ?? ivFromMediaSequence(mediaSequence)
                )
            } else {
                encryption = nil
            }
            segmentURLs.append(MediaSegment(url: url, encryption: encryption))
            mediaSequence += 1
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

    private static func validatedMediaURL(
        _ value: String,
        relativeTo baseURL: URL,
        source: OnlineSourcePolicy.Source
    ) -> URL? {
        OnlineSourcePolicy.resolvedURL(
            value,
            relativeTo: baseURL,
            source: source,
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
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "BANDWIDTH"
            else {
                continue
            }
            return Int(pair[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return 0
    }

    private static func hlsAttributeMap(_ line: String) -> [String: String] {
        guard let colon = line.firstIndex(of: ":") else { return [:] }
        let body = line[line.index(after: colon)...]
        var result: [String: String] = [:]
        var index = body.startIndex
        while index < body.endIndex {
            while index < body.endIndex, body[index] == "," || body[index].isWhitespace {
                index = body.index(after: index)
            }
            guard index < body.endIndex,
                  let equals = body[index...].firstIndex(of: "=")
            else { break }
            let name = body[index ..< equals].trimmingCharacters(in: .whitespaces).uppercased()
            var valueStart = body.index(after: equals)
            let value: String
            if valueStart < body.endIndex, body[valueStart] == "\"" {
                valueStart = body.index(after: valueStart)
                if let endQuote = body[valueStart...].firstIndex(of: "\"") {
                    value = String(body[valueStart ..< endQuote])
                    index = body.index(after: endQuote)
                } else {
                    value = String(body[valueStart...])
                    index = body.endIndex
                }
            } else if let comma = body[valueStart...].firstIndex(of: ",") {
                value = String(body[valueStart ..< comma]).trimmingCharacters(in: .whitespaces)
                index = comma
            } else {
                value = String(body[valueStart...]).trimmingCharacters(in: .whitespaces)
                index = body.endIndex
            }
            result[name] = value
        }
        return result
    }

    private static func dataFromHexIV(_ value: String) -> Data? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.lowercased().hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        guard hex.count == 32, hex.allSatisfy(\.isHexDigit) else { return nil }
        var data = Data()
        data.reserveCapacity(16)
        var cursor = hex.startIndex
        while cursor < hex.endIndex {
            let next = hex.index(cursor, offsetBy: 2)
            guard let byte = UInt8(hex[cursor ..< next], radix: 16) else { return nil }
            data.append(byte)
            cursor = next
        }
        return data
    }

    private static func ivFromMediaSequence(_ sequence: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        var value = UInt64(max(sequence, 0))
        for offset in (0 ..< 8).reversed() {
            bytes[8 + offset] = UInt8(truncatingIfNeeded: value)
            value >>= 8
        }
        return Data(bytes)
    }

    /// AES-128 info for playback. Prefers the download parser; if the playlist
    /// is too strict to parse, falls back to the first KEY tag's URI and IV.
    static func playbackAES128(
        _ text: String,
        baseURL: URL,
        source: OnlineSourcePolicy.Source
    ) -> (keyURL: URL, defaultIV: Data, ivByURL: [URL: Data])? {
        if case let .media(segments) = try? parse(text, baseURL: baseURL, source: source),
           let first = segments.first(where: { $0.encryption != nil })?.encryption
        {
            var ivByURL: [URL: Data] = [:]
            for segment in segments {
                if let encryption = segment.encryption {
                    ivByURL[segment.url] = encryption.iv
                }
            }
            return (first.keyURL, first.iv, ivByURL)
        }
        return aes128FromFirstKeyLine(text, baseURL: baseURL, source: source)
    }

    private static func aes128FromFirstKeyLine(
        _ text: String,
        baseURL: URL,
        source: OnlineSourcePolicy.Source
    ) -> (keyURL: URL, defaultIV: Data, ivByURL: [URL: Data])? {
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix("#EXT-X-KEY:") else { continue }
            let attributes = hlsAttributeMap(trimmed)
            guard attributes["METHOD"]?.uppercased() == "AES-128",
                  let uri = attributes["URI"],
                  let keyURL = validatedMediaURL(uri, relativeTo: baseURL, source: source)
            else { return nil }
            let iv = attributes["IV"].flatMap(dataFromHexIV) ?? ivFromMediaSequence(0)
            return (keyURL, iv, [:])
        }
        return nil
    }
}

nonisolated enum KnitVideoDownloadService {
    static let maximumSegmentCount = 10000
    private static let maximumPlaylistBytes = 5 * 1024 * 1024
    private static let maximumPlaylistDepth = 3
    private static let copyBufferSize = 1024 * 1024

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

    private static let maximumKeyBytes = 64

    private struct SessionContext {
        let source: OnlineSourcePolicy.Source
        let userAgent: String
        let referer: String
        let challengeRecovery: ChallengeRecoveryContext

        var allowsChallengeRecovery: Bool {
            source == .knit
        }
    }

    static func suggestedFilename(title: String, id: String) -> String {
        "\(AlbumDownloadFileNaming.sanitizedFolderName(title))-\(id).mp4"
    }

    static func suggestedFilename(for item: KnitGalleryItem) -> String {
        suggestedFilename(title: item.title, id: item.id)
    }

    static func discardCheckpoint(playlistURL: URL, destinationURL: URL) {
        try? FileManager.default.removeItem(
            at: workDirectory(playlistURL: playlistURL, destinationURL: destinationURL)
        )
    }

    static func saveMP4(
        from playlistURL: URL,
        to destinationURL: URL,
        source: OnlineSourcePolicy.Source = .knit,
        userAgent: String? = nil,
        referer: String? = nil,
        progress: @escaping @Sendable (KnitVideoDownloadProgress) -> Void
    ) async throws {
        guard destinationURL.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        try validatePlaylistURL(playlistURL, source: source)
        progress(.init(stage: .resolvingPlaylist, completedSegments: 0, totalSegments: 0))
        let context = SessionContext(
            source: source,
            userAgent: userAgent ?? KnitRequestFactory.userAgent,
            referer: referer ?? defaultReferer(for: source),
            challengeRecovery: ChallengeRecoveryContext()
        )
        let segments = try await resolveMediaPlaylist(
            at: playlistURL,
            depth: 0,
            context: context
        )
        try Task.checkCancellation()

        let fileManager = FileManager.default
        cleanupStaleTemporaryDirectories(fileManager: fileManager)
        let accessedDestination = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if accessedDestination {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }
        let workDirectory = workDirectory(playlistURL: playlistURL, destinationURL: destinationURL)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        var didInstall = false
        defer {
            if didInstall {
                try? fileManager.removeItem(at: workDirectory)
            }
        }

        let transportStreamURL = workDirectory.appendingPathComponent("video.ts")
        let checkpointURL = workDirectory.appendingPathComponent("checkpoint.json")
        let restored = loadCheckpoint(
            at: checkpointURL,
            playlistURL: playlistURL,
            totalSegments: segments.count,
            transportStreamURL: transportStreamURL,
            fileManager: fileManager
        )
        let startIndex = restored.completedSegments
        if startIndex == 0 || !fileManager.fileExists(atPath: transportStreamURL.path) {
            guard fileManager.createFile(atPath: transportStreamURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let outputHandle = try FileHandle(forWritingTo: transportStreamURL)
        if startIndex > 0 {
            try outputHandle.truncate(atOffset: restored.fileOffset)
            try outputHandle.seek(toOffset: restored.fileOffset)
        }
        var transferMeter = KnitVideoTransferMeter(downloadedBytes: restored.downloadedBytes)
        if startIndex > 0 {
            progress(.init(
                stage: .downloadingSegments,
                completedSegments: startIndex,
                totalSegments: segments.count,
                downloadedBytes: restored.downloadedBytes,
                totalBytes: restored.downloadedBytes
            ))
        }
        var keyCache: [URL: Data] = [:]
        do {
            if startIndex < segments.count {
                for index in startIndex ..< segments.count {
                    try Task.checkCancellation()
                    let segment = segments[index]
                    let request = try makeMediaRequest(url: segment.url, kind: .segment, context: context)
                    let temporarySegmentURL = try await downloadMediaFile(
                        for: request,
                        context: context,
                        fileManager: fileManager
                    )
                    defer { try? fileManager.removeItem(at: temporarySegmentURL) }
                    let segmentBytes: Int64
                    if let encryption = segment.encryption {
                        let key = try await cachedKey(encryption.keyURL, cache: &keyCache, context: context)
                        let cipher = try Data(contentsOf: temporarySegmentURL)
                        segmentBytes = Int64(cipher.count)
                        let plain = try KnitHLSAES128.decrypt(cipher, key: key, iv: encryption.iv)
                        try outputHandle.write(contentsOf: plain)
                    } else {
                        segmentBytes = try fileSize(at: temporarySegmentURL)
                        try appendFile(at: temporarySegmentURL, to: outputHandle)
                    }
                    try outputHandle.synchronize()
                    let fileOffset = try outputHandle.offset()
                    let transferMetrics = transferMeter.record(
                        segmentBytes: segmentBytes,
                        completedSegments: index + 1,
                        totalSegments: segments.count
                    )
                    try writeCheckpoint(
                        Checkpoint(
                            playlistURL: playlistURL.absoluteString,
                            completedSegments: index + 1,
                            totalSegments: segments.count,
                            downloadedBytes: transferMetrics.downloadedBytes,
                            fileOffset: fileOffset
                        ),
                        to: checkpointURL
                    )
                    progress(.init(
                        stage: .downloadingSegments,
                        completedSegments: index + 1,
                        totalSegments: segments.count,
                        downloadedBytes: transferMetrics.downloadedBytes,
                        totalBytes: transferMetrics.estimatedTotalBytes,
                        bytesPerSecond: transferMetrics.bytesPerSecond,
                        averageBytesPerSecond: transferMetrics.averageBytesPerSecond
                    ))
                }
            }
            try outputHandle.close()
        } catch {
            try? outputHandle.close()
            throw error
        }
        try Task.checkCancellation()

        progress(.init(
            stage: .exportingMP4,
            completedSegments: segments.count,
            totalSegments: segments.count,
            downloadedBytes: transferMeter.downloadedBytes,
            totalBytes: transferMeter.downloadedBytes,
            averageBytesPerSecond: transferMeter.averageBytesPerSecond
        ))
        do {
            let exportedURL = try await exportPassthroughMP4(from: transportStreamURL)
            defer { try? fileManager.removeItem(at: exportedURL.deletingLastPathComponent()) }
            try Task.checkCancellation()
            let exportedBytes = try fileSize(at: exportedURL)
            guard exportedBytes > 0 else { throw KnitVideoDownloadError.unsupportedTransportStream }

            progress(.init(
                stage: .installingFile,
                completedSegments: segments.count,
                totalSegments: segments.count,
                downloadedBytes: exportedBytes,
                totalBytes: exportedBytes,
                averageBytesPerSecond: transferMeter.averageBytesPerSecond
            ))
            try installAtomically(exportedURL, at: destinationURL)
            didInstall = true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try? fileManager.removeItem(at: workDirectory)
            throw error
        }
    }

    private static func defaultReferer(for source: OnlineSourcePolicy.Source) -> String {
        switch source {
        case .mrds: "https://www.mrds66.com/"
        case .quanji: "https://91quanji.com/"
        case .porny: "https://91porny.com/"
        case .tangxin: "https://tangxinvlog.app/"
        case .knit, .gallery, .missKon, .wallhaven: "https://xx.knit.bid/"
        }
    }

    private static func cachedKey(
        _ url: URL,
        cache: inout [URL: Data],
        context: SessionContext
    ) async throws -> Data {
        if let cached = cache[url] { return cached }
        let request = try makeMediaRequest(url: url, kind: .key, context: context)
        let data = try await loadMediaData(
            for: request,
            context: context,
            maximumBytes: maximumKeyBytes
        )
        guard data.count == kCCKeySizeAES128 else {
            throw KnitVideoDownloadError.invalidEncryptionKey
        }
        cache[url] = data
        return data
    }

    private static func resolveMediaPlaylist(
        at url: URL,
        depth: Int,
        context: SessionContext
    ) async throws -> [KnitHLSPlaylist.MediaSegment] {
        guard depth <= maximumPlaylistDepth else { throw KnitVideoDownloadError.invalidPlaylist }
        let request = try makeMediaRequest(url: url, kind: .playlist, context: context)
        let data = try await loadMediaData(for: request, context: context)
        guard data.count <= maximumPlaylistBytes else { throw KnitVideoDownloadError.playlistTooLarge }
        guard let text = String(data: data, encoding: .utf8) else {
            throw KnitVideoDownloadError.invalidPlaylist
        }
        switch try KnitHLSPlaylist.parse(text, baseURL: url, source: context.source) {
        case let .media(segments):
            return segments
        case let .master(variants):
            guard let preferred = variants.first else { throw KnitVideoDownloadError.emptyPlaylist }
            return try await resolveMediaPlaylist(
                at: preferred.url,
                depth: depth + 1,
                context: context
            )
        }
    }

    private enum MediaRequestKind {
        case playlist
        case segment
        case key
    }

    private static func makeMediaRequest(
        url: URL,
        kind: MediaRequestKind,
        context: SessionContext
    ) throws -> URLRequest {
        try OnlineSourcePolicy.validate(url, source: context.source, resource: .media)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.setValue(context.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(context.referer, forHTTPHeaderField: "Referer")
        if let origin = OnlineSourcePolicy.originHeader(fromReferer: context.referer) {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        switch kind {
        case .playlist:
            request.setValue(
                "application/vnd.apple.mpegurl,application/x-mpegURL,application/octet-stream;q=0.9,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
        case .segment:
            request.setValue("video/mp2t,application/octet-stream;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        case .key:
            request.setValue("application/octet-stream,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        return request
    }

    private static func validatePlaylistURL(_ url: URL, source: OnlineSourcePolicy.Source) throws {
        try OnlineSourcePolicy.validate(url, source: source, resource: .media)
        guard url.pathExtension.lowercased() == "m3u8" else {
            throw KnitVideoDownloadError.invalidPlaylistURL
        }
    }

    private static func loadMediaData(
        for request: URLRequest,
        context: SessionContext,
        maximumBytes: Int? = nil
    ) async throws -> Data {
        // Playlists are downloaded to URLSession's temporary file first. This
        // keeps a malformed/oversized response from being materialized in RAM
        // before the 5 MB contract can be enforced.
        let limit = maximumBytes ?? maximumPlaylistBytes
        let fileManager = FileManager.default
        let temporaryURL = try await downloadMediaFile(
            for: request,
            context: context,
            fileManager: fileManager
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        let fileSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= limit else {
            throw KnitVideoDownloadError.playlistTooLarge
        }
        try Task.checkCancellation()
        return try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
    }

    private static func downloadMediaFile(
        for request: URLRequest,
        context: SessionContext,
        fileManager: FileManager
    ) async throws -> URL {
        let first = try await session.download(for: request)
        let firstResponse: HTTPURLResponse
        do {
            firstResponse = try validatedHTTPResponse(first.1, source: context.source)
        } catch {
            try? fileManager.removeItem(at: first.0)
            throw error
        }

        guard isChallenge(firstResponse) else {
            do {
                try validateSuccessfulResponse(firstResponse, source: context.source)
                return first.0
            } catch {
                try? fileManager.removeItem(at: first.0)
                throw error
            }
        }

        guard context.allowsChallengeRecovery else {
            try? fileManager.removeItem(at: first.0)
            throw KnitVideoDownloadError.badStatus(firstResponse.statusCode)
        }

        // URLSession owns this temporary response body. Remove the challenge
        // page before waiting for user verification or issuing the sole retry.
        try? fileManager.removeItem(at: first.0)
        let retriedRequest = try await challengeRetryRequest(
            for: request,
            challengeRecovery: context.challengeRecovery
        )
        let retry = try await session.download(for: retriedRequest)
        do {
            try validateSuccessfulResponse(retry.1, source: context.source)
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

    private static func validatedHTTPResponse(
        _ response: URLResponse,
        source: OnlineSourcePolicy.Source
    ) throws -> HTTPURLResponse {
        try OnlineSourcePolicy.validate(response, source: source, resource: .media)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return response
    }

    private static func validateSuccessfulResponse(
        _ response: URLResponse,
        source: OnlineSourcePolicy.Source
    ) throws {
        let response = try validatedHTTPResponse(response, source: source)
        guard !isChallenge(response) else {
            throw KnitVideoDownloadError.challengeNotResolved
        }
        guard (200 ..< 300).contains(response.statusCode) else {
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
        try Int64(url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }

    /// Same working set as 1.8.9: unique `temporaryDirectory` folder, Passthrough
    /// export next to the concatenated TS, then system playability checks.
    private static func exportPassthroughMP4(from transportStreamURL: URL) async throws -> URL {
        let fileManager = FileManager.default
        let exportDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("4KHD-KnitVideo-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let exportSource = exportDirectory.appendingPathComponent("video.ts")
        let exportedURL = exportDirectory.appendingPathComponent("video.mp4")
        do {
            try fileManager.linkItem(at: transportStreamURL, to: exportSource)
        } catch {
            try fileManager.copyItem(at: transportStreamURL, to: exportSource)
        }
        let asset = AVURLAsset(url: exportSource)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            try? fileManager.removeItem(at: exportDirectory)
            throw KnitVideoDownloadError.exportUnavailable
        }
        do {
            try await exporter.export(to: exportedURL, as: .mp4)
        } catch is CancellationError {
            try? fileManager.removeItem(at: exportDirectory)
            throw CancellationError()
        } catch {
            try? fileManager.removeItem(at: exportDirectory)
            throw KnitVideoDownloadError.exportFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: exportedURL.path) else {
            try? fileManager.removeItem(at: exportDirectory)
            throw KnitVideoDownloadError.unsupportedTransportStream
        }
        let exportedBytes = try fileSize(at: exportedURL)
        guard exportedBytes > 0 else {
            try? fileManager.removeItem(at: exportDirectory)
            throw KnitVideoDownloadError.unsupportedTransportStream
        }
        do {
            try await validateExportedMP4(at: exportedURL)
        } catch {
            try? fileManager.removeItem(at: exportDirectory)
            throw error
        }
        return exportedURL
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
                  !videoTracks.isEmpty
            else {
                throw KnitVideoDownloadError.invalidExportedFile
            }
        } catch let error as KnitVideoDownloadError {
            throw error
        } catch {
            throw KnitVideoDownloadError.invalidExportedFile
        }
    }

    private static func installAtomically(_ sourceURL: URL, at destinationURL: URL) throws {
        let fileManager = FileManager.default
        // Stage inside the app container. A sibling temp next to the user-chosen
        // file is outside the NSSavePanel grant and fails anywhere except
        // Downloads / Pictures.
        let stagingURL = fileManager.temporaryDirectory.appendingPathComponent(
            "4KHD-install-\(UUID().uuidString).mp4"
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

    private struct Checkpoint: Codable {
        var playlistURL: String
        var completedSegments: Int
        var totalSegments: Int
        var downloadedBytes: Int64
        var fileOffset: UInt64
    }

    private static func workDirectory(playlistURL: URL, destinationURL: URL) -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("4KHD-KnitVideo", isDirectory: true)
            .appendingPathComponent(
                sha256Hex(playlistURL.absoluteString + "\n" + destinationURL.path),
                isDirectory: true
            )
    }

    private static func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadCheckpoint(
        at url: URL,
        playlistURL: URL,
        totalSegments: Int,
        transportStreamURL: URL,
        fileManager: FileManager
    ) -> (completedSegments: Int, downloadedBytes: Int64, fileOffset: UInt64) {
        let empty = (0, Int64(0), UInt64(0))
        guard fileManager.fileExists(atPath: url.path),
              fileManager.fileExists(atPath: transportStreamURL.path),
              let data = try? Data(contentsOf: url),
              let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data),
              checkpoint.playlistURL == playlistURL.absoluteString,
              checkpoint.totalSegments == totalSegments,
              checkpoint.completedSegments > 0,
              checkpoint.completedSegments <= totalSegments
        else { return empty }
        let fileSize = (try? fileSize(at: transportStreamURL)).map { UInt64(max($0, 0)) } ?? 0
        guard checkpoint.fileOffset > 0, fileSize >= checkpoint.fileOffset else { return empty }
        return (checkpoint.completedSegments, checkpoint.downloadedBytes, checkpoint.fileOffset)
    }

    private static func writeCheckpoint(_ checkpoint: Checkpoint, to url: URL) throws {
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: url, options: .atomic)
    }

    private static func cleanupStaleTemporaryDirectories(fileManager: FileManager) {
        let root = fileManager.temporaryDirectory
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        if let candidates = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) {
            for candidate in candidates where candidate.lastPathComponent.hasPrefix("4KHD-KnitVideo-") {
                guard let values = try? candidate.resourceValues(forKeys: keys),
                      values.isDirectory == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt < cutoff else { continue }
                try? fileManager.removeItem(at: candidate)
            }
        }
        let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("4KHD-KnitVideo", isDirectory: true)
        let cacheCutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        if let cacheRoot,
           let workspaces = try? fileManager.contentsOfDirectory(
               at: cacheRoot,
               includingPropertiesForKeys: Array(keys),
               options: [.skipsHiddenFiles]
           )
        {
            for candidate in workspaces {
                guard let values = try? candidate.resourceValues(forKeys: keys),
                      values.isDirectory == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt < cacheCutoff else { continue }
                try? fileManager.removeItem(at: candidate)
            }
        }
    }
}

nonisolated enum KnitHLSAES128 {
    nonisolated static func decrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        try crypt(operation: CCOperation(kCCDecrypt), data: data, key: key, iv: iv)
    }

    nonisolated static func encryptForTesting(_ data: Data, key: Data, iv: Data) throws -> Data {
        try crypt(operation: CCOperation(kCCEncrypt), data: data, key: key, iv: iv)
    }

    private nonisolated static func crypt(
        operation: CCOperation,
        data: Data,
        key: Data,
        iv: Data
    ) throws -> Data {
        guard key.count == kCCKeySizeAES128,
              iv.count == kCCBlockSizeAES128,
              !data.isEmpty
        else {
            throw KnitVideoDownloadError.invalidEncryptionKey
        }
        var outLength = 0
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let status = output.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outBytes.baseAddress,
                            outBytes.count,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw KnitVideoDownloadError.invalidEncryptionKey }
        output.removeSubrange(outLength...)
        return output
    }
}
