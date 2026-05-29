import AppKit
import Nuke

// MARK: - List Row

@MainActor
final class WallhavenListRowView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("WallhavenListRowView")

    private let coverView = WallhavenRemoteImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        setupView()
    }

    required init?(coder: NSCoder) { nil }

    func configure(wallpaper: Wallpaper, searchQuery: String? = nil) {
        coverView.mode = .aspectFit
        coverView.setImage(url: wallpaper.thumbnailUrl ?? wallpaper.previewUrl, maxPixelSize: 180)
        let displayName = formatDisplayName(wallpaper)
        if let query = searchQuery, !query.isEmpty {
            titleLabel.attributedStringValue = highlightedAttributedString(displayName, query: query)
        } else {
            titleLabel.stringValue = displayName
        }
        subtitleLabel.stringValue = formatSubtitle(wallpaper)
    }

    private func formatDisplayName(_ wallpaper: Wallpaper) -> String {
        let tags = wallpaper.tags.prefix(5).joined(separator: ", ")
        return tags.isEmpty ? "Wallhaven \(wallpaper.id)" : tags
    }

    private func formatSubtitle(_ wallpaper: Wallpaper) -> String {
        [
            wallpaper.resolutionText,
            wallpaper.formattedFileSize,
            wallpaper.purity.title
        ].filter { !$0.isEmpty && $0 != "-" }.joined(separator: " · ")
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

// MARK: - Footer Row (shared between list/grid footer containers)

@MainActor
final class WallhavenFooterRowView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("WallhavenFooterRowView")

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

// MARK: - Grid Item

@MainActor
final class WallhavenGridItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("WallhavenGridItemView")

    private let cardView = WorkspaceThumbnailGridCardView()
    private var imageTask: ImageTask?
    private var representedID: Wallpaper.ID?
    private var currentThumbURL: URL?

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
        currentThumbURL = nil
        cardView.resetForReuse()
    }

    func configure(wallpaper: Wallpaper, isSelected: Bool, searchQuery: String? = nil, onAspectRatio: @escaping (CGFloat) -> Void) {
        let thumbURL = wallpaper.thumbnailUrl
        let idChanged = representedID != wallpaper.id
        let urlChanged = currentThumbURL != thumbURL
        representedID = wallpaper.id

        let tagsText = wallpaper.tags.prefix(3).joined(separator: ", ")
        let title = tagsText.isEmpty ? "Wallhaven \(wallpaper.id)" : tagsText
        let metadataParts = [wallpaper.resolutionText, wallpaper.formattedFileSize].filter { $0 != "-" }
        let metadata = metadataParts.isEmpty ? wallpaper.purity.title : metadataParts.joined(separator: " · ")
        cardView.setText(title: title, metadata: metadata, highlightQuery: searchQuery)
        cardView.applySelectionState(isSelected)

        // Only reload image if the represented wallpaper or its thumb URL changed.
        if idChanged || urlChanged {
            loadCover(for: wallpaper, onAspectRatio: onAspectRatio)
        } else if let ratio = wallpaper.aspectRatio.map({ CGFloat($0) }), ratio > 0 {
            // Pass API aspect ratio when dimensions are known; suppress thumbnail-based re-layout.
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

    private func loadCover(for wallpaper: Wallpaper, onAspectRatio: @escaping (CGFloat) -> Void) {
        imageTask?.cancel()
        cardView.setImage(nil)
        currentThumbURL = wallpaper.thumbnailUrl
        guard let thumbURL = wallpaper.thumbnailUrl else {
            cardView.setPlaceholder("无缩略图", isVisible: true)
            return
        }
        let request = RemoteImagePipeline.shared.request(
            for: thumbURL,
            priority: .normal,
            maxPixelSize: 512,
            configureURLRequest: WallhavenRequestFactory.configureImageRequest
        )
        if let cached = RemoteImagePipeline.shared.cachedImage(with: request) {
            cardView.setImage(cached, animated: false)
            if wallpaper.aspectRatio == nil, cached.size.width > 0, cached.size.height > 0 {
                onAspectRatio(cached.size.width / cached.size.height)
            }
            return
        }

        cardView.setPlaceholder("加载中...", isVisible: true)
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.representedID == wallpaper.id else { return }
                if let image {
                    self.cardView.setImage(image)
                    // Only report thumbnail dimensions if API dimensions are missing.
                    if wallpaper.aspectRatio == nil, image.size.width > 0, image.size.height > 0 {
                        onAspectRatio(image.size.width / image.size.height)
                    }
                } else {
                    self.cardView.setPlaceholder("缩略图不可用", isVisible: true)
                }
            }
        }
    }
}

// MARK: - Grid Footer

@MainActor
final class WallhavenGridFooterItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("WallhavenGridFooterItem")

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
