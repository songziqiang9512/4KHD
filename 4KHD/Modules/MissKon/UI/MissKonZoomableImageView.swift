import AppKit
import Nuke

@MainActor
final class MissKonZoomableImageView: WorkspaceZoomableImageView {
    var onImageDisplayed: (() -> Void)?

    private let placeholderContainer = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "解析中")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private var retryAction: (() -> Void)?
    private var imageTask: ImageTask?
    private var loadedURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupPlaceholder()
    }

    func setImageURL(_ url: URL?, preservesCurrentImageUntilLoaded: Bool = false) {
        imageTask?.cancel()
        guard loadedURL != url else { return }
        loadedURL = url
        let shouldKeepCurrent = preservesCurrentImageUntilLoaded && imageView.image != nil
        if !shouldKeepCurrent {
            imageView.image = nil
            placeholderLabel.stringValue = "加载中"
            retryButton.isHidden = true
            placeholderContainer.isHidden = false
        }
        guard let url else { return }

        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .veryHigh,
            maxPixelSize: 4096,
            configureURLRequest: MissKonRequestFactory.configureImageRequest
        )
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.loadedURL == url else { return }
                guard let image else {
                    if !shouldKeepCurrent || self.imageView.image == nil {
                        self.placeholderLabel.stringValue = "图片加载失败"
                        self.retryButton.isHidden = true
                        self.placeholderContainer.isHidden = false
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

    func showFailure(retry: @escaping () -> Void) {
        retryAction = retry
        imageTask?.cancel()
        imageView.image = nil
        placeholderLabel.stringValue = "解析失败"
        retryButton.isHidden = false
        placeholderContainer.isHidden = false
    }

    @objc private func retry() {
        placeholderLabel.stringValue = "重试中"
        retryButton.isHidden = true
        retryAction?()
    }

    private func setupPlaceholder() {
        placeholderLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center

        retryButton.bezelStyle = .rounded
        retryButton.font = .systemFont(ofSize: 14)
        retryButton.target = self
        retryButton.action = #selector(retry)
        retryButton.isHidden = true

        let stack = NSStackView(views: [placeholderLabel, retryButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        placeholderContainer.addSubview(stack)
        addSubview(placeholderContainer)
        placeholderContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderContainer.topAnchor.constraint(equalTo: topAnchor),
            placeholderContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: placeholderContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: placeholderContainer.centerYAnchor)
        ])
        placeholderLabel.stringValue = "解析中"
    }
}
