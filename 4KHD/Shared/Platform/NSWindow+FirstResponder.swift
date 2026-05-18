import AppKit

extension NSWindow {
    func makeFirstResponderUnlessDescendantIsFirstResponder(_ view: NSView) {
        if let firstResponder = firstResponder as? NSView,
           (firstResponder === view || firstResponder.isDescendant(of: view)) {
            return
        }
        makeFirstResponder(view)
    }
}
