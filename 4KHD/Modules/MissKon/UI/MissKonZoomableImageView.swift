import AppKit
import Nuke

@MainActor
final class MissKonZoomableImageView: WorkspaceZoomableImageView {
    var onImageDisplayed: (() -> Void)?

    private let placeholderContainer = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "解析中")
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

    private func setupPlaceholder() {
        placeholderLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center

        placeholderContainer.addSubview(placeholderLabel)
        addSubview(placeholderContainer)
        placeholderContainer.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderContainer.topAnchor.constraint(equalTo: topAnchor),
            placeholderContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholderLabel.centerXAnchor.constraint(equalTo: placeholderContainer.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: placeholderContainer.centerYAnchor)
        ])
        placeholderLabel.stringValue = "解析中"
    }
}
