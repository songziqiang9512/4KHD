import AppKit

@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
    private let appContext: WorkspaceAppContext
    private let shellController: WorkspaceSplitViewController
    private let windowAutosaveName = NSWindow.FrameAutosaveName("WorkspaceWindow")
    private let titleUpdateQueue = WorkspaceCoalescingQueue(
        name: "Workspace Window Title",
        interval: 0.05,
        maxInterval: 0.1
    )
    private var routeObserverID: UUID?

    init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
        shellController = WorkspaceSplitViewController(appContext: appContext)
        let window = NSWindow(contentViewController: shellController)
        window.title = "4KHD"
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.minSize = NSSize(width: 1080, height: 700)
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .automatic
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self
        window.setFrameUsingName(windowAutosaveName, force: true)
        // If the restored frame is completely off-screen (e.g., from a now-disconnected
        // external monitor), reposition it onto a visible screen.
        let restoredFrame = window.frame
        if !restoredFrame.isEmpty, !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(restoredFrame) }) {
            let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.screens.first
            if let screenFrame = targetScreen?.visibleFrame {
                window.setFrameOrigin(NSPoint(
                    x: screenFrame.midX - restoredFrame.width / 2,
                    y: screenFrame.midY - restoredFrame.height / 2
                ))
            }
        }
        let toolbarHost = WorkspaceToolbarHost(appContext: appContext, splitController: shellController)
        window.toolbar = toolbarHost
        routeObserverID = appContext.routeController.addObserver { [weak self] _ in
            self?.scheduleWindowTitleUpdate()
        }
        updateWindowTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let routeObserverID {
            Task { @MainActor [appContext] in
                appContext.routeController.removeObserver(id: routeObserverID)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        saveStateToUserDefaults()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        saveStateToUserDefaults()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        saveStateToUserDefaults()
    }

    func saveStateToUserDefaults() {
        shellController.saveStateToUserDefaults()
        window?.saveFrame(usingName: windowAutosaveName)
    }

    private func updateWindowTitle() {
        let route = appContext.routeController.route
        window?.title = title(for: route)
    }

    private func scheduleWindowTitleUpdate() {
        titleUpdateQueue.add(id: "title") { [weak self] in
            self?.updateWindowTitle()
        }
    }

    private func title(for route: WorkspaceRoute) -> String {
        switch route.moduleID {
        case .fourKHDGallery:
            guard let section = GallerySection(rawValue: route.itemID) else {
                return "4KHD"
            }
            return "\(section.title) - 4KHD"
        case .localLibrary:
            if appContext.localLibraryStore.isAllImagesFolderID(route.itemID) {
                return "我的图片 - 本地"
            }
            if let folder = appContext.localLibraryStore.findFolder(id: route.itemID) {
                return "\(folder.title) - 本地"
            }
            return "本地 - 4KHD"
        case .missKon:
            guard let section = MissKonSection(rawValue: route.itemID) else {
                return "MissKon"
            }
            return "\(section.title) - MissKon"
        case .wallhaven:
            guard let section = WallhavenSection(rawValue: route.itemID) else {
                return "Wallhaven"
            }
            return "\(section.title) - Wallhaven"
        }
    }
}
