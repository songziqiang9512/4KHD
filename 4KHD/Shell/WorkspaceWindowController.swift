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
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .shadow
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self
        window.setFrameUsingName(windowAutosaveName, force: true)
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
            if let folder = appContext.localLibraryStore.findFolder(id: route.itemID) {
                return "\(folder.title) - 本地"
            }
            return "本地 - 4KHD"
        }
    }
}
