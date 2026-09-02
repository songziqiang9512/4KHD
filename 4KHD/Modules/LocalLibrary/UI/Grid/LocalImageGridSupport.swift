import AppKit

enum LocalImageThumbnailLoadResult {
    case image(NSImage)
    case missingFile
    case unavailable
}

final class LocalImageAppearanceAwareView: NSView {
    var appearanceDidChangeHandler: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChangeHandler?()
    }
}
