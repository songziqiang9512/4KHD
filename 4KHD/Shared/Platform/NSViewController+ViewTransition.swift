import AppKit

extension NSViewController {
    func animateViewTransition(to nextView: NSView, activeView: inout NSView?) {
        guard activeView !== nextView else { return }
        let previousView = activeView
        activeView = nextView
        nextView.translatesAutoresizingMaskIntoConstraints = false
        nextView.alphaValue = previousView != nil ? 0 : 1
        view.addSubview(nextView)
        NSLayoutConstraint.activate([
            nextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nextView.topAnchor.constraint(equalTo: view.topAnchor),
            nextView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        guard let previousView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            previousView.animator().alphaValue = 0
            nextView.animator().alphaValue = 1
        } completionHandler: {
            Task { @MainActor in
                previousView.removeFromSuperview()
            }
        }
    }
}
