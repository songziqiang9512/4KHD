import AppKit
import Nuke

@MainActor
final class GalleryGridContainerView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((GalleryItem) -> Void)?
    var onOpenDetail: (() -> Void)?
    var onNeedsMore: (() -> Void)?
    var onEscape: (() -> Bool)?
    var onRetry: (() -> Void)?
    var contextMenuProvider: ((GalleryItem) -> NSMenu?)?

    private let scrollView = NSScrollView()
    private let collectionView = GalleryGridCollectionView()
    private let gridLayout = WorkspaceThumbnailWaterfallLayout()
    private var items: [GalleryItem] = []
    private var selectedItemID: GalleryItem.ID?
    private var previousSelectedItemID: GalleryItem.ID?
    private var showsFooter = false
    private var isRefreshing = false
    private var errorMessage: String?
    private var canLoadMore = false
    private var minimumColumnCount: Int?
    private var maximumColumnCount: Int?
    private var preferredCardMinimumWidth: CGFloat = 160
    private var searchQuery: String?
    private var isFavorite: (GalleryItem) -> Bool = { _ in false }
    private var isCached: (GalleryItem) -> Bool = { _ in false }
    private var isApplyingSelection = false
    private var lastAppliedItemIDs: [GalleryItem.ID] = []
    private var lastShowsFooter = false
    private var lastLayoutWidth: CGFloat = 0
    private var aspectRatiosByItemID: [GalleryItem.ID: CGFloat] = [:]
    private let thumbnailPrefetchController = WorkspaceThumbnailPrefetchController<GalleryItem.ID>()
    private let aspectRatioLayoutQueue = WorkspaceCoalescingQueue(
        name: "GalleryGridAspectRatioLayout",
        interval: 0.03,
        maxInterval: 0.1
    )
    nonisolated(unsafe) private var scrollObserver: NSObjectProtocol?

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
        scheduleThumbnailPrefetch()
    }

    func focus() {
        window?.makeFirstResponderUnlessDescendantIsFirstResponder(collectionView)
    }

    func firstVisibleItemID() -> GalleryItem.ID? {
        collectionView.indexPathsForVisibleItems()
            .filter { items.indices.contains($0.item) }
            .min { $0.item < $1.item }
            .map { items[$0.item].id }
    }

    func scrollItemIntoViewIfNeeded(withID itemID: GalleryItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        scrollItemIntoViewIfNeeded(at: IndexPath(item: index, section: 0))
    }

    func update(
        items: [GalleryItem],
        selectedItemID: GalleryItem.ID?,
        searchQuery: String?,
        minimumColumnCount: Int?,
        maximumColumnCount: Int?,
        preferredCardMinimumWidth: CGFloat,
        showsFooter: Bool,
        isRefreshing: Bool,
        errorMessage: String?,
        canLoadMore: Bool,
        isFavorite: @escaping (GalleryItem) -> Bool,
        isCached: @escaping (GalleryItem) -> Bool
    ) {
        let previousSelectedItemID = self.selectedItemID
        let previousBadgeSignature = visibleBadgeSignature()
        let previousFooterState = (self.isRefreshing, self.errorMessage, self.canLoadMore)
        let previousItemIDs = lastAppliedItemIDs
        let previousShowsFooter = lastShowsFooter
        let nextItemIDs = items.map(\.id)
        let contentChanged = nextItemIDs != previousItemIDs || showsFooter != previousShowsFooter
        let nextItemIDSet = Set(nextItemIDs)

        self.items = items
        self.previousSelectedItemID = self.selectedItemID
        self.selectedItemID = selectedItemID
        self.searchQuery = searchQuery
        self.minimumColumnCount = minimumColumnCount
        self.maximumColumnCount = maximumColumnCount
        self.preferredCardMinimumWidth = preferredCardMinimumWidth
        self.showsFooter = showsFooter
        self.isRefreshing = isRefreshing
        self.errorMessage = errorMessage
        self.canLoadMore = canLoadMore
        self.isFavorite = isFavorite
        self.isCached = isCached
        aspectRatiosByItemID = aspectRatiosByItemID.filter { nextItemIDSet.contains($0.key) }

        let itemSizeChanged = updateItemSize()
        if contentChanged {
            lastAppliedItemIDs = nextItemIDs
            lastShowsFooter = showsFooter
            thumbnailPrefetchController.reset()
            applyContentChange(
                previousItemIDs: previousItemIDs,
                previousShowsFooter: previousShowsFooter,
                nextItemIDs: nextItemIDs,
                showsFooter: showsFooter
            )
            prefetchInitialThumbnails()
        } else {
            let badgeChanged = previousBadgeSignature != visibleBadgeSignature()
            let footerChanged = previousFooterState != (isRefreshing, errorMessage, canLoadMore)
            if footerChanged {
                reloadFooterItem()
            } else if badgeChanged {
                reloadVisibleItems()
            } else if itemSizeChanged || previousSelectedItemID != selectedItemID {
                refreshVisibleSelection()
            }
        }
        syncSelection()
        scheduleThumbnailPrefetch()
    }

    /// Lightweight update that only re-evaluates badge/footer/selection state without touching item layout.
    /// Precondition: the item array itself is unchanged; only metadata (favorites, cache, refresh, selection) may differ.
    func refreshMetadata(
        selectedItemID: GalleryItem.ID?,
        isFavorite: @escaping (GalleryItem) -> Bool,
        isCached: @escaping (GalleryItem) -> Bool,
        isRefreshing: Bool,
        errorMessage: String?,
        canLoadMore: Bool,
        showsFooter: Bool
    ) {
        let previousBadgeSignature = visibleBadgeSignature()
        let previousFooterState = (self.isRefreshing, self.errorMessage, self.canLoadMore)
        let previousSelectedItemID = self.selectedItemID

        self.selectedItemID = selectedItemID
        self.previousSelectedItemID = previousSelectedItemID
        self.isFavorite = isFavorite
        self.isCached = isCached
        self.isRefreshing = isRefreshing
        self.errorMessage = errorMessage
        self.canLoadMore = canLoadMore
        self.showsFooter = showsFooter

        let badgeChanged = previousBadgeSignature != visibleBadgeSignature()
        let footerChanged = previousFooterState != (isRefreshing, errorMessage, canLoadMore)
        let selectionChanged = previousSelectedItemID != selectedItemID

        if footerChanged {
            reloadFooterItem()
        } else if badgeChanged {
            reloadVisibleItems()
        } else if selectionChanged {
            refreshVisibleSelection()
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
            item.configure(
                isRefreshing: isRefreshing,
                errorMessage: errorMessage,
                canLoadMore: canLoadMore,
                hasItems: !items.isEmpty
            )
            item.onRetry = { [weak self] in
                if self?.errorMessage != nil {
                    self?.onRetry?()
                } else {
                    self?.onNeedsMore?()
                }
            }
            return item
        }

        let item = collectionView.makeItem(
            withIdentifier: GalleryGridItemView.reuseID,
            for: indexPath
        ) as? GalleryGridItemView ?? GalleryGridItemView()
        item.thumbnailMaxPixelSize = thumbnailMaxPixelSize
        let galleryItem = items[indexPath.item]
        item.configure(
            item: galleryItem,
            isSelected: galleryItem.id == selectedItemID,
            searchQuery: searchQuery,
            isFavorite: isFavorite(galleryItem),
            isCached: isCached(galleryItem),
            onImageAspectRatioResolved: { [weak self] ratio in
                self?.updateAspectRatio(ratio, for: galleryItem.id, knownAspectRatio: galleryItem.coverAspectRatio.map { CGFloat($0) })
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
        previousSelectedItemID = selectedItemID
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
                self?.updateItemSize()
                self?.scheduleThumbnailPrefetch()
            }
        }

        gridLayout.columnSpacing = 8
        gridLayout.rowSpacing = 10
        gridLayout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        gridLayout.aspectRatioProvider = { [weak self] indexPath in
            guard let self else { return 16.0 / 9.0 }
            guard indexPath.item < self.items.count else { return 3.0 }
            let item = self.items[indexPath.item]
            if let ratio = self.aspectRatiosByItemID[item.id] {
                return ratio
            }
            if let ratio = item.coverAspectRatio, ratio.isFinite, ratio > 0 {
                return CGFloat(ratio)
            }
            return 0.74
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
        collectionView.keyboardContext = WorkspaceKeyboardContext(
            stepSelection: collectionView.arrowKeyHandler,
            onEscape: { [weak self] in self?.onEscape?() ?? false },
            onEnter: { [weak self] in
                guard let self, let id = self.selectedItemID,
                      let indexPath = self.items.firstIndex(where: { $0.id == id }) else { return false }
                self.openDetail(for: IndexPath(item: indexPath, section: 0))
                return true
            }
        )
        collectionView.contextMenuProvider = { [weak self] indexPath in
            self?.makeContextMenu(for: indexPath)
        }
        collectionView.doubleClickHandler = { [weak self] indexPath in
            self?.openDetail(for: indexPath)
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
        let minimumColumnPreferenceChanged = gridLayout.minimumColumnCount != minimumColumnCount
        let columnPreferenceChanged = gridLayout.maximumColumnCount != maximumColumnCount
        let cardWidthPreferenceChanged = abs(gridLayout.preferredCardMinimumWidth - preferredCardMinimumWidth) > 0.001
        guard widthChanged || minimumColumnPreferenceChanged || columnPreferenceChanged || cardWidthPreferenceChanged else { return false }
        lastLayoutWidth = visibleWidth
        gridLayout.minimumColumnCount = minimumColumnCount
        gridLayout.maximumColumnCount = maximumColumnCount
        gridLayout.preferredCardMinimumWidth = preferredCardMinimumWidth
        performWithoutCollectionAnimation {
            gridLayout.invalidateLayout()
        }
        return true
    }

    private func updateAspectRatio(_ ratio: CGFloat, for itemID: GalleryItem.ID, knownAspectRatio: CGFloat?) {
        guard ratio.isFinite, ratio > 0 else { return }
        let clampedRatio = max(gridLayout.minAspectRatio, min(gridLayout.maxAspectRatio, ratio))
        let currentRatio = aspectRatiosByItemID[itemID]
            ?? knownAspectRatio
            ?? 0.74
        let threshold = knownAspectRatio != nil ? 0.1 : 0.01
        guard abs(currentRatio - clampedRatio) > threshold else { return }
        aspectRatiosByItemID[itemID] = clampedRatio
        aspectRatioLayoutQueue.add(id: "invalidate-layout") { [weak self] in
            self?.performWithoutCollectionAnimation {
                self?.gridLayout.invalidateCachedFrames()
            }
        }
    }

    private func prefetchInitialThumbnails() {
        thumbnailPrefetchController.prefetchInitial(
            itemCount: items.count,
            itemID: { [weak self] index in self?.itemID(at: index) },
            request: { [weak self] index in self?.thumbnailRequest(at: index) }
        )
    }

    private func scheduleThumbnailPrefetch() {
        thumbnailPrefetchController.schedule(
            scrollView: scrollView,
            layout: gridLayout,
            itemCount: items.count,
            itemID: { [weak self] index in self?.itemID(at: index) },
            request: { [weak self] index in self?.thumbnailRequest(at: index) }
        )
    }

    private func itemID(at index: Int) -> GalleryItem.ID? {
        guard items.indices.contains(index) else { return nil }
        return items[index].id
    }

    private var thumbnailMaxPixelSize: CGFloat {
        let width = gridLayout.resolvedColumnWidth
        guard width > 0 else { return 512 }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let requested = width * scale
        let buckets: [CGFloat] = [512, 768, 1024, 1536]
        return buckets.first { $0 >= requested } ?? 1536
    }

    private func thumbnailRequest(at index: Int) -> ImageRequest? {
        guard items.indices.contains(index),
              let coverURL = items[index].coverURL else { return nil }
        return RemoteImagePipeline.shared.request(
            for: coverURL,
            priority: .veryLow,
            maxPixelSize: thumbnailMaxPixelSize,
            configureURLRequest: GalleryRequestFactory.configureImageRequest
        )
    }

    private func applyContentChange(
        previousItemIDs: [GalleryItem.ID],
        previousShowsFooter: Bool,
        nextItemIDs: [GalleryItem.ID],
        showsFooter: Bool
    ) {
        let isAppendOnly = nextItemIDs.count > previousItemIDs.count
            && previousShowsFooter == showsFooter
            && Array(nextItemIDs.prefix(previousItemIDs.count)) == previousItemIDs

        guard isAppendOnly else {
            performWithoutCollectionAnimation {
                // 内容替换：强制布局全量重建，避免 append 增量路径把新内容套进旧卡片 frame。
                gridLayout.invalidateLayoutForContentReplacement()
                collectionView.reloadData()
            }
            return
        }

        let oldItemCount = previousItemIDs.count
        performWithoutCollectionAnimation {
            collectionView.performBatchUpdates {
                if oldItemCount < nextItemIDs.count {
                    let indexPaths = Set((oldItemCount ..< nextItemIDs.count).map { IndexPath(item: $0, section: 0) })
                    collectionView.insertItems(at: indexPaths)
                }
            }
        }
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
        performWithoutCollectionAnimation {
            collectionView.reloadItems(at: visibleItems)
        }
    }

    private func reloadFooterItem() {
        guard showsFooter else { return }
        let footerIndexPath = IndexPath(item: items.count, section: 0)
        guard collectionView.indexPathsForVisibleItems().contains(footerIndexPath) else { return }
        performWithoutCollectionAnimation {
            collectionView.reloadItems(at: [footerIndexPath])
        }
    }

    private func performWithoutCollectionAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            updates()
        }
        CATransaction.commit()
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
        let previousID = previousSelectedItemID
        let currentID = selectedItemID
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? GalleryGridItemView,
                  items.indices.contains(indexPath.item) else { continue }
            let itemID = items[indexPath.item].id
            let wasSelected = itemID == previousID
            let isSelected = itemID == currentID
            guard wasSelected != isSelected else { continue }
            item.applySelectionState(isSelected)
        }
        previousSelectedItemID = selectedItemID
    }

    private func scrollItemIntoViewIfNeeded(at indexPath: IndexPath) {
        guard items.indices.contains(indexPath.item) else { return }
        guard let attributes = gridLayout.layoutAttributesForItem(at: indexPath) else {
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
            return
        }
        let frame = attributes.frame
        let visible = scrollView.contentView.bounds
        guard frame.isValidScrollRect,
              visible.isValidScrollRect,
              gridLayout.collectionViewContentSize.isValidScrollSize else {
            return
        }
        guard !visible.contains(frame) else { return }
        let minY = -scrollView.contentInsets.top
        let contentHeight = gridLayout.collectionViewContentSize.height
        let maxY = max(minY, contentHeight - visible.height + scrollView.contentInsets.bottom)
        let targetY = frame.minY < visible.minY ? frame.minY - 4 : frame.maxY - visible.height + 4
        let y = min(max(minY, targetY), maxY)
        guard y.isFinite, y < 100_000 else { return }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func selectAdjacent(delta: Int) -> Bool {
        guard !items.isEmpty else { return false }
        let current = selectedItemID.flatMap { id in items.firstIndex { $0.id == id } }
            ?? collectionView.selectionIndexPaths.first?.item
            ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        guard next != current else { return true }
        previousSelectedItemID = selectedItemID
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
        previousSelectedItemID = selectedItemID
        selectedItemID = item.id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [indexPath]
        isApplyingSelection = false
        refreshVisibleSelection()
        onSelect?(item)
        return contextMenuProvider?(item)
    }

    private func openDetail(for indexPath: IndexPath) {
        guard items.indices.contains(indexPath.item) else { return }
        let item = items[indexPath.item]
        previousSelectedItemID = selectedItemID
        selectedItemID = item.id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [indexPath]
        isApplyingSelection = false
        refreshVisibleSelection()
        onSelect?(item)
        onOpenDetail?()
    }
}

