import AppKit

final class LocalImageGridCollectionView: WorkspaceCollectionView {
    var arrowKeyHandler: ((Int) -> Bool)?
    var spaceKeyHandler: (() -> Bool)?
    var doubleClickHandler: ((IndexPath) -> Void)?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?

    private var pressedCardIndexPath: IndexPath?
    private var pressedCardTimestamp: TimeInterval = 0
    private var pendingPressReleaseWorkItem: DispatchWorkItem?

    override func accessibilityLabel() -> String? {
        "Local Image Grid"
    }

    override func mouseDown(with event: NSEvent) {
        focusHandler?()
        window?.makeFirstResponder(self)
        // 被取消的延迟释放不会执行，先复位上一张卡片的按压状态，避免其永久停在缩放态。
        if let previousIndexPath = pressedCardIndexPath {
            cardPressStateHandler?(previousIndexPath, false)
            pressedCardIndexPath = nil
        }
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

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        syncHoverOnVisibleItems(windowLocation: window?.mouseLocationOutsideOfEventStream)
        super.viewDidEndLiveResize()
    }

    override func clearHoverOnVisibleItems() {
        lastHoveredIndexPath = nil
        for item in visibleItems() {
            (item as? LocalImageGridItemView)?.clearHoverState()
        }
    }

    override func syncHoverOnVisibleItems(windowLocation: NSPoint?) {
        for item in visibleItems() {
            (item as? LocalImageGridItemView)?.syncHoverState(windowLocation: windowLocation)
        }
    }
}
