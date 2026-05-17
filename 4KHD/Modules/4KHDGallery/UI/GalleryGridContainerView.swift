import AppKit

@MainActor
final class GalleryGridContainerView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((GalleryItem) -> Void)?
    var onNeedsMore: (() -> Void)?

    private let scrollView = NSScrollView()
    private let collectionView = GalleryGridCollectionView()
    private let gridLayout = NSCollectionViewFlowLayout()
    private var items: [GalleryItem] = []
    private var selectedItemID: GalleryItem.ID?
    private var showsFooter = false
    private var isRefreshing = false
    private var canLoadMore = false
    private var preferredColumnCount: Int?
    private var preferredCardMinimumWidth: CGFloat = 160
    private var isFavorite: (GalleryItem) -> Bool = { _ in false }
    private var isCached: (GalleryItem) -> Bool = { _ in false }
    private var isApplyingSelection = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        updateItemSize()
    }

    func update(
        items: [GalleryItem],
        selectedItemID: GalleryItem.ID?,
        preferredColumnCount: Int?,
        preferredCardMinimumWidth: CGFloat,
        showsFooter: Bool,
        isRefreshing: Bool,
        canLoadMore: Bool,
        isFavorite: @escaping (GalleryItem) -> Bool,
        isCached: @escaping (GalleryItem) -> Bool
    ) {
        self.items = items
        self.selectedItemID = selectedItemID
        self.preferredColumnCount = preferredColumnCount
        self.preferredCardMinimumWidth = preferredCardMinimumWidth
        self.showsFooter = showsFooter
        self.isRefreshing = isRefreshing
        self.canLoadMore = canLoadMore
        self.isFavorite = isFavorite
        self.isCached = isCached
        updateItemSize()
        collectionView.reloadData()
        syncSelection()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count + (showsFooter ? 1 : 0)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        if indexPath.item >= items.count {
            let item = collectionView.makeItem(
                withIdentifier: GalleryGridFooterItem.reuseID,
                for: indexPath
            ) as? GalleryGridFooterItem ?? GalleryGridFooterItem()
            item.configure(isRefreshing: isRefreshing, canLoadMore: canLoadMore, hasItems: !items.isEmpty)
            return item
        }

        let item = collectionView.makeItem(
            withIdentifier: GalleryGridItemView.reuseID,
            for: indexPath
        ) as? GalleryGridItemView ?? GalleryGridItemView()
        let galleryItem = items[indexPath.item]
        item.configure(
            item: galleryItem,
            isSelected: galleryItem.id == selectedItemID,
            isFavorite: isFavorite(galleryItem),
            isCached: isCached(galleryItem)
        )
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection,
              let indexPath = indexPaths.first,
              items.indices.contains(indexPath.item) else { return }
        let item = items[indexPath.item]
        selectedItemID = item.id
        refreshVisibleSelection()
        onSelect?(item)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard indexPath.item >= max(items.count - 3, 0) else { return }
        onNeedsMore?()
    }

    private func setupView() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = collectionView

        gridLayout.minimumInteritemSpacing = 14
        gridLayout.minimumLineSpacing = 14
        gridLayout.sectionInset = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        collectionView.collectionViewLayout = gridLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.arrowKeyHandler = { [weak self] delta in
            self?.selectAdjacent(delta: delta) ?? false
        }
        collectionView.register(GalleryGridItemView.self, forItemWithIdentifier: GalleryGridItemView.reuseID)
        collectionView.register(GalleryGridFooterItem.self, forItemWithIdentifier: GalleryGridFooterItem.reuseID)

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateItemSize() {
        let insetWidth = gridLayout.sectionInset.left + gridLayout.sectionInset.right
        let availableWidth = max(bounds.width - insetWidth, preferredCardMinimumWidth)
        let columns: Int
        if let preferredColumnCount {
            columns = max(preferredColumnCount, 1)
        } else {
            columns = max(Int((availableWidth + gridLayout.minimumInteritemSpacing) / (preferredCardMinimumWidth + gridLayout.minimumInteritemSpacing)), 1)
        }
        let totalSpacing = CGFloat(columns - 1) * gridLayout.minimumInteritemSpacing
        let width = floor((availableWidth - totalSpacing) / CGFloat(columns))
        gridLayout.itemSize = NSSize(width: width, height: max(width / 0.74 + 76, 230))
        gridLayout.invalidateLayout()
    }

    private func syncSelection() {
        guard let selectedItemID,
              let index = items.firstIndex(where: { $0.id == selectedItemID }) else {
            isApplyingSelection = true
            collectionView.selectionIndexPaths = []
            isApplyingSelection = false
            return
        }
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
        isApplyingSelection = false
        refreshVisibleSelection()
    }

    private func refreshVisibleSelection() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? GalleryGridItemView,
                  items.indices.contains(indexPath.item) else { continue }
            item.applySelectionState(items[indexPath.item].id == selectedItemID)
        }
    }

    private func selectAdjacent(delta: Int) -> Bool {
        guard !items.isEmpty else { return false }
        let current = selectedItemID.flatMap { id in items.firstIndex { $0.id == id } }
            ?? collectionView.selectionIndexPaths.first?.item
            ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        guard next != current else { return true }
        selectedItemID = items[next].id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [IndexPath(item: next, section: 0)]
        isApplyingSelection = false
        collectionView.scrollToItems(at: [IndexPath(item: next, section: 0)], scrollPosition: .nearestVerticalEdge)
        refreshVisibleSelection()
        onSelect?(items[next])
        return true
    }
}

