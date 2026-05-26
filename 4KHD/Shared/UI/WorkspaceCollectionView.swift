import AppKit

class WorkspaceCollectionView: NSCollectionView {
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var focusHandler: (() -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    var lastHoveredIndexPath: IndexPath?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        hoverTrackingArea = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hoveredIndexPath = indexPathForItem(at: point)
        if hoveredIndexPath != lastHoveredIndexPath {
            lastHoveredIndexPath = hoveredIndexPath
            syncHoverOnVisibleItems(windowLocation: event.locationInWindow)
        }
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        clearHoverOnVisibleItems()
        super.mouseExited(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        focusHandler?()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        return contextMenuProvider?(indexPathForItem(at: point))
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

    func clearHoverOnVisibleItems() {
        lastHoveredIndexPath = nil
    }

    func syncHoverOnVisibleItems(windowLocation: NSPoint?) {}
}

extension WorkspaceCollectionView: WorkspaceLiveResizeScrollerHiding {}
