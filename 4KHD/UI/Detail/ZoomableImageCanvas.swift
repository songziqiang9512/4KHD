import AppKit
import SwiftUI

/// 详情主图区。支持双指捏合缩放（围绕鼠标位置）、拖拽 / 滚轮平移、`resetToken` 重置。
/// 上层传入 `contentInsets` 给周围 chrome 让位；这里不直接显示标题或按钮。
struct ZoomableImageCanvas<Placeholder: View>: View {
    let url: URL?
    let resetToken: UUID
    let contentInsets: EdgeInsets
    let localMaxPixelSize: CGFloat?
    @ViewBuilder let placeholder: () -> Placeholder
    let onDisplayed: () -> Void
    let onBlankTap: () -> Void

    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var imageSize: CGSize?

    init(
        url: URL?,
        resetToken: UUID,
        contentInsets: EdgeInsets,
        localMaxPixelSize: CGFloat? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        onDisplayed: @escaping () -> Void,
        onBlankTap: @escaping () -> Void = {}
    ) {
        self.url = url
        self.resetToken = resetToken
        self.contentInsets = contentInsets
        self.localMaxPixelSize = localMaxPixelSize
        self.placeholder = placeholder
        self.onDisplayed = onDisplayed
        self.onBlankTap = onBlankTap
    }

    var body: some View {
        GeometryReader { proxy in
            let fitSize = contentSize(in: proxy.size)
            let fitCenter = CGPoint(
                x: contentInsets.leading + fitSize.width / 2,
                y: contentInsets.top + fitSize.height / 2
            )

            ZStack {
                RemoteImageView(
                    url: url,
                    contentMode: .fit,
                    priority: .userInitiated,
                    localMaxPixelSize: localMaxPixelSize,
                    onLoaded: onDisplayed,
                    onImageLoaded: { image in
                        imageSize = image.size
                        panOffset = clampedPanOffset(panOffset, in: fitSize, imageSize: image.size)
                        dragStartOffset = panOffset
                    }
                ) {
                    placeholder()
                }
                .frame(width: fitSize.width, height: fitSize.height)
                .scaleEffect(zoomScale)
                .offset(panOffset)
                .position(fitCenter)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .overlay {
                TrackpadPanView { delta in
                    guard zoomScale > 1 else { return }
                    let proposed = CGSize(
                        width: panOffset.width + delta.width,
                        height: panOffset.height + delta.height
                    )
                    panOffset = clampedPanOffset(proposed, in: fitSize, imageSize: imageSize)
                    dragStartOffset = panOffset
                } onMagnify: { magnification, location in
                    zoom(by: magnification, around: locationInContent(location, containerSize: proxy.size), in: fitSize)
                } onMagnifyEnded: {
                    settleZoom(in: fitSize)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let proposed = CGSize(
                            width: dragStartOffset.width + value.translation.width,
                            height: dragStartOffset.height + value.translation.height
                        )
                        panOffset = clampedPanOffset(proposed, in: fitSize, imageSize: imageSize)
                    }
                    .onEnded { _ in
                        panOffset = clampedPanOffset(panOffset, in: fitSize, imageSize: imageSize)
                        dragStartOffset = panOffset
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if isBlankLocation(value.location, in: fitSize) {
                            onBlankTap()
                        }
                    }
            )
        }
        .clipped()
        .onChange(of: url) { _, _ in resetView() }
        .onChange(of: resetToken) { _, _ in resetView() }
        .animation(.snappy(duration: 0.18), value: zoomScale)
    }

    private func resetView() {
        zoomScale = 1
        panOffset = .zero
        dragStartOffset = .zero
        imageSize = nil
    }

    private func contentSize(in containerSize: CGSize) -> CGSize {
        CGSize(
            width: max(containerSize.width - contentInsets.leading - contentInsets.trailing, 1),
            height: max(containerSize.height - contentInsets.top - contentInsets.bottom, 1)
        )
    }

    private func locationInContent(_ location: CGPoint, containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: location.x - contentInsets.leading,
            y: location.y - contentInsets.top
        )
    }

