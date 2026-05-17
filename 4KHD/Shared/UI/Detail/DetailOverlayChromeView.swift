import AppKit

@MainActor
final class DetailOverlayChromeView: NSVisualEffectView {
    init(cornerRadius: CGFloat = 16) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
