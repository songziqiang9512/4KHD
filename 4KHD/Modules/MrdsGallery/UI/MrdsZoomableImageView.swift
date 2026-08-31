import AppKit
import Nuke

@MainActor
final class MrdsZoomableImageView: WorkspaceZoomableImageView {
    private let statusLabel = NSTextField(labelWithString: "解析中")
    private var imageTask: RemoteImageLoadTask?
    private var loadedURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor
        addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func setImageURL(_ url: URL?, preservesCurrentImageUntilLoaded: Bool = false) {
        imageTask?.cancel()
        guard loadedURL != url || imageView.image == nil else { return }
        let identityChanged = loadedURL != url
        loadedURL = url
        if url == nil || (identityChanged && !preservesCurrentImageUntilLoaded) {
            imageView.image = nil
        }
        statusLabel.stringValue = "解析中"
        statusLabel.isHidden = preservesCurrentImageUntilLoaded && imageView.image != nil
        guard let url else { return }
        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .veryHigh,
            maxPixelSize: 4096,
            configureURLRequest: MrdsRequestFactory.configureImageRequest
        )
        if let cached = RemoteImagePipeline.shared.cachedImage(with: request) {
            statusLabel.isHidden = true
            imageView.image = cached
            fitImage(resetMagnification: true)
            imageTask = nil
            return
        }
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, loadedURL == url else { return }
                guard let image else {
                    statusLabel.stringValue = "图片加载失败"
                    statusLabel.isHidden = false
                    return
                }
                statusLabel.isHidden = true
                imageView.image = image
                fitImage(resetMagnification: true)
            }
        }
    }
}
