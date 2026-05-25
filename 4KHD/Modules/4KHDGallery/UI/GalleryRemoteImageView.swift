import AppKit
import Nuke

@MainActor
final class GalleryRemoteImageView: NSView {
    enum Mode {
        case aspectFill
        case aspectFit
    }

    var mode: Mode = .aspectFill {
        didSet { needsLayout = true }
    }

    var cornerRadius: CGFloat = 6 {
        didSet {
            layer?.cornerRadius = cornerRadius
            needsLayout = true
        }
    }

    private let imageView = NSImageView()
    private let placeholderImageView = NSImageView()
    private var imageTask: ImageTask?
    private var loadedURL: URL?

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
        imageView.frame = imageRect(for: bounds)
        placeholderImageView.frame = bounds
    }

    func setImage(url: URL?, maxPixelSize: CGFloat = 220) {
        imageTask?.cancel()
        guard loadedURL != url else { return }
        loadedURL = url
        guard let url else {
            // URL is nil — clear the image and show placeholder
            imageView.image = nil
            placeholderImageView.isHidden = false
            return
        }
        // Keep the existing image visible while the new one loads.
        // Only show placeholder if there is no image to preserve,
        // which avoids a flash during fast scrolling.
        if imageView.image == nil {
            placeholderImageView.isHidden = false
        }

        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .low,
            maxPixelSize: maxPixelSize,
            configureURLRequest: GalleryRequestFactory.configureImageRequest
        )
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.loadedURL == url else { return }
                self.imageView.image = image
                self.placeholderImageView.isHidden = image != nil
                self.needsLayout = true
            }
        }
    }

    func cancelPendingLoad() {
        imageTask?.cancel()
        imageTask = nil
        loadedURL = nil
        // Don't clear imageView.image — let the old image stay visible
        // until the next configure call replaces it. This avoids a
        // flash during fast scrolling where cells are rapidly recycled.
        if imageView.image == nil {
            placeholderImageView.isHidden = false
        }
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleAxesIndependently
        imageView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(imageView)

        placeholderImageView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        placeholderImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        placeholderImageView.contentTintColor = .tertiaryLabelColor
        placeholderImageView.imageScaling = .scaleNone
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(placeholderImageView)
    }

    private func imageRect(for rect: NSRect) -> NSRect {
        guard let image = imageView.image else { return rect }
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, rect.width > 0, rect.height > 0 else { return rect }

        let xScale = rect.width / imageSize.width
        let yScale = rect.height / imageSize.height
        let scale = mode == .aspectFill ? max(xScale, yScale) : min(xScale, yScale)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
