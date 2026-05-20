import AppKit
import QuartzCore

enum WorkspaceThumbnailGridCardAnimation {
    static let cardHoverScale: CGFloat = 1.05
    static let cardPressedScale: CGFloat = 0.96
    static let cardHoverExpandDuration: CFTimeInterval = 0.30
    static let cardHoverCollapseDuration: CFTimeInterval = 0.34
    static let cardPressDownDuration: CFTimeInterval = 0.08
    static let cardPressUpDuration: CFTimeInterval = 0.12
    static let cardEnterTiming = CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.26, 1.0)
    static let cardExitTiming = CAMediaTimingFunction(controlPoints: 0.26, 0.64, 0.30, 1.0)
}

final class WorkspaceThumbnailGridCardView: NSView {
    private let imageView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "加载中...")
    private let hoverOutline = NSView()
    private let infoOverlay = NSView()
    private let gradientLayer = CAGradientLayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let missingOverlay = NSView()
    private let missingIcon = NSImageView()
    private let placeholderImage = NSImage(size: NSSize(width: 1, height: 1))

    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false
    private var isPressingCard = false
    private var isSelectedState = false
    private var currentScale: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard bounds.isUsableForManualLayout else { return }
        ensureLayerAnchorCentered()
        let fontSizes = fontSizeForWidth(bounds.width)
        titleLabel.font = .systemFont(ofSize: fontSizes.title, weight: .medium)
        metadataLabel.font = .monospacedDigitSystemFont(ofSize: fontSizes.metadata, weight: .regular)
        imageView.frame = bounds
        hoverOutline.frame = bounds.insetBy(dx: 1, dy: 1)
        missingOverlay.frame = bounds
        missingIcon.frame = NSRect(
            x: floor((bounds.width - 26) / 2),
            y: floor((bounds.height - 26) / 2),
            width: 26,
            height: 26
        )

        infoOverlay.frame = bounds
        gradientLayer.frame = infoOverlay.bounds

        let pad: CGFloat = 8
        if metadataLabel.isHidden {
            metadataLabel.frame = .zero
        } else {
            metadataLabel.sizeToFit()
            metadataLabel.frame = NSRect(
                x: pad,
                y: pad + 2,
                width: bounds.width - pad * 2,
                height: metadataLabel.fittingSize.height
            )
        }
        titleLabel.sizeToFit()
        titleLabel.frame = NSRect(
            x: pad,
            y: metadataLabel.isHidden ? pad + 2 : metadataLabel.frame.maxY + 2,
            width: bounds.width - pad * 2,
            height: titleLabel.fittingSize.height
        )

        let placeholderSize = placeholderLabel.fittingSize
        placeholderLabel.frame = NSRect(
            x: floor((bounds.width - placeholderSize.width) / 2),
            y: floor((bounds.height - placeholderSize.height) / 2),
            width: placeholderSize.width,
            height: placeholderSize.height
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHovering(bounds.contains(point))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            setHovering(false)
        }
    }

    func resetForReuse() {
        removeTransientAnimations()
        isHovering = false
        isPressingCard = false
        isSelectedState = false
        currentScale = 1
        imageView.image = placeholderImage
        placeholderLabel.stringValue = "加载中..."
        placeholderLabel.isHidden = false
        titleLabel.stringValue = ""
        metadataLabel.stringValue = ""
        metadataLabel.isHidden = false
        missingOverlay.isHidden = true
        infoOverlay.alphaValue = 0
        hoverOutline.alphaValue = 0
        layer?.transform = CATransform3DIdentity
        refreshAppearance()
    }

    func setImage(_ image: NSImage?) {
        imageView.image = image ?? placeholderImage
        placeholderLabel.isHidden = image != nil
    }

    func setPlaceholder(_ text: String, isVisible: Bool) {
        placeholderLabel.stringValue = text
        placeholderLabel.isHidden = !isVisible
        needsLayout = true
    }

    func setText(title: String, metadata: String) {
        titleLabel.stringValue = title
        metadataLabel.stringValue = metadata
        metadataLabel.isHidden = metadata.isEmpty
        needsLayout = true
    }

    func setMissingVisible(_ isVisible: Bool) {
        missingOverlay.isHidden = !isVisible
    }

    func applySelectionState(_ isSelected: Bool) {
        isSelectedState = isSelected
        refreshAppearance()
    }

    func applyPressedState(_ isPressed: Bool) {
        guard isPressingCard != isPressed else { return }
        isPressingCard = isPressed
        guard isHovering else { return }
        applyCardScale(
            targetScale: isPressed
                ? WorkspaceThumbnailGridCardAnimation.cardPressedScale
                : WorkspaceThumbnailGridCardAnimation.cardHoverScale,
            duration: isPressed
                ? WorkspaceThumbnailGridCardAnimation.cardPressDownDuration
                : WorkspaceThumbnailGridCardAnimation.cardPressUpDuration,
            timing: isPressed
                ? WorkspaceThumbnailGridCardAnimation.cardEnterTiming
                : WorkspaceThumbnailGridCardAnimation.cardExitTiming
        )
    }

    func syncHoverState(windowLocation: NSPoint?) {
        guard let windowLocation, window != nil, !isHidden else {
            setHovering(false)
            return
        }
        let point = convert(windowLocation, from: nil)
        setHovering(bounds.contains(point))
    }

    func clearHoverState() {
        setHovering(false)
    }

    func prepareForImmediateDisplay() {
        removeTransientAnimations()
        isHovering = false
        isPressingCard = false
        currentScale = 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.transform = CATransform3DIdentity
        hoverOutline.alphaValue = 0
        infoOverlay.alphaValue = 0
        CATransaction.commit()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        imageView.imageScaling = .scaleAxesIndependently

        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 11)

        hoverOutline.wantsLayer = true
        hoverOutline.layer?.cornerRadius = 11
        hoverOutline.layer?.borderWidth = 1
        hoverOutline.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutline.alphaValue = 0

        infoOverlay.wantsLayer = true
        infoOverlay.layer?.backgroundColor = NSColor.clear.cgColor
        infoOverlay.layer?.addSublayer(gradientLayer)
        infoOverlay.alphaValue = 0
        gradientLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.05).cgColor,
            NSColor.black.withAlphaComponent(0.72).cgColor
        ]
        gradientLayer.locations = [0.0, 0.62, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.actions = ["bounds": NSNull(), "position": NSNull()]
        gradientLayer.needsDisplayOnBoundsChange = true
        gradientLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.alignment = .center

        metadataLabel.textColor = NSColor.white.withAlphaComponent(0.80)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.alignment = .center

        missingOverlay.wantsLayer = true
        missingOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        missingOverlay.isHidden = true

        missingIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        missingIcon.contentTintColor = NSColor.white.withAlphaComponent(0.86)

        addSubview(imageView)
        addSubview(infoOverlay)
        infoOverlay.addSubview(titleLabel)
        infoOverlay.addSubview(metadataLabel)
        addSubview(missingOverlay)
        missingOverlay.addSubview(missingIcon)
        addSubview(hoverOutline)
        addSubview(placeholderLabel)
        refreshAppearance()
    }

    private func removeTransientAnimations() {
        layer?.removeAnimation(forKey: "workspace.grid.card.scale")
        layer?.removeAllAnimations()
        imageView.layer?.removeAllAnimations()
        hoverOutline.layer?.removeAllAnimations()
        infoOverlay.layer?.removeAllAnimations()
        gradientLayer.removeAllAnimations()
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        let targetScale: CGFloat = hovering
            ? (isPressingCard
                ? WorkspaceThumbnailGridCardAnimation.cardPressedScale
                : WorkspaceThumbnailGridCardAnimation.cardHoverScale)
            : 1
        applyCardScale(
            targetScale: targetScale,
            duration: hovering
                ? WorkspaceThumbnailGridCardAnimation.cardHoverExpandDuration
                : WorkspaceThumbnailGridCardAnimation.cardHoverCollapseDuration,
            timing: hovering
                ? WorkspaceThumbnailGridCardAnimation.cardEnterTiming
                : WorkspaceThumbnailGridCardAnimation.cardExitTiming
        )
        animateHoverChrome(hovering)
    }

    private func fontSizeForWidth(_ width: CGFloat) -> (title: CGFloat, metadata: CGFloat) {
        switch width {
        case ..<160:
            return (9, 8)
        case 160..<260:
            return (11, 10)
        default:
            return (13, 11)
        }
    }

    private func animateHoverChrome(_ hovering: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hovering
                ? WorkspaceThumbnailGridCardAnimation.cardHoverExpandDuration
                : WorkspaceThumbnailGridCardAnimation.cardHoverCollapseDuration
            context.timingFunction = hovering
                ? WorkspaceThumbnailGridCardAnimation.cardEnterTiming
                : WorkspaceThumbnailGridCardAnimation.cardExitTiming
            hoverOutline.animator().alphaValue = hovering ? 1 : 0
            infoOverlay.animator().alphaValue = hovering ? 1 : 0
        }
    }

    private func applyCardScale(targetScale: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer else { return }
        ensureLayerAnchorCentered()
        guard abs(currentScale - targetScale) > 0.0001 else { return }
        let from = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? currentScale
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = targetScale
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "workspace.grid.card.scale")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
        currentScale = targetScale
    }

    private func ensureLayerAnchorCentered() {
        guard let layer, bounds.isUsableForManualLayout else { return }
        let preservedFrame = layer.frame
        guard preservedFrame.isUsableForManualLayout else { return }
        guard abs(layer.anchorPoint.x - 0.5) > 0.0001
           || abs(layer.anchorPoint.y - 0.5) > 0.0001 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = preservedFrame
        CATransaction.commit()
    }

    private func refreshAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
        layer?.backgroundColor = (isDark ? NSColor.controlBackgroundColor : NSColor.windowBackgroundColor).cgColor
        layer?.borderColor = isSelectedState
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.withAlphaComponent(isDark ? 0.55 : 0.42).cgColor
        layer?.borderWidth = isSelectedState ? 2 : 1
        let hoverColor = isDark
            ? NSColor.white.withAlphaComponent(0.88)
            : NSColor.systemBlue.withAlphaComponent(0.86)
        hoverOutline.layer?.borderColor = hoverColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

}

private extension NSRect {
    var isUsableForManualLayout: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
            && size.width < 100_000
            && size.height < 100_000
    }
}
