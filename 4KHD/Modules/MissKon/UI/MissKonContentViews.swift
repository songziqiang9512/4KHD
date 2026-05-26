import AppKit
import Nuke

@MainActor
final class MissKonListRowView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("MissKonListRowView")

    private let coverView = MissKonRemoteImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        setupView()
    }

    required init?(coder: NSCoder) { nil }

    func configure(item: MissKonItem) {
        coverView.setImage(url: item.coverURL, maxPixelSize: 180)
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = "\(item.imageCount) 张图片"
    }

    private func setupView() {
        coverView.cornerRadius = 5
        coverView.mode = .aspectFill

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2

        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let root = NSStackView(views: [coverView, textStack])
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 10

        addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        coverView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coverView.widthAnchor.constraint(equalToConstant: 64),
            coverView.heightAnchor.constraint(equalToConstant: 86),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            root.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4)
        ])
    }
}

@MainActor
final class MissKonFooterRowView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("MissKonFooterRowView")

    private let progress = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        setupView()
    }

    required init?(coder: NSCoder) { nil }

    func configure(isRefreshing: Bool, errorMessage: String?, canLoadMore: Bool, hasItems: Bool) {
        progress.isHidden = !isRefreshing || errorMessage != nil
        if let errorMessage {
            progress.stopAnimation(nil)
            label.stringValue = errorMessage
        } else if isRefreshing {
            progress.startAnimation(nil)
            label.stringValue = "加载下一页"
        } else {
            progress.stopAnimation(nil)
            label.stringValue = canLoadMore ? "继续加载" : (hasItems ? "已到末尾" : "")
        }
    }

    private func setupView() {
        progress.style = .spinning
        progress.controlSize = .small
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [progress, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progress.widthAnchor.constraint(equalToConstant: 16),
            progress.heightAnchor.constraint(equalToConstant: 16),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

@MainActor
final class MissKonGridItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("MissKonGridItemView")

    private let cardView = WorkspaceThumbnailGridCardView()
    private var imageTask: ImageTask?
    private var representedID: MissKonItem.ID?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.addSubview(cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        representedID = nil
        cardView.resetForReuse()
    }

    func configure(item: MissKonItem, isSelected: Bool, onAspectRatio: @escaping (CGFloat) -> Void) {
        representedID = item.id
        cardView.setText(title: item.title, metadata: "\(item.imageCount) 张图片")
        cardView.applySelectionState(isSelected)
        loadCover(for: item, onAspectRatio: onAspectRatio)
    }

    func applySelectionState(_ isSelected: Bool) {
        cardView.applySelectionState(isSelected)
    }

    func syncHoverState(windowLocation: NSPoint?) {
        cardView.syncHoverState(windowLocation: windowLocation)
    }

    func clearHoverState() {
        cardView.clearHoverState()
    }

    private func loadCover(for item: MissKonItem, onAspectRatio: @escaping (CGFloat) -> Void) {
        imageTask?.cancel()
        cardView.setImage(nil)
        guard let coverURL = item.coverURL else {
            cardView.setPlaceholder("暂无缩略图", isVisible: true)
            return
        }
        cardView.setPlaceholder("加载中...", isVisible: true)
        let request = RemoteImagePipeline.shared.request(
            for: coverURL,
            priority: .low,
            maxPixelSize: 512,
            configureURLRequest: MissKonRequestFactory.configureImageRequest
        )
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.representedID == item.id else { return }
                if let image {
                    self.cardView.setImage(image)
                    if image.size.width > 0, image.size.height > 0 {
                        onAspectRatio(image.size.width / image.size.height)
                    }
                } else {
                    self.cardView.setPlaceholder("缩略图不可用", isVisible: true)
                }
            }
        }
    }
}

@MainActor
final class MissKonGridFooterItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("MissKonGridFooterItem")

    private let progress = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        progress.style = .spinning
        progress.controlSize = .small
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [progress, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progress.widthAnchor.constraint(equalToConstant: 16),
            progress.heightAnchor.constraint(equalToConstant: 16),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func configure(isRefreshing: Bool, errorMessage: String?, canLoadMore: Bool, hasItems: Bool) {
        progress.isHidden = !isRefreshing || errorMessage != nil
        if let errorMessage {
            progress.stopAnimation(nil)
            label.stringValue = errorMessage
        } else if isRefreshing {
            progress.startAnimation(nil)
            label.stringValue = "加载下一页"
        } else {
            progress.stopAnimation(nil)
            label.stringValue = canLoadMore ? "继续加载" : (hasItems ? "已到末尾" : "")
        }
    }
}
