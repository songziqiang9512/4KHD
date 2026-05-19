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

@MainActor
final class DetailNavigationButton: NSButton {
    init(symbolName: String, accessibilityDescription: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        imagePosition = .imageOnly
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        bezelStyle = .circular
        isBordered = true
        alphaValue = 0.82
        toolTip = accessibilityDescription
        setButtonType(.momentaryPushIn)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
