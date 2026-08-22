import AppKit
import Nuke

/// 收藏详情的缩放图片视图:与 MissKon 版同款占位/失败/重试行为,
/// 请求头按收藏来源动态配置。
@MainActor
final class FavoritesZoomableImageView: WorkspaceZoomableImageView {
    var onImageDisplayed: (() -> Void)?
    var requestConfigurator: ((inout URLRequest) -> Void)?

    private let placeholderContainer = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "解析中")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private var retryAction: (() -> Void)?
    private var imageTask: ImageTask?
    private var loadedURL: URL?
    /// 正在网络加载的 URL:同一 URL 的在途请求被再次调用时直接复用,不取消重启。
    private var inFlightURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupPlaceholder()
    }

    func setImageURL(_ url: URL?, preservesCurrentImageUntilLoaded: Bool = false) {
        // 同一 URL 的请求仍在途:直接复用,避免封面→详情同 URL 连续调用时取消重启。
        if let url, url == inFlightURL { return }
        imageTask?.cancel()
        inFlightURL = nil
        // 同 URL 且已有图才跳过:加载失败后重试同一 URL 必须重新发起请求。
        guard loadedURL != url || imageView.image == nil else { return }
        loadedURL = url
        imageView.alphaValue = 1
        guard let url else {
            imageView.image = nil
            placeholderContainer.isHidden = false
            return
        }

        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .veryHigh,
            maxPixelSize: 4096,
            configureURLRequest: requestConfigurator ?? { _ in }
        )
        // 4096px 缓存未命中时回退 512px(网格缩略图分辨率),让封面立即显示。
        let cached: NSImage?
        if let img = RemoteImagePipeline.shared.cachedImage(with: request) {
            cached = img
        } else {
            let thumbRequest = RemoteImagePipeline.shared.request(
                for: url,
                priority: .veryHigh,
                maxPixelSize: 512,
                configureURLRequest: requestConfigurator ?? { _ in }
            )
            cached = RemoteImagePipeline.shared.cachedImage(with: thumbRequest)
        }
        if let cached {
            imageView.image = cached
            placeholderContainer.isHidden = true
            fitImage(resetMagnification: true)
            onImageDisplayed?()
            return
        }

        let shouldKeepCurrent = preservesCurrentImageUntilLoaded && imageView.image != nil
        if !shouldKeepCurrent {
            imageView.image = nil
            placeholderLabel.stringValue = "加载中"
            retryButton.isHidden = true
            placeholderContainer.isHidden = false
        }

        inFlightURL = url
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.loadedURL == url else { return }
                self.inFlightURL = nil
                guard let image else {
                    if !shouldKeepCurrent || self.imageView.image == nil {
                        self.placeholderLabel.stringValue = "图片加载失败"
                        self.retryButton.isHidden = true
                        self.placeholderContainer.isHidden = false
                    }
                    return
                }
                self.placeholderContainer.isHidden = true
                self.imageView.alphaValue = 0
                self.imageView.image = image
                self.fitImage(resetMagnification: true)
                self.onImageDisplayed?()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    self.imageView.animator().alphaValue = 1
                }
            }
        }
    }

    func showFailure(retry: @escaping () -> Void) {
        retryAction = retry
        imageTask?.cancel()
        inFlightURL = nil
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
        placeholderLabel.drawsBackground = false

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
            stack.centerYAnchor.constraint(equalTo: placeholderContainer.centerYAnchor),
        ])
        placeholderLabel.stringValue = "解析中"
    }
}
