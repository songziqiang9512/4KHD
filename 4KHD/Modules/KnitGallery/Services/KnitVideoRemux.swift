import AVFoundation
import Foundation

/// Lossless local remux used after HLS segments are concatenated.
/// MPEG-TS uses the same `AVAssetExportPresetPassthrough` path as 1.8.9.
/// Already-MP4/fMP4 files are installed as-is.
nonisolated enum KnitVideoRemux {
    enum Container: Equatable {
        case mpegTransportStream
        case mpeg4
        case unknown
    }

    nonisolated static func remux(from sourceURL: URL, to outputURL: URL) async throws {
        try Task.checkCancellation()
        switch try sniff(sourceURL) {
        case .mpeg4:
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: sourceURL, to: outputURL)
            try validateExportedFile(at: outputURL)
            return
        case .mpegTransportStream, .unknown:
            break
        }

        try? FileManager.default.removeItem(at: outputURL)
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw KnitVideoDownloadError.exportUnavailable
        }
        do {
            try await exporter.export(to: outputURL, as: .mp4)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw KnitVideoDownloadError.exportFailed(error.localizedDescription)
        }
        try validateExportedFile(at: outputURL)
    }

    nonisolated static func mpegTransportStreamAligned(_ data: Data) throws -> Data {
        let start: Int
        if data.first == 0x47 {
            start = 0
        } else if let index = data.prefix(188).firstIndex(of: 0x47) {
            start = data.distance(from: data.startIndex, to: index)
        } else {
            throw KnitVideoDownloadError.unsupportedTransportStream
        }
        let packetBytes = ((data.count - start) / 188) * 188
        guard packetBytes >= 188 else {
            throw KnitVideoDownloadError.unsupportedTransportStream
        }
        if start == 0, packetBytes == data.count {
            return data
        }
        return Data(data[start ..< (start + packetBytes)])
    }

    nonisolated static func sniff(_ url: URL) throws -> Container {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 16) ?? Data()
        if prefix.count >= 8, prefix[4 ..< 8] == Data("ftyp".utf8) {
            return .mpeg4
        }
        if prefix.first == 0x47 {
            return .mpegTransportStream
        }
        return .unknown
    }

    /// Confirm the exporter wrote an MP4. Avoid `asset.load`, which hops to
    /// the main actor and can stall the download queue.
    nonisolated static func validateExportedFile(at url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, try sniff(url) == .mpeg4 else {
            throw KnitVideoDownloadError.invalidExportedFile
        }
    }
}
