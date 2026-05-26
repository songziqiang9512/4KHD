import AppKit

final class MissKonRemoteImageView: RemoteImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureRequest = MissKonRequestFactory.configureImageRequest
    }

    required init?(coder: NSCoder) { nil }
}