final class GalleryGridCollectionView: NSCollectionView {
    var arrowKeyHandler: ((Int) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let noModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        if noModifiers {
            switch event.keyCode {
            case 123, 126:
                if arrowKeyHandler?(-1) == true { return }
            case 124, 125:
                if arrowKeyHandler?(1) == true { return }
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class GalleryGridItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("GalleryGridItemView")

    private let coverView = GalleryRemoteImageView()
    private let kindLabel = GalleryPillLabel()
    private let imageCountLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let pageCountLabel = NSTextField(labelWithString: "")
    private let favoriteIcon = NSImageView()
    private let cachedIcon = NSImageView()
    private let backgroundView = NSView()

    override func loadView() {
        view = NSView()
        setupView()
    }

    func configure(item: GalleryItem, isSelected: Bool, isFavorite: Bool, isCached: Bool) {
        coverView.setImage(url: item.coverURL, maxPixelSize: 360)
        kindLabel.configure(kind: item.kind)
        imageCountLabel.stringValue = "\(item.imageCount)"
        titleLabel.stringValue = item.title
        pageCountLabel.stringValue = "\(item.pageCount) 页"
        favoriteIcon.isHidden = !isFavorite
        cachedIcon.isHidden = !isCached
        applySelectionState(isSelected)
    }

    func applySelectionState(_ isSelected: Bool) {
        backgroundView.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : NSColor.clear.cgColor
        backgroundView.layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        backgroundView.layer?.borderWidth = isSelected ? 1.5 : 0
    }

    private func setupView() {
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 8
        backgroundView.layer?.masksToBounds = true

        coverView.mode = .aspectFill
        coverView.cornerRadius = 5

        imageCountLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        imageCountLabel.textColor = .secondaryLabelColor

        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2

        pageCountLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pageCountLabel.textColor = .secondaryLabelColor

        favoriteIcon.image = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: nil)
        favoriteIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        favoriteIcon.contentTintColor = .secondaryLabelColor
        cachedIcon.image = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil)
        cachedIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        cachedIcon.contentTintColor = .secondaryLabelColor

        let topMeta = NSStackView(views: [kindLabel, imageCountLabel])
        topMeta.orientation = .horizontal
        topMeta.alignment = .centerY
        topMeta.spacing = 5

        let spacer = NSView()
        let bottomMeta = NSStackView(views: [pageCountLabel, spacer, favoriteIcon, cachedIcon])
        bottomMeta.orientation = .horizontal
        bottomMeta.alignment = .centerY
        bottomMeta.spacing = 8

        let stack = NSStackView(views: [coverView, topMeta, titleLabel, bottomMeta])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        view.addSubview(backgroundView)
        backgroundView.addSubview(stack)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        coverView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: backgroundView.bottomAnchor, constant: -8),
            coverView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            coverView.heightAnchor.constraint(equalTo: coverView.widthAnchor, multiplier: 1 / 0.74)
        ])
    }
}

@MainActor
final class GalleryGridFooterItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("GalleryGridFooterItem")

    private let progress = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        setupView()
    }

    func configure(isRefreshing: Bool, canLoadMore: Bool, hasItems: Bool) {
        progress.isHidden = !isRefreshing
        if isRefreshing {
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
}
