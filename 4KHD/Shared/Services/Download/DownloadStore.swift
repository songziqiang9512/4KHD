import AppKit
import Foundation
import Observation

/// 图集批量下载管理器:持有任务列表、严格串行调度队列、取消与清理。
/// 任务不持久化,重启清空;已下载文件保留。
@MainActor
@Observable
final class DownloadStore {
    enum TaskKind: Equatable {
        case album
        case video
    }

    enum TaskStatus: Equatable {
        case queued
        case running
        case completed
        case failed
        case cancelled

        var isTerminal: Bool {
            self == .completed || self == .failed || self == .cancelled
        }
    }

    struct DownloadTask: Identifiable {
        let id: UUID
        let kind: TaskKind
        let title: String
        let sourceTitle: String
        let detailURL: URL
        let destinationURL: URL
        var status: TaskStatus
        var completedCount: Int
        var totalCount: Int
        var failedCount: Int
        var failedPageCount: Int
        var progressFraction: Double
        var progressText: String
        var downloadedBytes: Int64
        var totalBytes: Int64?
        var bytesPerSecond: Double
        var averageBytesPerSecond: Double
        var errorMessage: String
        var startedAt: Date?
        var finishedAt: Date?

        var destinationFolderURL: URL {
            kind == .album ? destinationURL : destinationURL.deletingLastPathComponent()
        }

        var revealURL: URL { destinationURL }
    }

    enum EnqueueAlbumResult: Equatable {
        case enqueued
        case duplicate
        case cancelled
    }

    enum EnqueueFileResult: Equatable {
        case enqueued
        case duplicate
        case destinationInUse
    }

    var tasks: [DownloadTask] = []

    /// 测试注入点:替换引擎默认的图片拉取实现,生产环境保持 nil。
    @ObservationIgnored var imageFetcher: AlbumImageDataFetcher?

    private enum WorkSource {
        case album(AlbumDownloadSource)
        case singleFile(SingleFileDownloadSource)
    }

    @ObservationIgnored private var workSources: [UUID: WorkSource] = [:]
    @ObservationIgnored private var activeJob: Task<Void, Never>?
    @ObservationIgnored private let registry = ImageTaskRegistry()
    /// 会话内已分配的目标目录路径:同名图集并发下载时各得各的目录,
    /// 不会因为目录尚不存在/为空而复用同一目录互相覆盖。
    @ObservationIgnored private var reservedFolderPaths = Set<String>()
    /// 活动单文件任务的目标路径。保存面板只能检查当前磁盘状态；首个任务
    /// 尚未落盘时，第二个不同视频仍可能选择同一路径，因此队列内还要预留。
    @ObservationIgnored private var reservedFileDestinationKeys = Set<String>()
    /// 进度推算用的每任务累计值(去重后张数 / 已解析页数)。
    @ObservationIgnored private var resolvedImageTotals: [UUID: Int] = [:]
    @ObservationIgnored private var resolvedPageCounts: [UUID: Int] = [:]
    @ObservationIgnored private var albumTransferSamples: [UUID: AlbumTransferSample] = [:]

    private struct AlbumTransferSample {
        var downloadedBytes: Int64
        var recordedAt: Date
        var smoothedBytesPerSecond: Double
    }

    // MARK: - 入队

    /// 弹目录选择面板,选定后按图集名建子目录并入队。
    /// 返回 .cancelled 表示用户取消选择,.duplicate 表示已在队列中。
    func enqueueAlbumChoosingFolder(source: AlbumDownloadSource) -> EnqueueAlbumResult {
        guard let destinationRoot = DownloadFolderPicker.chooseDirectory() else {
            return .cancelled
        }
        return enqueueAlbum(source: source, destinationRoot: destinationRoot)
    }

    /// 入队一个图集下载。同 detailURL 已在 queued/running 时拒绝并返回
    /// .duplicate,由调用方提示用户。
    @discardableResult
    func enqueueAlbum(source: AlbumDownloadSource, destinationRoot: URL) -> EnqueueAlbumResult {
        let isDuplicated = tasks.contains { task in
            (task.status == .queued || task.status == .running)
                && task.detailURL.absoluteString == source.detailURL.absoluteString
        }
        guard !isDuplicated else { return .duplicate }

        let destinationFolderURL = AlbumDownloadFileNaming.uniqueDestinationFolder(
            root: destinationRoot,
            albumName: source.title,
            excluding: reservedFolderPaths
        )
        reservedFolderPaths.insert(destinationFolderURL.path)
        let task = DownloadTask(
            id: UUID(),
            kind: .album,
            title: source.title,
            sourceTitle: "在线图库",
            detailURL: source.detailURL,
            destinationURL: destinationFolderURL,
            status: .queued,
            completedCount: 0,
            totalCount: source.estimatedImageCount,
            failedCount: 0,
            failedPageCount: 0,
            progressFraction: 0,
            progressText: "等待下载",
            downloadedBytes: 0,
            totalBytes: nil,
            bytesPerSecond: 0,
            averageBytesPerSecond: 0,
            errorMessage: "",
            startedAt: nil,
            finishedAt: nil
        )
        workSources[task.id] = .album(source)
        tasks.append(task)
        pumpQueue()
        return .enqueued
    }

