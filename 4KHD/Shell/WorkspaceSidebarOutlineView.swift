import AppKit

@MainActor
final class WorkspaceSidebarOutlineView: NSOutlineView, WorkspaceLiveResizeScrollerHiding {
    var keyboardContextProvider: (() -> WorkspaceKeyboardContext)?
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func accessibilityLabel() -> String? {
        "Workspace Sidebar"
    }

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

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, delegate?.outlineView?(self, shouldSelectItem: item(atRow: row) as Any) != false {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return contextMenuProvider?(row)
    }
}
