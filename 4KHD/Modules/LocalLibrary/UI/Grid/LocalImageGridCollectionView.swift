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
        let noModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        if noModifiers {
            switch event.keyCode {
            case 123, 126:
                if arrowKeyHandler?(-1) == true { return }
            case 124, 125:
                if arrowKeyHandler?(1) == true { return }
            case 49:
                if spaceKeyHandler?() == true { return }
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}
