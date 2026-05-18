import AppKit

final class LocalImageGridCollectionView: NSCollectionView {
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var focusHandler: (() -> Void)?
    var arrowKeyHandler: ((Int) -> Bool)?
    var spaceKeyHandler: (() -> Bool)?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?

    private var pressedCardIndexPath: IndexPath?
    private var pressedCardTimestamp: TimeInterval = 0
    private var pendingPressReleaseWorkItem: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }

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
        super.viewDidEndLiveResize()
    }
}

extension LocalImageGridCollectionView: WorkspaceLiveResizeScrollerHiding {}
