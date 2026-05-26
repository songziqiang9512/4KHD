import AppKit

/// A detail-area root view that forwards keyDown events to a handler closure.
/// Used by detail view controllers to ensure keyboard events are captured
/// even in immersive/presented modes.
final class WorkspaceDetailRootView: NSView {
    var keyHandler: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}
