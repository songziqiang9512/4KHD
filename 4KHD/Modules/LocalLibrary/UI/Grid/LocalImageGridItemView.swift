import AppKit
import QuartzCore

final class LocalImageGridItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LocalImageGridItemView")

    private static var hoverTrackingActivated = false
    static func resetHoverTracking() { hoverTrackingActivated = false }

    private let imageContainer = LocalImageAppearanceAwareView()
    private let thumbnailView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "加载中...")
    private let hoverOutline = NSView()
    private let missingOverlay = NSView()
    private let missingIcon = NSImageView()

    private var representedID: String?
    private var imageTaskID: UUID?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressingCard = false
    private var isSelectedState = false
    private var currentScale: CGFloat = 1
    private var isHoverOutlineVisible = false

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        setupViews()
    }

    override func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        view.frame = layoutAttributes.frame
        layoutSubviewsManually()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSubviewsManually()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedID = nil
        imageTaskID = nil
        isHovering = false
        isPressingCard = false
        isSelectedState = false
        currentScale = 1
        thumbnailView.image = nil
        placeholderLabel.stringValue = "加载中..."
        placeholderLabel.isHidden = false
        missingOverlay.isHidden = true
        imageContainer.layer?.transform = CATransform3DIdentity
        hoverOutline.alphaValue = 0
        isHoverOutlineVisible = false
        refreshAppearance()
    }

    func configure(
        image: LocalImageItem,
        fileExists: Bool,
        isSelected: Bool,
        thumbnailLoader: @escaping (@escaping (LocalImageThumbnailLoadResult) -> Void) -> Void
    ) {
        representedID = image.id
        applySelectionState(isSelected)
        missingOverlay.isHidden = fileExists
        placeholderLabel.stringValue = fileExists ? "加载中..." : "原文件不存在"
        placeholderLabel.isHidden = !fileExists

        guard fileExists else {
            thumbnailView.image = nil
            return
        }

        let taskID = UUID()
        imageTaskID = taskID
        thumbnailLoader { [weak self] result in
            guard let self, self.imageTaskID == taskID, self.representedID == image.id else { return }
            switch result {
            case .image(let thumbnail):
                self.thumbnailView.image = thumbnail
                self.placeholderLabel.isHidden = true
                self.missingOverlay.isHidden = true
            case .missingFile:
                self.thumbnailView.image = nil
                self.placeholderLabel.stringValue = "原文件不存在"
                self.placeholderLabel.isHidden = false
                self.missingOverlay.isHidden = false
            case .unavailable:
                self.thumbnailView.image = nil
                self.placeholderLabel.stringValue = "缩略图不可用"
                self.placeholderLabel.isHidden = false
                self.missingOverlay.isHidden = true
            }
        }
    }

    func applySelectionState(_ isSelected: Bool) {
        isSelectedState = isSelected
        DispatchQueue.main.async { [weak self] in
            self?.refreshAppearance()
        }
    }

    func applyPressedState(_ isPressed: Bool) {
        guard isPressingCard != isPressed else { return }
        isPressingCard = isPressed
        guard isHovering else { return }
        applyCardScale(
            targetScale: isPressed ? LocalImageGridAnimation.cardPressedScale : LocalImageGridAnimation.cardHoverScale,
            duration: isPressed ? LocalImageGridAnimation.cardPressDownDuration : LocalImageGridAnimation.cardPressUpDuration,
            timing: isPressed ? LocalImageGridAnimation.cardEnterTiming : LocalImageGridAnimation.cardExitTiming
        )
    }

    override func mouseEntered(with event: NSEvent) {
        guard Self.hoverTrackingActivated else { return }
        isHovering = true
        applyHoverState(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard Self.hoverTrackingActivated else { return }
        isHovering = false
        applyHoverState(false)
    }

    override func mouseMoved(with event: NSEvent) {
        if !Self.hoverTrackingActivated {
            Self.hoverTrackingActivated = true
        }
        let point = imageContainer.convert(event.locationInWindow, from: nil)
        let hoveringNow = imageContainer.bounds.contains(point)
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        applyHoverState(hoveringNow)
    }

    private func layoutSubviewsManually() {
        let bounds = view.bounds
        imageContainer.frame = bounds
        imageContainer.localImageGridEnsureLayerAnchorCentered()
        thumbnailView.frame = imageContainer.bounds
        hoverOutline.frame = imageContainer.bounds.insetBy(dx: 1, dy: 1)
        missingOverlay.frame = imageContainer.bounds
        missingIcon.frame = NSRect(
            x: (bounds.width - 26) / 2,
            y: (bounds.height - 26) / 2,
            width: 26,
            height: 26
        )
        let labelSize = placeholderLabel.fittingSize
        placeholderLabel.frame = NSRect(
            x: (bounds.width - labelSize.width) / 2,
            y: (bounds.height - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        refreshAppearance()
    }

    private func applyHoverState(_ hovered: Bool) {
        applyHoverOutline(hovered)
        let targetScale: CGFloat
        if hovered {
            targetScale = isPressingCard ? LocalImageGridAnimation.cardPressedScale : LocalImageGridAnimation.cardHoverScale
        } else {
            targetScale = 1
        }
        applyCardScale(
            targetScale: targetScale,
            duration: hovered ? LocalImageGridAnimation.cardHoverExpandDuration : LocalImageGridAnimation.cardHoverCollapseDuration,
            timing: hovered ? LocalImageGridAnimation.cardEnterTiming : LocalImageGridAnimation.cardExitTiming
        )
    }

    private func applyCardScale(targetScale: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = imageContainer.layer else { return }
        imageContainer.localImageGridEnsureLayerAnchorCentered()
        guard abs(currentScale - targetScale) > 0.0001 else { return }
        let from = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? currentScale
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = targetScale
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "local.grid.card.scale")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
        currentScale = targetScale
    }

    private func applyHoverOutline(_ hovered: Bool) {
        let alpha: CGFloat = hovered ? 1 : 0
        guard isHoverOutlineVisible != hovered || abs(hoverOutline.alphaValue - alpha) > 0.0001 else { return }
        isHoverOutlineVisible = hovered
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hovered
                ? LocalImageGridAnimation.cardHoverExpandDuration
                : LocalImageGridAnimation.cardHoverCollapseDuration
            context.timingFunction = hovered
                ? LocalImageGridAnimation.cardEnterTiming
                : LocalImageGridAnimation.cardExitTiming
            hoverOutline.animator().alphaValue = alpha
        }
    }

    private func refreshAppearance() {
        imageContainer.layer?.borderColor = (isSelectedState ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        imageContainer.layer?.borderWidth = isSelectedState ? 2 : 1
        hoverOutline.layer?.borderColor = (view.localImageGridIsDarkAppearance ? NSColor.white : .controlAccentColor).cgColor
    }

    private func setupViews() {
        imageContainer.wantsLayer = true
        imageContainer.layer?.cornerRadius = 12
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageContainer.layer?.borderWidth = 1

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown

        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 11)

        hoverOutline.wantsLayer = true
        hoverOutline.layer?.cornerRadius = 11
        hoverOutline.layer?.borderWidth = 1
        hoverOutline.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutline.alphaValue = 0

        missingOverlay.wantsLayer = true
        missingOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        missingOverlay.isHidden = true

        missingIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        missingIcon.contentTintColor = NSColor.white.withAlphaComponent(0.86)

        view.addSubview(imageContainer)
        imageContainer.addSubview(thumbnailView)
        imageContainer.addSubview(missingOverlay)
        missingOverlay.addSubview(missingIcon)
        imageContainer.addSubview(hoverOutline)
        imageContainer.addSubview(placeholderLabel)

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        imageContainer.addTrackingArea(tracking)
        trackingArea = tracking

        imageContainer.appearanceDidChangeHandler = { [weak self] in
            self?.refreshAppearance()
        }
        refreshAppearance()
    }
}
