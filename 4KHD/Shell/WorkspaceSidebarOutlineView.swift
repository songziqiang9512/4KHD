import AppKit

@MainActor
final class WorkspaceSidebarOutlineView: NSOutlineView, WorkspaceLiveResizeScrollerHiding {
    var keyboardContextProvider: (() -> WorkspaceKeyboardContext)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var draggingUpdatedHandler: ((NSPoint) -> NSDragOperation)?
    var draggingSessionEndedHandler: ((NSDragOperation) -> Void)?

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

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = draggingUpdatedHandler?(sender.draggingLocation) ?? []
        return operation == [] ? super.draggingUpdated(sender) : operation
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        super.draggingSession(session, endedAt: screenPoint, operation: operation)
        draggingSessionEndedHandler?(operation)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, delegate?.outlineView?(self, shouldSelectItem: item(atRow: row) as Any) != false {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return contextMenuProvider?(row)
    }
}

final class WorkspaceSidebarRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}
