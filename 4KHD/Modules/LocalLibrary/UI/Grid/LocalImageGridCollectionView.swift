import AppKit

final class LocalImageGridCollectionView: WorkspaceCollectionView {
    var arrowKeyHandler: ((Int) -> Bool)?
    var spaceKeyHandler: (() -> Bool)?
    var doubleClickHandler: ((IndexPath) -> Void)?

    override func accessibilityLabel() -> String? {
        "本地图片网格"
    }

    override func mouseDown(with event: NSEvent) {
        focusHandler?()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
        if event.clickCount == 2, let indexPath = indexPathForItem(at: point) {
            doubleClickHandler?(indexPath)
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
