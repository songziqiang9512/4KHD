import AppKit
import Foundation
import Observation

/// 图集批量下载管理器:持有任务列表、严格串行调度队列、取消与清理。
/// 任务不持久化,重启清空;已下载文件保留。
@MainActor
@Observable
final class DownloadStore {
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

    struct AlbumDownloadTask: Identifiable {
        let id: UUID
        let title: String
        let detailURL: URL
        let destinationFolderURL: URL
        var status: TaskStatus
        var completedCount: Int
        var totalCount: Int
        var failedCount: Int
        var failedPageCount: Int
        var errorMessage: String
        var startedAt: Date?
        var finishedAt: Date?
    }

    enum EnqueueAlbumResult: Equatable {
        case enqueued
        case duplicate
        case cancelled
    }

    var tasks: [AlbumDownloadTask] = []

    /// 测试注入点:替换引擎默认的图片拉取实现,生产环境保持 nil。
    @ObservationIgnored var imageFetcher: AlbumImageDataFetcher?

    @ObservationIgnored private var sources: [UUID: AlbumDownloadSource] = [:]
    @ObservationIgnored private var activeJob: Task<Void, Never>?
    @ObservationIgnored private let registry = ImageTaskRegistry()
    /// 会话内已分配的目标目录路径:同名图集并发下载时各得各的目录,
    /// 不会因为目录尚不存在/为空而复用同一目录互相覆盖。
    @ObservationIgnored private var reservedFolderPaths = Set<String>()

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
        let task = AlbumDownloadTask(
            id: UUID(),
            title: source.title,
            detailURL: source.detailURL,
            destinationFolderURL: destinationFolderURL,
            status: .queued,
            completedCount: 0,
            totalCount: source.estimatedImageCount,
            failedCount: 0,
            failedPageCount: 0,
            errorMessage: "",
            startedAt: nil,
            finishedAt: nil
        )
        sources[task.id] = source
        tasks.append(task)
        pumpQueue()
        return .enqueued
    }

    // MARK: - 取消 / 移除

    func cancelTask(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        switch tasks[index].status {
        case .queued:
            tasks[index].status = .cancelled
            tasks[index].finishedAt = Date()
            sources[id] = nil
            reservedFolderPaths.remove(tasks[index].destinationFolderURL.path)
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
            sources[tasks[index].id] = nil
            reservedFolderPaths.remove(tasks[index].destinationFolderURL.path)
        }
    }

    /// 仅终态任务可移除。
    func removeTask(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].status.isTerminal else { return }
        reservedFolderPaths.remove(tasks[index].destinationFolderURL.path)
        tasks.remove(at: index)
        sources[id] = nil
    }

    func clearFinishedTasks() {
        let finishedTasks = tasks.filter { $0.status.isTerminal }
        guard !finishedTasks.isEmpty else { return }
        finishedTasks.forEach { reservedFolderPaths.remove($0.destinationFolderURL.path) }
        let finishedIDs = finishedTasks.map(\.id)
        tasks.removeAll { $0.status.isTerminal }
        finishedIDs.forEach { sources[$0] = nil }
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
        guard let source = sources[tasks[index].id] else {
            tasks[index].status = .failed
            tasks[index].errorMessage = "下载源缺失"
            tasks[index].finishedAt = Date()
            return
        }

        let taskID = tasks[index].id
        tasks[index].status = .running
        tasks[index].startedAt = Date()
        let destinationFolder = tasks[index].destinationFolderURL

        let job = Task { [weak self] in
            guard let self else { return }
            let summary = await AlbumDownloadOrchestrator.run(
                source: source,
                destinationFolder: destinationFolder,
                maxConcurrentImages: 3,
                registry: registry,
                emit: { event in
                    Task { @MainActor [weak self] in
                        self?.apply(event, to: taskID)
                    }
                },
                fetcher: imageFetcher
            )
            self.finishTask(id: taskID, summary: summary)
        }
        activeJob = job
    }

    private func apply(_ event: AlbumDownloadEvent, to id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].status == .running else { return }
        var task = tasks[index]
        switch event {
        case .pageResolved:
            break
        case .pageFailed:
            task.failedPageCount += 1
        case .imageSucceeded:
            task.completedCount += 1
        case .imageFailed:
            task.failedCount += 1
        }
        tasks[index] = task
    }

    private func finishTask(id: UUID, summary: AlbumDownloadSummary) {
        activeJob = nil
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            pumpQueue()
            return
        }
        var task = tasks[index]
        task.completedCount = summary.completedCount
        task.failedCount = summary.failedCount
        task.failedPageCount = summary.failedPageCount
        task.finishedAt = Date()
        if let folderCreationError = summary.folderCreationError {
            task.errorMessage = folderCreationError
        }
        if summary.cancelled {
            // 已下载文件保留。
            task.status = .cancelled
        } else if summary.completedCount == 0 {
            task.status = .failed
            removeFolderIfEmpty(task.destinationFolderURL)
        } else {
            task.status = .completed
        }
        tasks[index] = task
        sources[id] = nil
        reservedFolderPaths.remove(task.destinationFolderURL.path)
        pumpQueue()
    }

    private func removeFolderIfEmpty(_ url: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ),
            contents.isEmpty else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
