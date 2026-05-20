import AppKit

final class LocalImageGridCollectionView: NSCollectionView {
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var focusHandler: (() -> Void)?
    var arrowKeyHandler: ((Int) -> Bool)?
    var spaceKeyHandler: (() -> Bool)?
    var doubleClickHandler: ((IndexPath) -> Void)?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?

    private var pressedCardIndexPath: IndexPath?
    private var pressedCardTimestamp: TimeInterval = 0
    private var pendingPressReleaseWorkItem: DispatchWorkItem?
    private var hoverTrackingArea: NSTrackingArea?
    private var lastHoveredIndexPath: IndexPath?

    override var acceptsFirstResponder: Bool { true }

    override func accessibilityLabel() -> String? {
        "Local Image Grid"
    }

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

    override func mouseDown(with event: NSEvent) {
        focusHandler?()
        window?.makeFirstResponder(self)
        pendingPressReleaseWorkItem?.cancel()
        pendingPressReleaseWorkItem = nil

        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point) {
            pressedCardIndexPath = indexPath
            pressedCardTimestamp = ProcessInfo.processInfo.systemUptime
            cardPressStateHandler?(indexPath, true)
        }
        super.mouseDown(with: event)
        if event.clickCount == 2, let indexPath = indexPathForItem(at: point) {
            doubleClickHandler?(indexPath)
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard let indexPath = pressedCardIndexPath else { return }
        pendingPressReleaseWorkItem = LocalImageGridInteractionSupport.schedulePressRelease(
            pressedAt: pressedCardTimestamp
        ) { [weak self] in
            self?.cardPressStateHandler?(indexPath, false)
            self?.pressedCardIndexPath = nil
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hoveredIndexPath = indexPathForItem(at: point)
        if hoveredIndexPath != lastHoveredIndexPath {
            lastHoveredIndexPath = hoveredIndexPath
            syncVisibleHoverState(windowLocation: event.locationInWindow)
        }
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        lastHoveredIndexPath = nil
        clearVisibleHoverState()
        super.mouseExited(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        focusHandler?()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        return contextMenuProvider?(indexPathForItem(at: point))
    }

    override func keyDown(with event: NSEvent) {
        let handled = WorkspaceKeyboardHandler.keyDown(
            event,
            context: WorkspaceKeyboardContext(
                stepSelection: arrowKeyHandler,
                quickLook: spaceKeyHandler
            )
        )
        if handled {
            return
        }
        super.keyDown(with: event)
    }

    override func viewWillStartLiveResize() {
        workspaceWillStartLiveResize()
        super.viewWillStartLiveResize()
    }

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        syncVisibleHoverState(windowLocation: window?.mouseLocationOutsideOfEventStream)
        super.viewDidEndLiveResize()
    }

    func clearVisibleHoverState() {
        lastHoveredIndexPath = nil
        for item in visibleItems() {
            (item as? LocalImageGridItemView)?.clearHoverState()
        }
    }

    private func syncVisibleHoverState(windowLocation: NSPoint?) {
        for item in visibleItems() {
            (item as? LocalImageGridItemView)?.syncHoverState(windowLocation: windowLocation)
        }
    }
}

extension LocalImageGridCollectionView: WorkspaceLiveResizeScrollerHiding {}