private extension NSRect {
    var isValidScrollRect: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.isValidScrollSize
            && size.width >= 0
            && size.height >= 0
    }
}

private extension NSSize {
    var isValidScrollSize: Bool {
        width.isFinite && height.isFinite
    }
}

final class GalleryGridCollectionView: WorkspaceCollectionView {
    var arrowKeyHandler: ((Int) -> Bool)?
    var doubleClickHandler: ((IndexPath) -> Void)?

    override func accessibilityLabel() -> String? {
        "4KHD 图片网格"
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedIndexPath = indexPathForItem(at: point)
        super.mouseDown(with: event)
        if event.clickCount == 2, let clickedIndexPath {
            doubleClickHandler?(clickedIndexPath)
        }
    }

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        clearHoverOnVisibleItems()
        super.viewDidEndLiveResize()
    }

    override func clearHoverOnVisibleItems() {
        lastHoveredIndexPath = nil
        for item in visibleItems() {
            (item as? GalleryGridItemView)?.clearHoverState()
        }
    }

    override func syncHoverOnVisibleItems(windowLocation: NSPoint?) {
        for item in visibleItems() {
            (item as? GalleryGridItemView)?.syncHoverState(windowLocation: windowLocation)
        }
    }
}

@MainActor
final class GalleryGridItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("GalleryGridItemView")

    private let cardView = WorkspaceThumbnailGridCardView()
    private var imageTask: RemoteImageLoadTask?
    private var representedID: GalleryItem.ID?
    private var currentCoverURL: URL?
    var thumbnailMaxPixelSize: CGFloat = 512

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
        currentCoverURL = nil
        cardView.resetForReuse()
    }

    func configure(
        item: GalleryItem,
        isSelected: Bool,
        searchQuery: String?,
        isFavorite: Bool,
        isCached: Bool,
        onImageAspectRatioResolved: @escaping (CGFloat) -> Void
    ) {
        let idChanged = representedID != item.id
        let urlChanged = currentCoverURL != item.coverURL
        representedID = item.id
        cardView.setText(
            title: item.title,
            metadata: metadataText(for: item, isFavorite: isFavorite, isCached: isCached),
            highlightQuery: searchQuery
        )
        applySelectionState(isSelected)
        if idChanged || urlChanged {
            loadCover(for: item, onImageAspectRatioResolved: onImageAspectRatioResolved)
        } else if let ratio = item.coverAspectRatio.map({ CGFloat($0) }), ratio > 0 {
            onImageAspectRatioResolved(ratio)
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
        currentCoverURL = item.coverURL
        guard let coverURL = item.coverURL else {
            cardView.setPlaceholder("暂无缩略图", isVisible: true)
            return
        }

        let request = RemoteImagePipeline.shared.request(
            for: coverURL,
            priority: .normal,
            maxPixelSize: thumbnailMaxPixelSize,
            configureURLRequest: GalleryRequestFactory.configureImageRequest
        )
        if let cached = RemoteImagePipeline.shared.cachedImage(with: request) {
            cardView.setImage(cached, animated: false)
            if cached.size.width > 0, cached.size.height > 0 {
                onImageAspectRatioResolved(cached.size.width / cached.size.height)
            }
            return
        }

        cardView.setPlaceholder("加载中...", isVisible: true)
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
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
    var onRetry: (() -> Void)?

    override func loadView() {
        view = NSView()
        setupView()
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

        let click = NSClickGestureRecognizer(target: self, action: #selector(didClick))
        view.addGestureRecognizer(click)
    }
}
