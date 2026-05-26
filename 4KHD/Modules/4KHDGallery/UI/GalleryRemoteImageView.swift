import AppKit

final class GalleryRemoteImageView: RemoteImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureRequest = GalleryRequestFactory.configureImageRequest
    }

    required init?(coder: NSCoder) { nil }
}
