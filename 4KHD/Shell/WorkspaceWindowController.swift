import AppKit

@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
    private let shellController: WorkspaceSplitViewController
    private let windowAutosaveName = NSWindow.FrameAutosaveName("WorkspaceWindow")

    init(appContext: WorkspaceAppContext) {
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
        let toolbar = WorkspaceToolbarHost(appContext: appContext, splitController: shellController)
        window.toolbar = toolbar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        saveStateToUserDefaults()
    }

    func saveStateToUserDefaults() {
        shellController.saveStateToUserDefaults()
        window?.saveFrame(usingName: windowAutosaveName)
    }
}
