import AppKit

@MainActor
final class WorkspaceSidebarOutlineView: NSOutlineView, WorkspaceLiveResizeScrollerHiding {
    var keyboardContextProvider: (() -> WorkspaceKeyboardContext)?

    override func viewWillStartLiveResize() {
        workspaceWillStartLiveResize()
        super.viewWillStartLiveResize()
    }

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        super.viewDidEndLiveResize()
    }

    override func keyDown(with event: NSEvent) {
        if let keyboardContextProvider,
           WorkspaceKeyboardHandler.keyDown(event, context: keyboardContextProvider()) {
            return
        }
        super.keyDown(with: event)
    }
}
