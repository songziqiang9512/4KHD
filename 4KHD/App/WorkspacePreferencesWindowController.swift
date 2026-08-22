import AppKit

@MainActor
final class WorkspacePreferencesWindowController: NSWindowController {
    private let preferencesViewController: WorkspacePreferencesViewController

    init(appContext: WorkspaceAppContext) {
        let preferencesViewController = WorkspacePreferencesViewController(
            toolbarContext: appContext.toolbarContext,
            favoritesStore: appContext.favoritesStore,
            clearCaches: {
                var failures: [String] = []
                await RemoteImagePipeline.shared.clearAllCaches()
                do {
                    try await DetailPageImageCache.shared.clear()
                    try await MissKonDetailMetadataCache.shared.clear()
                } catch {
                    failures.append("详情页")
                }
                do {
                    try await LocalImageCache.shared.clear()
                } catch {
                    failures.append("本地缩略图")
                }
                do {
                    try await appContext.missKonStore.feed.clearCache()
                } catch {
                    failures.append("MissKon")
                }
                do {
                    try await appContext.wallhavenStore.feed.clearCache()
                } catch {
                    failures.append("Wallhaven")
                }

                let tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("4KHD-Wallpaper", isDirectory: true)
                do {
                    try await Task.detached(priority: .utility) {
                        guard FileManager.default.fileExists(atPath: tempDirectory.path) else { return }
                        try FileManager.default.removeItem(at: tempDirectory)
                    }.value
                } catch {
                    failures.append("临时文件")
                }
                return failures
            },
            // 统一收藏模块直接观察 FavoritesStore,导入后列表自动重建。
            onFavoritesImported: {}
        )
        self.preferencesViewController = preferencesViewController

        let window = NSWindow(contentViewController: preferencesViewController)
        window.title = "设置"
        window.styleMask = [.titled, .closable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setContentSize(WorkspacePreferencesViewController.contentSize)
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func refresh() {
        preferencesViewController.refresh()
    }
}
