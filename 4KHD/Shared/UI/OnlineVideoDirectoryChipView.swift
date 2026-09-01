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
    static let verticalPadding: CGFloat = 8
    static let titleSubtitleSpacing: CGFloat = 2
    static let itemSize = NSSize(width: 120, height: 76)
    static let titleLineLimit = 3
    static let interitemSpacing: CGFloat = 8
    static let lineSpacing: CGFloat = 8
    static let footerHeight: CGFloat = 42
    static let sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
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
        titleLabel.alignment = .center
        titleLabel.usesSingleLineMode = false
        titleLabel.maximumNumberOfLines = OnlineVideoDirectoryChipMetrics.titleLineLimit
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        if let cell = titleLabel.cell as? NSTextFieldCell {
            cell.wraps = true
            cell.truncatesLastVisibleLine = true
            cell.isScrollable = false
        }
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
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
            stack.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),
            stack.topAnchor.constraint(
                greaterThanOrEqualTo: chrome.topAnchor,
                constant: OnlineVideoDirectoryChipMetrics.verticalPadding
            ),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: chrome.bottomAnchor,
                constant: -OnlineVideoDirectoryChipMetrics.verticalPadding
            ),
        ])
        updateChrome()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let textWidth = max(
            chrome.bounds.width - OnlineVideoDirectoryChipMetrics.horizontalPadding * 2,
            1
        )
        titleLabel.preferredMaxLayoutWidth = textWidth
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
            titleLabel.attributedStringValue = wrappingTitle(
                highlightedAttributedString(item.title, query: searchQuery)
            )
        } else {
            titleLabel.stringValue = item.title
        }
        subtitleLabel.stringValue = item.subtitle
        subtitleLabel.isHidden = item.subtitle.isEmpty
        applySelectionState(selected)
    }

    private func wrappingTitle(_ attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        mutable.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .paragraphStyle: paragraph,
            ],
            range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
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
