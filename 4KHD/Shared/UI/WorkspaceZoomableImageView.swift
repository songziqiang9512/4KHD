import AppKit

class WorkspaceZoomableImageView: NSView {
    let scrollView = WorkspaceZoomScrollView()
    let documentView = NSView()
    let imageView = NSImageView()
    let minimumRubberBandMagnification: CGFloat = 0.8
    var maxMagnification: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupScrollView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        if abs(scrollView.magnification - 1) < 0.001 {
            fitImage(resetMagnification: false)
        }
    }

    func resetZoom() {
        fitImage(resetMagnification: true)
    }

    func fitImage(resetMagnification: Bool) {
        guard let image = imageView.image,
              image.size.width > 0, image.size.height > 0 else { return }
        if resetMagnification {
            scrollView.magnification = 1
            scrollView.layoutSubtreeIfNeeded()
        }
        let viewport = scrollView.contentView.bounds.size
        guard viewport.width > 1, viewport.height > 1 else { return }

        let scale = min(viewport.width / image.size.width, viewport.height / image.size.height)
        guard scale.isFinite, scale > 0 else { return }
        let fittedSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
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

    func restoreBaselineAfterRubberBand() {
        guard scrollView.magnification < 1 else { return }
        let visibleRect = scrollView.contentView.bounds
        let center = NSPoint(x: visibleRect.midX, y: visibleRect.midY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            scrollView.setMagnification(1, centeredAt: center)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.scrollView.contentView.scroll(to: .zero)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    private func setupScrollView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = minimumRubberBandMagnification
        scrollView.maxMagnification = maxMagnification
        scrollView.autohidesScrollers = true
        scrollView.contentView = CenteringClipView()
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
    }
}

private final class CenteringClipView: NSClipView {
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

final class WorkspaceZoomScrollView: NSScrollView {
    var onMagnifyEndedBelowBaseline: (() -> Void)?

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
    }

    override func viewDidEndLiveResize() {
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

        let pointInView = convert(event.locationInWindow, from: nil)
        setMagnification(proposedMagnification, centeredAt: pointInView)
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            onMagnifyEndedBelowBaseline?()
        }
    }
}
