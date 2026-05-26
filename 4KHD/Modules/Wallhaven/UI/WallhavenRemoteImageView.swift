import AppKit

final class WallhavenRemoteImageView: RemoteImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureRequest = WallhavenRequestFactory.configureImageRequest
    }

    required init?(coder: NSCoder) { nil }
}
