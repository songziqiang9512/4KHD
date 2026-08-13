import AppKit

@MainActor
final class LocalZoomableImageView: WorkspaceZoomableImageView {
    private let progressIndicator = NSProgressIndicator()
    private var imageTask: Task<Void, Never>?
    private var imageURL: URL?

    var onDisplayed: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        maxMagnification = 8
        setupLocalOverlay()
    }

    override var acceptsFirstResponder: Bool { true }

    func setImageURL(_ url: URL?, preservesCurrentImageUntilLoaded: Bool = false) {
        guard imageURL != url else { return }
        imageView.alphaValue = 1
        let shouldKeepCurrent = preservesCurrentImageUntilLoaded && imageView.image != nil
        imageURL = url
        imageTask?.cancel()
        if !shouldKeepCurrent {
            imageView.image = nil
            progressIndicator.isHidden = url == nil
            if url != nil {
                progressIndicator.startAnimation(nil)
            }
        }

        guard let url else { return }
        imageTask = Task { [weak self] in
            let image = await LocalImageCache.shared.image(for: url, maxPixelSize: self?.maxPixelSize)
            guard !Task.isCancelled else { return }
            self?.display(image)
        }
    }

    private var maxPixelSize: CGFloat {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return max(bounds.width, bounds.height) * scale
    }

    private func display(_ image: NSImage?) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        guard let image else { return }
        imageView.alphaValue = 0
        imageView.image = image
        fitImage(resetMagnification: true)
        onDisplayed?()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.imageView.animator().alphaValue = 1
        }
    }

    private func setupLocalOverlay() {
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .large
        progressIndicator.isDisplayedWhenStopped = false

        addSubview(progressIndicator)
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