    /// Enqueues a module-owned single-file job into the same serial queue used
    /// by albums. The caller chooses the final file URL before enqueueing.
    @discardableResult
    func enqueueFile(
        source: SingleFileDownloadSource,
        destinationURL: URL
    ) -> EnqueueFileResult {
        let isDuplicated = tasks.contains { task in
            task.kind == .video
                && (task.status == .queued || task.status == .running)
                && task.detailURL.absoluteString == source.detailURL.absoluteString
        }
        guard !isDuplicated else { return .duplicate }
        let destinationKey = fileDestinationReservationKey(for: destinationURL)
        guard !reservedFileDestinationKeys.contains(destinationKey) else {
            return .destinationInUse
        }
        reservedFileDestinationKeys.insert(destinationKey)

        let task = DownloadTask(
            id: UUID(),
            kind: .video,
            title: source.title,
            sourceTitle: source.sourceTitle,
            detailURL: source.detailURL,
            destinationURL: destinationURL,
            status: .queued,
            completedCount: 0,
            totalCount: 0,
            failedCount: 0,
            failedPageCount: 0,
            progressFraction: 0,
            progressText: "等待下载",
            downloadedBytes: 0,
            totalBytes: nil,
            bytesPerSecond: 0,
            averageBytesPerSecond: 0,
            errorMessage: "",
            startedAt: nil,
            finishedAt: nil
        )
        workSources[task.id] = .singleFile(source)
        tasks.append(task)
        pumpQueue()
        return .enqueued
    }

    var hasActiveVideoDownload: Bool {
        tasks.contains {
            $0.kind == .video && ($0.status == .queued || $0.status == .running)
        }
    }

    // MARK: - 取消 / 移除

    func cancelTask(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        switch tasks[index].status {
        case .queued:
            tasks[index].status = .cancelled
            tasks[index].finishedAt = Date()
            workSources[id] = nil
            resolvedImageTotals[id] = nil
            resolvedPageCounts[id] = nil
            albumTransferSamples[id] = nil
            releaseReservedDestination(for: tasks[index])
        case .running:
            activeJob?.cancel()
            registry.cancelAll()
        default:
            break
        }
    }

    func cancelAll() {
        activeJob?.cancel()
        registry.cancelAll()
        for index in tasks.indices where tasks[index].status == .queued {
            tasks[index].status = .cancelled
            tasks[index].finishedAt = Date()
            let taskID = tasks[index].id
            workSources[taskID] = nil
            resolvedImageTotals[taskID] = nil
            resolvedPageCounts[taskID] = nil
            albumTransferSamples[taskID] = nil
            releaseReservedDestination(for: tasks[index])
        }
    }

