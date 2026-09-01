import AppKit

@MainActor
final class OnlineVideoDirectoryHeaderView: NSView {
    var onBack: ((String) -> Void)?
    private var parentFilter: String?
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backButton.bezelStyle = .accessoryBarAction
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "返回")
        backButton.imagePosition = .imageLeading
        backButton.target = self
        backButton.action = #selector(goBack)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [backButton, titleLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(separator)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(parentFilter: String, parentTitle: String, title: String) {
        self.parentFilter = parentFilter
        backButton.title = parentTitle
        titleLabel.stringValue = title
    }

    @objc private func goBack() {
        guard let parentFilter else { return }
        onBack?(parentFilter)
    }
}

enum OnlineVideoDirectoryChipMetrics {
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 7
    static let titleSubtitleSpacing: CGFloat = 1
    static let minWidth: CGFloat = 72
    static let maxWidth: CGFloat = 220
    static let interitemSpacing: CGFloat = 8
    static let lineSpacing: CGFloat = 8
    static let footerHeight: CGFloat = 42

    static func size(title: String, subtitle: String) -> NSSize {
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let subtitleFont = NSFont.systemFont(ofSize: 11)
        let maxTextWidth = maxWidth - horizontalPadding * 2
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let titleBounds = (title as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: 36),
            options: options,
            attributes: [.font: titleFont]
        )
        var width = ceil(titleBounds.width) + horizontalPadding * 2
        var height = ceil(titleBounds.height) + verticalPadding * 2
        if !subtitle.isEmpty {
            let subtitleBounds = (subtitle as NSString).boundingRect(
                with: NSSize(width: maxTextWidth, height: 28),
                options: options,
                attributes: [.font: subtitleFont]
            )
            width = max(width, ceil(subtitleBounds.width) + horizontalPadding * 2)
            height += ceil(subtitleBounds.height) + titleSubtitleSpacing
        }
        return NSSize(
            width: min(max(width, minWidth), maxWidth),
            height: max(height, 30)
        )
    }
}

final class OnlineVideoDirectoryChipLayout: NSCollectionViewLayout {
    var itemSizeProvider: ((Int) -> NSSize)?
    var treatsLastItemAsFooter = true
    private var cache: [NSCollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var preparedWidth: CGFloat = 0

    override var collectionViewContentSize: NSSize {
        NSSize(width: preparedWidth, height: contentHeight)
    }

    override func prepare() {
        super.prepare()
        cache.removeAll(keepingCapacity: true)
        contentHeight = 0
        preparedWidth = 0
        guard let collectionView, collectionView.numberOfSections > 0 else { return }
        let width = collectionView.bounds.width
        guard width > 1 else { return }
        preparedWidth = width
        let itemCount = collectionView.numberOfItems(inSection: 0)
        let inset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        let usableWidth = max(width - inset.left - inset.right, 1)
        var x = inset.left
        var y = inset.top
        var rowHeight: CGFloat = 0
        let chipCount = treatsLastItemAsFooter ? max(itemCount - 1, 0) : itemCount
        for index in 0 ..< chipCount {
            var size = itemSizeProvider?(index) ?? NSSize(width: 80, height: 32)
            size.width = min(size.width, usableWidth)
            if x > inset.left, x + size.width > width - inset.right {
                x = inset.left
                y += rowHeight + OnlineVideoDirectoryChipMetrics.lineSpacing
                rowHeight = 0
            }
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
            attributes.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            cache.append(attributes)
            x += size.width + OnlineVideoDirectoryChipMetrics.interitemSpacing
            rowHeight = max(rowHeight, size.height)
        }
        if treatsLastItemAsFooter, itemCount > chipCount {
            if chipCount > 0 {
                y += rowHeight + OnlineVideoDirectoryChipMetrics.lineSpacing
            }
            let attributes = NSCollectionViewLayoutAttributes(
                forItemWith: IndexPath(item: chipCount, section: 0)
            )
            attributes.frame = NSRect(
                x: inset.left,
                y: y,
                width: usableWidth,
                height: OnlineVideoDirectoryChipMetrics.footerHeight
            )
            cache.append(attributes)
            y += OnlineVideoDirectoryChipMetrics.footerHeight
        } else {
            y += rowHeight
        }
        contentHeight = max(y + inset.bottom, inset.top + inset.bottom)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        cache.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(newBounds.width - preparedWidth) > 0.5
    }
}

@MainActor
final class OnlineVideoDirectoryChipItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("OnlineVideoDirectoryChipItem")
    private let chrome = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var isHovered = false

    override func loadView() {
        view = NSView()
        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = 8
        chrome.layer?.masksToBounds = true
        chrome.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = OnlineVideoDirectoryChipMetrics.titleSubtitleSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chrome)
        chrome.addSubview(stack)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: view.topAnchor),
            chrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(
                equalTo: chrome.leadingAnchor,
                constant: OnlineVideoDirectoryChipMetrics.horizontalPadding
            ),
            stack.trailingAnchor.constraint(
                equalTo: chrome.trailingAnchor,
                constant: -OnlineVideoDirectoryChipMetrics.horizontalPadding
            ),
            stack.topAnchor.constraint(
                equalTo: chrome.topAnchor,
                constant: OnlineVideoDirectoryChipMetrics.verticalPadding
            ),
            stack.bottomAnchor.constraint(
                equalTo: chrome.bottomAnchor,
                constant: -OnlineVideoDirectoryChipMetrics.verticalPadding
            ),
        ])
        updateChrome()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
        titleLabel.stringValue = ""
        subtitleLabel.stringValue = ""
        updateChrome()
    }

    func configure(item: OnlineVideoItem, isSelected selected: Bool, searchQuery: String?) {
        if let searchQuery, !searchQuery.isEmpty {
            titleLabel.attributedStringValue = highlightedAttributedString(item.title, query: searchQuery)
        } else {
            titleLabel.stringValue = item.title
        }
        subtitleLabel.stringValue = item.subtitle
        subtitleLabel.isHidden = item.subtitle.isEmpty
        applySelectionState(selected)
    }

    override var isSelected: Bool {
        didSet { updateChrome() }
    }

    func applySelectionState(_ selected: Bool) {
        isSelected = selected
    }

    func clearHoverState() {
        isHovered = false
        updateChrome()
    }

    func syncHoverState(windowLocation: NSPoint?) {
        let hovered: Bool
        if let windowLocation {
            let local = view.convert(windowLocation, from: nil)
            hovered = view.bounds.contains(local)
        } else {
            hovered = false
        }
        guard hovered != isHovered else { return }
        isHovered = hovered
        updateChrome()
    }

    private func updateChrome() {
        let fill: NSColor
        if isSelected {
            fill = NSColor.controlAccentColor.withAlphaComponent(0.22)
        } else if isHovered {
            fill = NSColor.labelColor.withAlphaComponent(0.08)
        } else {
            fill = NSColor.labelColor.withAlphaComponent(0.05)
        }
        chrome.layer?.backgroundColor = fill.cgColor
        chrome.layer?.borderWidth = isSelected ? 1 : 0
        chrome.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
    }
}
