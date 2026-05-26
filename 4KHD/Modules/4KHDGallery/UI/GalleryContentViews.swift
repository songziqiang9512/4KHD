import AppKit

@MainActor
final class GalleryListRowView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("GalleryListRowView")

    private let coverView = GalleryRemoteImageView()
    private let kindLabel = GalleryPillLabel()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let favoriteIcon = NSImageView()
    private let cachedIcon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(item: GalleryItem, isFavorite: Bool, isCached: Bool) {
        coverView.setImage(url: item.coverURL, maxPixelSize: 180)
        kindLabel.configure(kind: item.kind)
        kindLabel.isHidden = item.kind == .gallery
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle
        favoriteIcon.isHidden = !isFavorite
        cachedIcon.isHidden = !isCached
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
        subtitleLabel.maximumNumberOfLines = 1

        favoriteIcon.image = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: "已收藏")
        favoriteIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        favoriteIcon.contentTintColor = .secondaryLabelColor
        cachedIcon.image = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: "已缓存")
        cachedIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        cachedIcon.contentTintColor = .secondaryLabelColor

        let countStack = NSStackView(views: [kindLabel])
        countStack.orientation = .horizontal
        countStack.alignment = .centerY
        countStack.spacing = 5

        let iconStack = NSStackView(views: [favoriteIcon, cachedIcon])
        iconStack.orientation = .horizontal
        iconStack.alignment = .centerY
        iconStack.spacing = 8

        let textStack = NSStackView(views: [countStack, titleLabel, subtitleLabel, iconStack])
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
final class GalleryFavoriteGroupHeaderView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("GalleryFavoriteGroupHeaderView")

    var onRename: (() -> Void)?

    private let chevron = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(group: FavoriteAuthorGroup, isExpanded: Bool) {
        titleLabel.stringValue = group.author
        countLabel.stringValue = "\(group.items.count)"
        chevron.image = NSImage(systemSymbolName: isExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: isExpanded ? "折叠" : "展开")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "重命名目录", action: #selector(rename), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func rename() {
        onRename?()
    }

    private func setupView() {
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        chevron.contentTintColor = .tertiaryLabelColor

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        let stack = NSStackView(views: [chevron, titleLabel, spacer, countLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

@MainActor
final class GalleryFooterRowView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("GalleryFooterRowView")

    private let progress = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
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
final class GalleryPillLabel: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        alignment = .center
        font = .systemFont(ofSize: 10, weight: .semibold)
        wantsLayer = true
        layer?.cornerRadius = 8
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(kind: ContentKind) {
        switch kind {
        case .gallery:
            stringValue = "图集"
            textColor = .secondaryLabelColor
        case .recommended:
            stringValue = "推荐"
            textColor = .systemBlue
        case .advertisement:
            stringValue = "广告"
            textColor = .systemOrange
        }
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 12, height: 18)
    }
}
