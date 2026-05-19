import AppKit
import Nuke

@MainActor
final class GalleryGridContainerView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((GalleryItem) -> Void)?
    var onNeedsMore: (() -> Void)?
    var contextMenuProvider: ((GalleryItem) -> NSMenu?)?

    private let scrollView = NSScrollView()
    private let collectionView = GalleryGridCollectionView()
    private let gridLayout = WorkspaceThumbnailWaterfallLayout()
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
    private var lastAppliedItemIDs: [GalleryItem.ID] = []
    private var lastShowsFooter = false
    private var lastLayoutWidth: CGFloat = 0
    private var aspectRatiosByItemID: [GalleryItem.ID: CGFloat] = [:]
    private var scrollObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
    }

    override func layout() {
        super.layout()
        updateItemSize()
    }

    func focus() {
        window?.makeFirstResponderUnlessDescendantIsFirstResponder(collectionView)
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
        let previousSelectedItemID = self.selectedItemID
        let previousBadgeSignature = visibleBadgeSignature()
        let previousFooterState = (self.isRefreshing, self.canLoadMore)
        let nextItemIDs = items.map(\.id)
        let contentChanged = nextItemIDs != lastAppliedItemIDs || showsFooter != lastShowsFooter
        let nextItemIDSet = Set(nextItemIDs)

        self.items = items
        self.selectedItemID = selectedItemID
        self.preferredColumnCount = preferredColumnCount
        self.preferredCardMinimumWidth = preferredCardMinimumWidth
        self.showsFooter = showsFooter
        self.isRefreshing = isRefreshing
        self.canLoadMore = canLoadMore
        self.isFavorite = isFavorite
        self.isCached = isCached
        aspectRatiosByItemID = aspectRatiosByItemID.filter { nextItemIDSet.contains($0.key) }

        let itemSizeChanged = updateItemSize()
        if contentChanged {
            lastAppliedItemIDs = nextItemIDs
            lastShowsFooter = showsFooter
            collectionView.reloadData()
        } else {
            let badgeChanged = previousBadgeSignature != visibleBadgeSignature()
            let footerChanged = previousFooterState != (isRefreshing, canLoadMore)
            if badgeChanged || footerChanged {
                reloadVisibleItems()
            } else if itemSizeChanged || previousSelectedItemID != selectedItemID {
                refreshVisibleSelection()
            }
        }
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
            isCached: isCached(galleryItem),
            onImageAspectRatioResolved: { [weak self] ratio in
                self?.updateAspectRatio(ratio, for: galleryItem.id)
            }
        )
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard items.indices.contains(indexPath.item) else { return nil }
        return items[indexPath.item].detailURL as NSURL
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
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = collectionView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.collectionView.clearVisibleHoverState()
                self?.updateItemSize()
            }
        }

        gridLayout.columnSpacing = 8
        gridLayout.rowSpacing = 10
        gridLayout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        gridLayout.aspectRatioProvider = { [weak self] indexPath in
            guard let self else { return 16.0 / 9.0 }
            guard indexPath.item < self.items.count else { return 3.0 }
            return self.aspectRatiosByItemID[self.items[indexPath.item].id] ?? 0.74
        }

        collectionView.collectionViewLayout = gridLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: true)
        collectionView.arrowKeyHandler = { [weak self] delta in
            self?.selectAdjacent(delta: delta) ?? false
        }
        collectionView.contextMenuProvider = { [weak self] indexPath in
            self?.makeContextMenu(for: indexPath)
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

    @discardableResult
    private func updateItemSize() -> Bool {
        let visibleWidth = scrollView.contentView.bounds.width > 0 ? scrollView.contentView.bounds.width : bounds.width
        let widthChanged = abs(visibleWidth - lastLayoutWidth) > 0.5
        let columnPreferenceChanged = gridLayout.preferredColumnCount != preferredColumnCount
        let cardWidthPreferenceChanged = abs(gridLayout.preferredCardMinimumWidth - preferredCardMinimumWidth) > 0.001
        guard widthChanged || columnPreferenceChanged || cardWidthPreferenceChanged else { return false }
        lastLayoutWidth = visibleWidth
        gridLayout.preferredColumnCount = preferredColumnCount
        gridLayout.preferredCardMinimumWidth = preferredCardMinimumWidth
        gridLayout.invalidateLayout()
        return true
    }

    private func updateAspectRatio(_ ratio: CGFloat, for itemID: GalleryItem.ID) {
        guard ratio.isFinite, ratio > 0 else { return }
        let clampedRatio = max(gridLayout.minAspectRatio, min(gridLayout.maxAspectRatio, ratio))
        guard abs((aspectRatiosByItemID[itemID] ?? 0.74) - clampedRatio) > 0.01 else { return }
        aspectRatiosByItemID[itemID] = clampedRatio
        collectionView.collectionViewLayout?.invalidateLayout()
    }

    private struct BadgeSignature: Equatable {
        let itemID: GalleryItem.ID
        let isFavorite: Bool
        let isCached: Bool
    }

    private func visibleBadgeSignature() -> [IndexPath: BadgeSignature] {
        Dictionary(uniqueKeysWithValues: collectionView.indexPathsForVisibleItems().compactMap { indexPath in
            guard items.indices.contains(indexPath.item) else { return nil }
            let item = items[indexPath.item]
            return (
                indexPath,
                BadgeSignature(itemID: item.id, isFavorite: isFavorite(item), isCached: isCached(item))
            )
        })
    }

    private func reloadVisibleItems() {
        let visibleItems = Set(collectionView.indexPathsForVisibleItems().filter { indexPath in
            indexPath.item < items.count + (showsFooter ? 1 : 0)
        })
        guard !visibleItems.isEmpty else { return }
        collectionView.reloadItems(at: visibleItems)
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

    private func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        guard let indexPath,
              items.indices.contains(indexPath.item) else { return nil }

        let item = items[indexPath.item]
        selectedItemID = item.id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [indexPath]
        isApplyingSelection = false
        refreshVisibleSelection()
        onSelect?(item)
        return contextMenuProvider?(item)
    }
}

