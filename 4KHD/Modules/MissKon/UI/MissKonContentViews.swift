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

    func configure(item: MissKonItem, searchQuery: String? = nil) {
        coverView.setImage(url: item.coverURL, maxPixelSize: 180)
        if let query = searchQuery, !query.isEmpty {
            titleLabel.attributedStringValue = highlightedAttributedString(item.title, query: query)
        } else {
            titleLabel.stringValue = item.title
        }
        subtitleLabel.stringValue = item.imageCount > 0 ? "\(item.imageCount) 张图片" : "多张图片"
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
    var onRetry: (() -> Void)?

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
            label.stringValue = "\(errorMessage) — 点击重试"
            label.textColor = .systemRed
        } else if isRefreshing {
            progress.startAnimation(nil)
            label.stringValue = "加载中..."
            label.textColor = .tertiaryLabelColor
        } else {
            progress.stopAnimation(nil)
            label.stringValue = canLoadMore ? "加载更多" : (hasItems ? "已到末尾" : "无内容")
            label.textColor = .tertiaryLabelColor
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

        let click = NSClickGestureRecognizer(target: self, action: #selector(didClick))
        addGestureRecognizer(click)
    }

    @objc private func didClick() {
        onRetry?()
    }
}

@MainActor
final class MissKonGridFooterItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("MissKonGridFooterItem")

    private let progress = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")
    var onRetry: (() -> Void)?

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

        let click = NSClickGestureRecognizer(target: self, action: #selector(didClick))
        view.addGestureRecognizer(click)
    }

    func configure(isRefreshing: Bool, errorMessage: String?, canLoadMore: Bool, hasItems: Bool) {
        progress.isHidden = !isRefreshing || errorMessage != nil
        if let errorMessage {
            progress.stopAnimation(nil)
            label.stringValue = "\(errorMessage) — 点击重试"
            label.textColor = .systemRed
        } else if isRefreshing {
            progress.startAnimation(nil)
            label.stringValue = "加载中..."
            label.textColor = .tertiaryLabelColor
        } else {
            progress.stopAnimation(nil)
            label.stringValue = canLoadMore ? "加载更多" : (hasItems ? "已到末尾" : "无内容")
            label.textColor = .tertiaryLabelColor
        }
    }

    @objc private func didClick() {
        onRetry?()
    }
}

@MainActor
final class MissKonGridItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("MissKonGridItemView")

    private let cardView = WorkspaceThumbnailGridCardView()
    private var imageTask: RemoteImageLoadTask?
    private var representedID: MissKonItem.ID?
    private var currentCoverURL: URL?
    var thumbnailMaxPixelSize: CGFloat = 512

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
        currentCoverURL = nil
        cardView.resetForReuse()
    }

    func configure(item: MissKonItem, isSelected: Bool, searchQuery: String? = nil, onAspectRatio: @escaping (CGFloat) -> Void) {
        let idChanged = representedID != item.id
        let urlChanged = currentCoverURL != item.coverURL
        representedID = item.id
        cardView.setText(title: item.title, metadata: item.imageCount > 0 ? "\(item.imageCount) 张图片" : "多张图片", highlightQuery: searchQuery)
        cardView.applySelectionState(isSelected)
        if idChanged || urlChanged {
            loadCover(for: item, onAspectRatio: onAspectRatio)
        } else if let ratio = item.coverAspectRatio.map({ CGFloat($0) }), ratio > 0 {
            onAspectRatio(ratio)
        }
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
        currentCoverURL = item.coverURL
        guard let coverURL = item.coverURL else {
            cardView.setPlaceholder("暂无缩略图", isVisible: true)
            return
        }
        let request = RemoteImagePipeline.shared.request(
            for: coverURL,
            priority: .normal,
            maxPixelSize: thumbnailMaxPixelSize,
            configureURLRequest: MissKonRequestFactory.configureImageRequest
        )
        if let cached = RemoteImagePipeline.shared.cachedImage(with: request) {
            cardView.setImage(cached, animated: false)
            if cached.size.width > 0, cached.size.height > 0 {
                onAspectRatio(cached.size.width / cached.size.height)
            }
            return
        }

        cardView.setPlaceholder("加载中...", isVisible: true)
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
