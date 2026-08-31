import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class OnlineVideoDetailInteractionController {
    var saveMessage = ""

    @ObservationIgnored private let downloadStore: DownloadStore
    @ObservationIgnored private let policySource: OnlineSourcePolicy.Source
    @ObservationIgnored private let sourceTitle: String
    @ObservationIgnored private let userAgent: String
    @ObservationIgnored private let referer: String

    init(
        downloadStore: DownloadStore,
        policySource: OnlineSourcePolicy.Source,
        sourceTitle: String,
        userAgent: String,
        referer: String
    ) {
        self.downloadStore = downloadStore
        self.policySource = policySource
        self.sourceTitle = sourceTitle
        self.userAgent = userAgent
        self.referer = referer
    }

    func saveVideo(item: OnlineVideoItem, sourceURL: URL) {
        guard OnlineSourcePolicy.allows(sourceURL, source: policySource, resource: .media) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = KnitVideoDownloadService.suggestedFilename(title: item.title, id: item.id)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let targetURL = panel.url else { return }

        let source = SingleFileDownloadSource(
            detailURL: item.detailURL,
            sourceURL: sourceURL,
            title: item.title,
            sourceTitle: sourceTitle,
            perform: { [policySource, userAgent, referer] targetURL, reportProgress in
                try await KnitVideoDownloadService.saveMP4(
                    from: sourceURL,
                    to: targetURL,
                    source: policySource,
                    userAgent: userAgent,
                    referer: referer
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