final class GalleryGridCollectionView: NSCollectionView {
    var arrowKeyHandler: ((Int) -> Bool)?
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    private var hoverTrackingArea: NSTrackingArea?
    private var lastHoveredIndexPath: IndexPath?

    override var acceptsFirstResponder: Bool { true }

    override func accessibilityLabel() -> String? {
        "4KHD Gallery Grid"
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        hoverTrackingArea = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hoveredIndexPath = indexPathForItem(at: point)
        if hoveredIndexPath != lastHoveredIndexPath {
            lastHoveredIndexPath = hoveredIndexPath
            syncVisibleHoverState(windowLocation: event.locationInWindow)
        }
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        lastHoveredIndexPath = nil
        clearVisibleHoverState()
        super.mouseExited(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        return contextMenuProvider?(indexPathForItem(at: point))
    }

    override func keyDown(with event: NSEvent) {
        let handled = WorkspaceKeyboardHandler.keyDown(
            event,
            context: WorkspaceKeyboardContext(stepSelection: arrowKeyHandler)
        )
        if handled {
            return
        }
        super.keyDown(with: event)
    }

    override func viewWillStartLiveResize() {
        workspaceWillStartLiveResize()
        super.viewWillStartLiveResize()
    }

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        syncVisibleHoverState(windowLocation: window?.mouseLocationOutsideOfEventStream)
        super.viewDidEndLiveResize()
    }

    func clearVisibleHoverState() {
        lastHoveredIndexPath = nil
        for item in visibleItems() {
            (item as? GalleryGridItemView)?.clearHoverState()
        }
    }

    private func syncVisibleHoverState(windowLocation: NSPoint?) {
        for item in visibleItems() {
            (item as? GalleryGridItemView)?.syncHoverState(windowLocation: windowLocation)
        }
    }
}

extension GalleryGridCollectionView: WorkspaceLiveResizeScrollerHiding {}

@MainActor
final class GalleryGridItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("GalleryGridItemView")

    private let cardView = WorkspaceThumbnailGridCardView()
    private var imageTask: ImageTask?
    private var representedID: GalleryItem.ID?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        setupView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        representedID = nil
        cardView.resetForReuse()
    }

    func configure(
        item: GalleryItem,
        isSelected: Bool,
        isFavorite: Bool,
        isCached: Bool,
        onImageAspectRatioResolved: @escaping (CGFloat) -> Void
    ) {
        representedID = item.id
        cardView.setText(
            title: item.title,
            metadata: metadataText(for: item, isFavorite: isFavorite, isCached: isCached)
        )
        applySelectionState(isSelected)
        loadCover(for: item, onImageAspectRatioResolved: onImageAspectRatioResolved)
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

    private func setupView() {
        view.addSubview(cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadCover(
        for item: GalleryItem,
        onImageAspectRatioResolved: @escaping (CGFloat) -> Void
    ) {
        imageTask?.cancel()
        cardView.setImage(nil)
        cardView.setMissingVisible(false)
        guard let coverURL = item.coverURL else {
            cardView.setPlaceholder("暂无缩略图", isVisible: true)
            return
        }

        cardView.setPlaceholder("加载中...", isVisible: true)
        let request = RemoteImagePipeline.shared.request(
            for: coverURL,
            priority: .low,
            maxPixelSize: 512,
            configureURLRequest: GalleryRequestFactory.configureImageRequest
        )
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.representedID == item.id else { return }
                if let image {
                    self.cardView.setImage(image)
                    if image.size.width > 0, image.size.height > 0 {
                        onImageAspectRatioResolved(image.size.width / image.size.height)
                    }
                } else {
                    self.cardView.setPlaceholder("缩略图不可用", isVisible: true)
                }
            }
        }
    }

    private func metadataText(for item: GalleryItem, isFavorite: Bool, isCached: Bool) -> String {
        var parts: [String] = []
        if isFavorite {
            parts.append("已收藏")
        }
        if isCached {
            parts.append("已缓存")
        }
        return parts.joined(separator: " · ")
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
