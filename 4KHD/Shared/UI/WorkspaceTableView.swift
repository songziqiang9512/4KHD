import AppKit

class WorkspaceTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override var acceptsFirstResponder: Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        return contextMenuProvider?(row)
    }

    override func keyDown(with event: NSEvent) {
        if let context = keyboardContext {
            let handled = WorkspaceKeyboardHandler.keyDown(event, context: context)
            if handled { return }
        }
        super.keyDown(with: event)
    }

    override func viewWillStartLiveResize() {
        workspaceWillStartLiveResize()
        super.viewWillStartLiveResize()
    }

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        super.viewDidEndLiveResize()
    }

    var keyboardContext: WorkspaceKeyboardContext?
}

extension WorkspaceTableView: WorkspaceLiveResizeScrollerHiding {}
