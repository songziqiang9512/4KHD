import AppKit

final class LocalImageGridItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LocalImageGridItemView")

    private let cardView = WorkspaceThumbnailGridCardView()
    private var representedID: String?
    private var imageTaskID: UUID?

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        setupView()
    }

    override func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        view.frame = layoutAttributes.frame
        cardView.frame = view.bounds
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        cardView.frame = view.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedID = nil
        imageTaskID = nil
        cardView.resetForReuse()
    }

    func configure(
        image: LocalImageItem,
        metadata: LocalImageMetadata?,
        fileExists: Bool,
        isSelected: Bool,
        cachedThumbnail: NSImage?,
        thumbnailLoader: @escaping (@escaping (LocalImageThumbnailLoadResult) -> Void) -> Void
    ) {
        representedID = image.id
        cardView.prepareForImmediateDisplay()
        cardView.setText(title: image.title, metadata: metadataText(for: image, metadata: metadata))
        cardView.applySelectionState(isSelected)
        cardView.setMissingVisible(!fileExists)
        cardView.setPlaceholder(fileExists ? "加载中..." : "原文件不存在", isVisible: true)
        cardView.setImage(cachedThumbnail)

        guard fileExists, cachedThumbnail == nil else { return }

        let taskID = UUID()
        imageTaskID = taskID
        thumbnailLoader { [weak self] result in
            guard let self, self.imageTaskID == taskID, self.representedID == image.id else { return }
            switch result {
            case .image(let thumbnail):
                self.cardView.setImage(thumbnail)
                self.cardView.setMissingVisible(false)
            case .missingFile:
                self.cardView.setImage(nil)
                self.cardView.setPlaceholder("原文件不存在", isVisible: true)
                self.cardView.setMissingVisible(true)
            case .unavailable:
                self.cardView.setImage(nil)
                self.cardView.setPlaceholder("缩略图不可用", isVisible: true)
                self.cardView.setMissingVisible(false)
            }
        }
    }

    func applySelectionState(_ isSelected: Bool) {
        cardView.applySelectionState(isSelected)
    }

    func applyPressedState(_ isPressed: Bool) {
        cardView.applyPressedState(isPressed)
    }

    func syncHoverState(windowLocation: NSPoint?) {
        cardView.syncHoverState(windowLocation: windowLocation)
    }

    func clearHoverState() {
        cardView.clearHoverState()
    }

    private func setupView() {
        view.addSubview(cardView)
    }

    private func metadataText(for image: LocalImageItem, metadata: LocalImageMetadata?) -> String {
        let parts = [
            formattedResolution(metadata),
            formattedSecondaryMetadata(metadata)
        ].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        return image.url.deletingLastPathComponent().lastPathComponent
    }
}
