import AppKit
import Nuke
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class KnitDetailInteractionController {
    var resetToken = UUID()
    var saveMessage = ""

    @ObservationIgnored private let downloadStore: DownloadStore
    @ObservationIgnored private var saveTask: ImageTask?

    init(downloadStore: DownloadStore) {
        self.downloadStore = downloadStore
    }

    deinit {
        saveTask?.cancel()
    }

    func resetZoom() {
        resetToken = UUID()
    }

    func save(item: KnitGalleryItem, slot: KnitImageSlot) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.image]
        let extensionValue = slot.knownURL.pathExtension.isEmpty ? "jpg" : slot.knownURL.pathExtension
        panel.nameFieldStringValue = "\(item.id)-\(slot.displayIndex).\(extensionValue)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }

        saveMessage = "保存中"
        saveTask?.cancel()
        let request = RemoteImagePipeline.shared.request(
            for: slot.knownURL,
            priority: .veryHigh,
            configureURLRequest: KnitRequestFactory.configureImageRequest
        )
        saveTask = RemoteImagePipeline.shared.loadData(with: request) { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let data else {
                    saveMessage = "保存失败"
                    return
                }
                do {
                    try data.write(to: target, options: .atomic)
                    saveMessage = "已保存"
                } catch {
                    saveMessage = "保存失败"
                }
            }
        }
    }

    func saveVideo(item: KnitGalleryItem, sourceURL: URL) {
        guard OnlineSourcePolicy.allows(sourceURL, source: .knit, resource: .media) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = KnitVideoDownloadService.suggestedFilename(for: item)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let targetURL = panel.url else { return }

        let source = SingleFileDownloadSource(
            detailURL: item.detailURL,
            sourceURL: sourceURL,
            title: item.title,
            sourceTitle: "爱妹子",
            perform: { targetURL, reportProgress in
                try await KnitVideoDownloadService.saveMP4(
                    from: sourceURL,
                    to: targetURL
                ) { progress in
                    reportProgress(
                        SingleFileDownloadProgress(
                            fractionCompleted: progress.fractionCompleted,
                            statusText: progress.statusText,
                            downloadedBytes: progress.downloadedBytes,
                            totalBytes: progress.totalBytes,
                            bytesPerSecond: progress.bytesPerSecond,
                            averageBytesPerSecond: progress.averageBytesPerSecond
                        )
                    )
                }
            }
        )
        switch downloadStore.enqueueFile(source: source, destinationURL: targetURL) {
        case .enqueued:
            WorkspaceDownloadsPresenter.show()
        case .duplicate:
            let alert = makeAppAlert(
                title: "该视频已在下载队列中",
                message: "同一视频正在排队或下载中。",
                style: .informational
            )
            presentAppAlert(alert, in: appModalHostWindow())
        case .destinationInUse:
            let alert = makeAppAlert(
                title: "保存位置正在使用",
                message: "另一个视频任务正在写入这个文件，请选择其他名称或等待该任务结束。",
                style: .warning
            )
            presentAppAlert(alert, in: appModalHostWindow())
        }
    }
}
