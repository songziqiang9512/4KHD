import AppKit
import QuartzCore

enum LocalImageThumbnailLoadResult {
    case image(NSImage)
    case missingFile
    case unavailable
}

enum LocalImageGridAnimation {
    static let cardHoverScale = WorkspaceThumbnailGridCardAnimation.cardHoverScale
    static let cardPressedScale = WorkspaceThumbnailGridCardAnimation.cardPressedScale
    static let cardHoverExpandDuration = WorkspaceThumbnailGridCardAnimation.cardHoverExpandDuration
    static let cardHoverCollapseDuration = WorkspaceThumbnailGridCardAnimation.cardHoverCollapseDuration
    static let cardPressDownDuration = WorkspaceThumbnailGridCardAnimation.cardPressDownDuration
    static let cardPressUpDuration = WorkspaceThumbnailGridCardAnimation.cardPressUpDuration
    static let minimumPressVisualDuration: TimeInterval = 0.05
    static let cardEnterTiming = WorkspaceThumbnailGridCardAnimation.cardEnterTiming
    static let cardExitTiming = WorkspaceThumbnailGridCardAnimation.cardExitTiming
}

final class LocalImageAppearanceAwareView: NSView {
    var appearanceDidChangeHandler: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChangeHandler?()
    }
}

extension NSView {
    var localImageGridIsDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
    }

    func localImageGridEnsureLayerAnchorCentered() {
        guard let layer, !bounds.isEmpty else { return }
        guard abs(layer.anchorPoint.x - 0.5) > 0.0001
           || abs(layer.anchorPoint.y - 0.5) > 0.0001 else { return }
        let frame = layer.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = frame
        CATransaction.commit()
    }
}

enum LocalImageGridInteractionSupport {
    static func schedulePressRelease(
        pressedAt: TimeInterval,
        action: @escaping () -> Void
    ) -> DispatchWorkItem {
        let elapsed = ProcessInfo.processInfo.systemUptime - pressedAt
        let remaining = max(0, LocalImageGridAnimation.minimumPressVisualDuration - elapsed)
        let workItem = DispatchWorkItem(block: action)
        if remaining <= 0 {
            workItem.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
        }
        return workItem
    }
}
