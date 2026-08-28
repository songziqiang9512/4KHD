import Foundation

/// A source-neutral single-file download job. The owning module supplies the
/// actual transfer/remux implementation; DownloadStore only owns queueing,
/// progress, cancellation, and presentation state.
nonisolated struct SingleFileDownloadProgress: Sendable, Equatable {
    let fractionCompleted: Double
    let statusText: String
    let downloadedBytes: Int64
    let totalBytes: Int64?
    let bytesPerSecond: Double
    let averageBytesPerSecond: Double

    init(
        fractionCompleted: Double,
        statusText: String,
        downloadedBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        bytesPerSecond: Double = 0,
        averageBytesPerSecond: Double = 0
    ) {
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.statusText = statusText
        let normalizedDownloadedBytes = max(downloadedBytes, 0)
        self.downloadedBytes = normalizedDownloadedBytes
        self.totalBytes = totalBytes.map { max($0, normalizedDownloadedBytes) }
        self.bytesPerSecond = max(bytesPerSecond, 0)
        self.averageBytesPerSecond = max(averageBytesPerSecond, 0)
    }
}

nonisolated struct SingleFileDownloadSource: Sendable {
    let detailURL: URL
    let sourceURL: URL
    let title: String
    let sourceTitle: String
    let perform: @Sendable (
        URL,
        @escaping @Sendable (SingleFileDownloadProgress) -> Void
    ) async throws -> Void
}