    /// 仅终态任务可移除。
    func removeTask(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].status.isTerminal else { return }
        releaseReservedDestination(for: tasks[index])
        tasks.remove(at: index)
        workSources[id] = nil
        albumTransferSamples[id] = nil
    }

    func clearFinishedTasks() {
        let finishedTasks = tasks.filter { $0.status.isTerminal }
        guard !finishedTasks.isEmpty else { return }
        finishedTasks.forEach { releaseReservedDestination(for: $0) }
        let finishedIDs = finishedTasks.map(\.id)
        tasks.removeAll { $0.status.isTerminal }
        finishedIDs.forEach { id in
            workSources[id] = nil
            resolvedImageTotals[id] = nil
            resolvedPageCounts[id] = nil
            albumTransferSamples[id] = nil
        }
    }

    /// 应用退出时调用:中断当前任务与在飞请求,不清理列表与文件。
    func shutdown() {
        activeJob?.cancel()
        registry.cancelAll()
    }

    // MARK: - 串行调度

    private func pumpQueue() {
        guard activeJob == nil,
              let index = tasks.firstIndex(where: { $0.status == .queued }) else { return }
        guard let source = workSources[tasks[index].id] else {
            tasks[index].status = .failed
            tasks[index].errorMessage = "下载源缺失"
            tasks[index].finishedAt = Date()
            workSources[tasks[index].id] = nil
            releaseReservedDestination(for: tasks[index])
            pumpQueue()
            return
        }

        let taskID = tasks[index].id
        tasks[index].status = .running
        let startedAt = Date()
        tasks[index].startedAt = startedAt
        if case .album = source {
            albumTransferSamples[taskID] = AlbumTransferSample(
                downloadedBytes: 0,
                recordedAt: startedAt,
                smoothedBytesPerSecond: 0
            )
        }
        let destinationURL = tasks[index].destinationURL

        let job = Task { [weak self] in
            guard let self else { return }
            switch source {
            case .album(let albumSource):
                let summary = await AlbumDownloadOrchestrator.run(
                    source: albumSource,
                    destinationFolder: destinationURL,
                    maxConcurrentImages: 3,
                    registry: registry,
                    emit: { event in
                        Task { @MainActor [weak self] in
                            self?.apply(event, to: taskID)
                        }
                    },
                    fetcher: imageFetcher
                )
                finishAlbumTask(id: taskID, summary: summary)
            case .singleFile(let fileSource):
                do {
                    try await fileSource.perform(destinationURL) { progress in
                        Task { @MainActor [weak self] in
                            self?.apply(progress, to: taskID)
                        }
                    }
                    try Task.checkCancellation()
                    finishFileTask(id: taskID, result: .success(()))
                } catch is CancellationError {
                    finishFileTask(id: taskID, result: .failure(CancellationError()))
                } catch {
                    finishFileTask(id: taskID, result: .failure(error))
                }
            }
        }
        activeJob = job
    }

    private func apply(_ event: AlbumDownloadEvent, to id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].status == .running else { return }
        var task = tasks[index]
        switch event {
        case .pageResolved(_, let pageCount, let imageCount):
            // 按已解析页的去重张数推算总张数(剩余页按当前平均估算),
            // 比入队时的 estimatedImageCount 更接近真实值;任务终结时
            // finishTask 会用精确值覆盖,保证进度条最终到达 100%。
            resolvedImageTotals[id, default: 0] += imageCount
            resolvedPageCounts[id, default: 0] += 1
            let resolvedImages = resolvedImageTotals[id, default: 0]
            let resolvedPages = resolvedPageCounts[id, default: 1]
            let remainingPages = max(pageCount - resolvedPages, 0)
            let averagePerPage = max(resolvedImages / resolvedPages, 1)
            task.totalCount = max(task.totalCount, resolvedImages + remainingPages * averagePerPage)
            updateAlbumTotalBytesEstimate(on: &task)
        case .pageFailed:
            task.failedPageCount += 1
        case .imageSucceeded(_, _, let bytesWritten):
            task.completedCount += 1
            recordAlbumBytes(bytesWritten, for: id, on: &task)
        case .imageFailed:
            task.failedCount += 1
        }
        if task.totalCount > 0 {
            task.progressFraction = min(
                max(Double(task.completedCount + task.failedCount) / Double(task.totalCount), 0),
                1
            )
        }
        task.progressText = task.totalCount > 0
            ? "已下载 \(task.completedCount) / \(task.totalCount) 张"
            : "正在解析图集"
        tasks[index] = task
    }

    private func apply(_ progress: SingleFileDownloadProgress, to id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].status == .running else { return }
        tasks[index].progressFraction = progress.fractionCompleted
        tasks[index].progressText = progress.statusText
        tasks[index].downloadedBytes = progress.downloadedBytes
        tasks[index].totalBytes = progress.totalBytes
        tasks[index].bytesPerSecond = progress.bytesPerSecond
        tasks[index].averageBytesPerSecond = progress.averageBytesPerSecond
    }

    private func finishAlbumTask(id: UUID, summary: AlbumDownloadSummary) {
        activeJob = nil
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            pumpQueue()
            return
        }
        var task = tasks[index]
        task.completedCount = summary.completedCount
        task.failedCount = summary.failedCount
        task.failedPageCount = summary.failedPageCount
        task.downloadedBytes = summary.downloadedBytes
        let processedCount = task.completedCount + task.failedCount
        // 正常终态以实际处理总数收口到 100%；取消任务保留运行时的
        // 总量估算，避免把部分下载误显示为 100%。
        task.totalCount = summary.cancelled
            ? max(task.totalCount, processedCount)
            : processedCount
        if task.totalCount > 0 {
            task.progressFraction = min(
                max(Double(processedCount) / Double(task.totalCount), 0),
                1
            )
        }
        task.finishedAt = Date()
        if let folderCreationError = summary.folderCreationError {
            task.errorMessage = folderCreationError
        }
        if summary.cancelled {
            // 已下载文件保留。
            task.status = .cancelled
        } else if summary.completedCount == 0 {
            task.status = .failed
        } else {
            task.status = .completed
        }
        if !summary.cancelled {
            task.totalBytes = summary.downloadedBytes
        }
        task.bytesPerSecond = 0
        updateAverageBytesPerSecond(on: &task, at: task.finishedAt ?? Date())
        task.progressText = task.status == .completed ? "图集下载完成" : task.progressText
        tasks[index] = task
        workSources[id] = nil
        resolvedImageTotals[id] = nil
        resolvedPageCounts[id] = nil
        albumTransferSamples[id] = nil
        releaseReservedDestination(for: task)
        pumpQueue()
    }

    private func finishFileTask(id: UUID, result: Result<Void, Error>) {
        activeJob = nil
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            pumpQueue()
            return
        }
        var task = tasks[index]
        task.finishedAt = Date()
        switch result {
        case .success:
            task.status = .completed
            task.progressFraction = 1
            task.progressText = "MP4 已保存"
            if let exactBytes = fileSize(at: task.destinationURL) {
                task.downloadedBytes = exactBytes
                task.totalBytes = exactBytes
            }
        case .failure(let error):
            if error is CancellationError {
                task.status = .cancelled
                task.progressText = "已取消"
            } else {
                task.status = .failed
                task.errorMessage = error.localizedDescription
                task.progressText = "下载失败"
            }
        }
        task.bytesPerSecond = 0
        updateAverageBytesPerSecondIfNeeded(on: &task, at: task.finishedAt ?? Date())
        tasks[index] = task
        workSources[id] = nil
        releaseReservedDestination(for: task)
        pumpQueue()
    }

    private func releaseReservedDestination(for task: DownloadTask) {
        switch task.kind {
        case .album:
            reservedFolderPaths.remove(task.destinationURL.path)
        case .video:
            reservedFileDestinationKeys.remove(fileDestinationReservationKey(for: task.destinationURL))
        }
    }

    private func fileDestinationReservationKey(for url: URL) -> String {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    private func recordAlbumBytes(
        _ byteCount: Int64,
        for id: UUID,
        on task: inout DownloadTask,
        at recordedAt: Date = Date()
    ) {
        let additionalBytes = max(byteCount, 0)
        guard additionalBytes > 0 else { return }
        let previous = albumTransferSamples[id] ?? AlbumTransferSample(
            downloadedBytes: task.downloadedBytes,
            recordedAt: task.startedAt ?? recordedAt,
            smoothedBytesPerSecond: task.bytesPerSecond
        )
        task.downloadedBytes += additionalBytes

        updateAverageBytesPerSecond(on: &task, at: recordedAt)
        updateAlbumTotalBytesEstimate(on: &task)

        // A page can finish several concurrent image writes in one MainActor
        // turn. Keep accumulating those bytes until a meaningful sampling
        // interval has elapsed instead of reporting a per-tick speed spike.
        let sampleDuration = recordedAt.timeIntervalSince(previous.recordedAt)
        guard sampleDuration >= 0.2 else {
            task.bytesPerSecond = previous.smoothedBytesPerSecond > 0
                ? previous.smoothedBytesPerSecond
                : task.averageBytesPerSecond
            return
        }
        let byteDelta = max(task.downloadedBytes - previous.downloadedBytes, 0)
        let instantaneousSpeed = Double(byteDelta) / sampleDuration
        let smoothedSpeed = previous.smoothedBytesPerSecond > 0
            ? previous.smoothedBytesPerSecond * 0.75 + instantaneousSpeed * 0.25
            : instantaneousSpeed
        task.bytesPerSecond = smoothedSpeed
        albumTransferSamples[id] = AlbumTransferSample(
            downloadedBytes: task.downloadedBytes,
            recordedAt: recordedAt,
            smoothedBytesPerSecond: smoothedSpeed
        )
    }

    private func updateAlbumTotalBytesEstimate(on task: inout DownloadTask) {
        guard task.completedCount > 0, task.totalCount > 0 else { return }
        let estimatedBytes = Double(task.downloadedBytes)
            / Double(task.completedCount)
            * Double(task.totalCount)
        guard estimatedBytes.isFinite else { return }
        task.totalBytes = max(
            task.downloadedBytes,
            Int64(min(estimatedBytes.rounded(), Double(Int64.max)))
        )
    }

    private func updateAverageBytesPerSecond(on task: inout DownloadTask, at date: Date) {
        guard task.downloadedBytes > 0, let startedAt = task.startedAt else { return }
        let elapsed = max(date.timeIntervalSince(startedAt), 0.2)
        task.averageBytesPerSecond = Double(task.downloadedBytes) / elapsed
    }

    private func updateAverageBytesPerSecondIfNeeded(on task: inout DownloadTask, at date: Date) {
        guard task.averageBytesPerSecond == 0 else { return }
        updateAverageBytesPerSecond(on: &task, at: date)
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(size)
    }

}
