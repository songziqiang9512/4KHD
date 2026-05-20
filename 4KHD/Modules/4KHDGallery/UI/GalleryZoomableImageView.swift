import AppKit
import Nuke

@MainActor
final class GalleryZoomableImageView: NSView {
    var onImageDisplayed: (() -> Void)?

    private let scrollView = GalleryZoomScrollView()
    private let documentView = NSView()
    private let imageView = NSImageView()
    private let placeholderContainer = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "解析中")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private let openOriginalButton = NSButton(title: "打开原网页", target: nil, action: nil)
    private let minimumRubberBandMagnification: CGFloat = 0.8
    private var imageTask: ImageTask?
    private var loadedURL: URL?
    private var retryAction: (() -> Void)?
    private var openOriginalAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        imageTask?.cancel()
    }

    override func layout() {
        super.layout()
        if abs(scrollView.magnification - 1) < 0.001 {
            fitImage(resetMagnification: false)
        }
    }

    func setImageURL(_ url: URL?, preservesCurrentImageUntilLoaded: Bool = false) {
        imageTask?.cancel()
        guard loadedURL != url else { return }
        loadedURL = url
        let shouldKeepCurrentImage = preservesCurrentImageUntilLoaded && imageView.image != nil
        if !shouldKeepCurrentImage {
            imageView.image = nil
            showPlaceholder(title: "解析中", showsActions: false)
        }
        guard let url else { return }

        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .veryHigh,
            configureURLRequest: GalleryRequestFactory.configureImageRequest
        )
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.loadedURL == url else { return }
                guard let image else {
                    if !shouldKeepCurrentImage {
                        self.showPlaceholder(title: "图片加载失败", showsActions: false)
                    }
                    return
                }
                self.placeholderContainer.isHidden = true
                self.imageView.image = image
                self.fitImage(resetMagnification: true)
                self.onImageDisplayed?()
            }
        }
    }

    func showFailure(retry: @escaping () -> Void, openOriginal: @escaping () -> Void) {
        retryAction = retry
        openOriginalAction = openOriginal
        imageTask?.cancel()
        imageView.image = nil
        showPlaceholder(title: "解析失败", showsActions: true)
    }

    func resetZoom() {
        fitImage(resetMagnification: true)
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = minimumRubberBandMagnification
        scrollView.maxMagnification = 6
        scrollView.contentView = GalleryCenteringClipView()
        scrollView.documentView = documentView
        scrollView.onMagnifyEndedBelowBaseline = { [weak self] in
            self?.restoreBaselineAfterRubberBand()
        }

        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = NSColor.clear.cgColor
        documentView.addSubview(imageView)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        placeholderLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        placeholderLabel.textColor = .secondaryLabelColor
        retryButton.target = self
        retryButton.action = #selector(retry)
        retryButton.bezelStyle = .rounded
        openOriginalButton.target = self
        openOriginalButton.action = #selector(openOriginal)
        openOriginalButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [retryButton, openOriginalButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        let stack = NSStackView(views: [placeholderLabel, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10

        placeholderContainer.addSubview(stack)
        addSubview(placeholderContainer)
        placeholderContainer.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderContainer.topAnchor.constraint(equalTo: topAnchor),
            placeholderContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: placeholderContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: placeholderContainer.centerYAnchor)
        ])
        showPlaceholder(title: "解析中", showsActions: false)
    }

    private func showPlaceholder(title: String, showsActions: Bool) {
        placeholderLabel.stringValue = title
        placeholderContainer.isHidden = false
        retryButton.isHidden = !showsActions
        openOriginalButton.isHidden = !showsActions
    }

    private func fitImage(resetMagnification: Bool) {
        guard let image = imageView.image else { return }
        if resetMagnification {
            scrollView.magnification = 1
            scrollView.layoutSubtreeIfNeeded()
        }
        let viewport = scrollView.contentView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let fittedSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        documentView.frame = NSRect(origin: .zero, size: viewport)
        imageView.frame = NSRect(
            x: max((viewport.width - fittedSize.width) / 2, 0),
            y: max((viewport.height - fittedSize.height) / 2, 0),
            width: fittedSize.width,
            height: fittedSize.height
        )
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func retry() {
        retryAction?()
    }

    @objc private func openOriginal() {
        openOriginalAction?()
    }

    private func restoreBaselineAfterRubberBand() {
        guard scrollView.magnification < 1 else { return }
        let visibleRect = scrollView.contentView.bounds
        let center = NSPoint(x: visibleRect.midX, y: visibleRect.midY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scrollView.animator().setMagnification(1, centeredAt: center)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.scrollView.contentView.scroll(to: .zero)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }
}

private final class GalleryCenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return constrained }

        let documentFrame = documentView.frame
        if documentFrame.width < proposedBounds.width {
            constrained.origin.x = floor((documentFrame.width - proposedBounds.width) / 2)
        }
        if documentFrame.height < proposedBounds.height {
            constrained.origin.y = floor((documentFrame.height - proposedBounds.height) / 2)
        }
        return constrained
    }
}

private final class GalleryZoomScrollView: NSScrollView {
    var onMagnifyEndedBelowBaseline: (() -> Void)?

    override func viewWillStartLiveResize() {
        hasHorizontalScroller = false
        hasVerticalScroller = false
        super.viewWillStartLiveResize()
    }

    override func viewDidEndLiveResize() {
        hasHorizontalScroller = true
        hasVerticalScroller = true
        super.viewDidEndLiveResize()
    }

    override func magnify(with event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if magnification < 1 {
                onMagnifyEndedBelowBaseline?()
                return
            }
        }

        let proposedMagnification = min(max(magnification + event.magnification, minMagnification), maxMagnification)
        guard event.magnification < 0, proposedMagnification < 1.0001 else {
            super.magnify(with: event)
            return
        }

        let visibleRect = contentView.bounds
        let center = NSPoint(x: visibleRect.midX, y: visibleRect.midY)
        setMagnification(proposedMagnification, centeredAt: center)
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            onMagnifyEndedBelowBaseline?()
        }
    }
}
