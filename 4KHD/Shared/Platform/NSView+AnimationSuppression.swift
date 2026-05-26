import AppKit

extension NSView {
    /// Perform a batch of view updates with all implicit animations suppressed.
    /// Useful for collection view / table view reloads where flickering is undesirable.
    static func performWithoutAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            updates()
        }
        CATransaction.commit()
    }
}