    private func zoom(by magnification: CGFloat, around location: CGPoint, in containerSize: CGSize) {
        let currentScale = zoomScale
        let nextScale = min(max(currentScale * (1 + magnification), 0.65), 5)
        guard nextScale != currentScale else { return }

        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let relativePoint = CGSize(
            width: location.x - center.x,
            height: location.y - center.y
        )
        let scaleRatio = nextScale / currentScale
        let proposedOffset = CGSize(
            width: relativePoint.width * (1 - scaleRatio) + panOffset.width * scaleRatio,
            height: relativePoint.height * (1 - scaleRatio) + panOffset.height * scaleRatio
        )

        zoomScale = nextScale
        panOffset = clampedPanOffset(proposedOffset, in: containerSize, imageSize: imageSize)
        dragStartOffset = panOffset
    }

    private func settleZoom(in containerSize: CGSize) {
        guard zoomScale < 1 else {
            panOffset = clampedPanOffset(panOffset, in: containerSize, imageSize: imageSize)
            dragStartOffset = panOffset
            return
        }

        withAnimation(.snappy(duration: 0.2)) {
            zoomScale = 1
            panOffset = .zero
        }
        dragStartOffset = .zero
    }

    private func clampedPanOffset(_ offset: CGSize, in containerSize: CGSize, imageSize: CGSize?) -> CGSize {
        guard zoomScale > 1 else { return .zero }
        let fittedSize = fittedImageSize(in: containerSize, imageSize: imageSize)
        let maxX = max((fittedSize.width * zoomScale - containerSize.width) / 2, 0)
        let maxY = max((fittedSize.height * zoomScale - containerSize.height) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func fittedImageSize(in containerSize: CGSize, imageSize: CGSize?) -> CGSize {
        guard let imageSize,
              imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return containerSize
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func isBlankLocation(_ location: CGPoint, in containerSize: CGSize) -> Bool {
        guard imageSize != nil else { return false }
        let fittedSize = fittedImageSize(in: containerSize, imageSize: imageSize)
        let displayedSize = CGSize(width: fittedSize.width * zoomScale, height: fittedSize.height * zoomScale)
        let center = CGPoint(
            x: contentInsets.leading + containerSize.width / 2 + panOffset.width,
            y: contentInsets.top + containerSize.height / 2 + panOffset.height
        )
        let imageFrame = CGRect(
            x: center.x - displayedSize.width / 2,
            y: center.y - displayedSize.height / 2,
            width: displayedSize.width,
            height: displayedSize.height
        )
        return !imageFrame.contains(location)
    }
}

/// 用 `NSView` 拦截 trackpad 的滚轮和捏合手势 ——
/// SwiftUI 的 `MagnifyGesture` 不会给捏合中心点，这里手动绕过去。
private struct TrackpadPanView: NSViewRepresentable {
    let onPan: (CGSize) -> Void
    let onMagnify: (CGFloat, CGPoint) -> Void
    let onMagnifyEnded: () -> Void

    func makeNSView(context: Context) -> NSView {
        ScrollCatcherView(onPan: onPan, onMagnify: onMagnify, onMagnifyEnded: onMagnifyEnded)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let catcher = nsView as? ScrollCatcherView else { return }
        catcher.onPan = onPan
        catcher.onMagnify = onMagnify
        catcher.onMagnifyEnded = onMagnifyEnded
    }

    private final class ScrollCatcherView: NSView {
        var onPan: (CGSize) -> Void
        var onMagnify: (CGFloat, CGPoint) -> Void
        var onMagnifyEnded: () -> Void

        override var isFlipped: Bool { true }

        init(
            onPan: @escaping (CGSize) -> Void,
            onMagnify: @escaping (CGFloat, CGPoint) -> Void,
            onMagnifyEnded: @escaping () -> Void
        ) {
            self.onPan = onPan
            self.onMagnify = onMagnify
            self.onMagnifyEnded = onMagnifyEnded
            super.init(frame: .zero)
            wantsLayer = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func scrollWheel(with event: NSEvent) {
            let horizontalDelta = event.scrollingDeltaX
            let verticalDelta = event.scrollingDeltaY

            if abs(horizontalDelta) > abs(verticalDelta) {
                onPan(CGSize(width: horizontalDelta, height: 0))
            } else {
                onPan(CGSize(width: 0, height: verticalDelta))
            }
        }

        override func magnify(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            onMagnify(event.magnification, location)
        }

        override func endGesture(with event: NSEvent) {
            onMagnifyEnded()
        }

        override func mouseDown(with event: NSEvent) {
            nextResponder?.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            nextResponder?.mouseDragged(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            nextResponder?.mouseUp(with: event)
        }
    }
}
