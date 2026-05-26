import AppKit
import Nuke

@MainActor
final class GalleryZoomableImageView: WorkspaceZoomableImageView {
    var onImageDisplayed: (() -> Void)?

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
        setupGalleryOverlay()
    }

    func setImageURL(_ url: URL?, preservesCurrentImageUntilLoaded: Bool = false) {
        imageTask?.cancel()
        guard loadedURL != url else { return }
        loadedURL = url
        let shouldKeepCurrent = preservesCurrentImageUntilLoaded && imageView.image != nil
        if !shouldKeepCurrent {
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
                    if !shouldKeepCurrent || self.imageView.image == nil {
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

    private func setupGalleryOverlay() {
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

    @objc private func retry() {
        retryAction?()
    }

    @objc private func openOriginal() {
        openOriginalAction?()
    }
}
