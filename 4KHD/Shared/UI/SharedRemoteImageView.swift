import AppKit
import Nuke

@MainActor
class RemoteImageView: NSView {
    enum Mode {
        case aspectFill
        case aspectFit
    }

    var mode: Mode = .aspectFill { didSet { needsLayout = true } }
    var cornerRadius: CGFloat = 6 { didSet { layer?.cornerRadius = cornerRadius; needsLayout = true } }
    var configureRequest: ((inout URLRequest) -> Void)?

    private let imageView = NSImageView()
    private let placeholderImageView = NSImageView()
    private var imageTask: ImageTask?
    private var loadedURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) { nil }

    deinit { imageTask?.cancel() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor
    }

    override func layout() {
        super.layout()
        imageView.frame = imageRect(for: bounds)
        placeholderImageView.frame = bounds
    }

    func setImage(url: URL?, maxPixelSize: CGFloat = 220) {
        // 同 URL 且已有图才跳过：加载失败的缩略图滚出再滚回时重新尝试。
        guard loadedURL != url || imageView.image == nil else { return }
        imageTask?.cancel()
        loadedURL = url
        imageView.alphaValue = 1
        guard let url else {
            imageView.image = nil
            placeholderImageView.isHidden = false
            return
        }
        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .normal,
            maxPixelSize: maxPixelSize,
            configureURLRequest: configureRequest ?? { _ in }
        )
        if let cached = RemoteImagePipeline.shared.cachedImage(with: request) {
            imageView.image = cached
            placeholderImageView.isHidden = true
            imageTask = nil
            needsLayout = true
            return
        }
        if imageView.image == nil {
            placeholderImageView.isHidden = false
        }
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.loadedURL == url else { return }
                guard let image else {
                    self.placeholderImageView.isHidden = false
                    return
                }
                self.imageView.alphaValue = 0
                self.imageView.image = image
                self.placeholderImageView.isHidden = true
                self.needsLayout = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    self.imageView.animator().alphaValue = 1
                }
            }
        }
    }

    func cancelPendingLoad() {
        imageTask?.cancel()
        imageTask = nil
        loadedURL = nil
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
        addSubview(imageView)

        placeholderImageView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        placeholderImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        placeholderImageView.contentTintColor = .tertiaryLabelColor
        placeholderImageView.imageScaling = .scaleNone
        addSubview(placeholderImageView)
    }

    private func imageRect(for rect: NSRect) -> NSRect {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
              rect.width > 0, rect.height > 0 else { return rect }
        let xScale = rect.width / image.size.width
        let yScale = rect.height / image.size.height
        let scale = mode == .aspectFill ? max(xScale, yScale) : min(xScale, yScale)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}
