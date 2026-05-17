import AppKit
import Nuke

@MainActor
final class GalleryZoomableImageView: NSView {
    var onImageDisplayed: (() -> Void)?

    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private let imageView = NSImageView()
    private let placeholderContainer = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "解析中")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private let openOriginalButton = NSButton(title: "打开原网页", target: nil, action: nil)
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
        fitImage(resetMagnification: false)
    }

    func setImageURL(_ url: URL?) {
        imageTask?.cancel()
        guard loadedURL != url else { return }
        loadedURL = url
        imageView.image = nil
        showPlaceholder(title: "解析中", showsActions: false)
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
                    self.showPlaceholder(title: "图片加载失败", showsActions: false)
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
        scrollView.minMagnification = 0.15
        scrollView.maxMagnification = 6
        scrollView.documentView = documentView

        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = NSColor.black.cgColor
        documentView.addSubview(imageView)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor

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
        let viewport = scrollView.contentView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        if resetMagnification {
            scrollView.magnification = 1
        }
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
}
