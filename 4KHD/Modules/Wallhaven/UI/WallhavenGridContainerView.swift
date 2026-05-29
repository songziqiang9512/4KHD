import AppKit
import Nuke

@MainActor
final class WallhavenGridContainerView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((Wallpaper) -> Void)?
    var onOpenDetail: (() -> Void)?
    var onNeedsMore: (() -> Void)?
    var onEscape: (() -> Bool)?
    var onRetry: (() -> Void)?
    var contextMenuProvider: ((Wallpaper) -> NSMenu?)?

    private let scrollView = NSScrollView()
    private let collectionView = WallhavenGridCollectionView()
    private let gridLayout = WorkspaceThumbnailWaterfallLayout()
    private var wallpapers: [Wallpaper] = []
    private var selectedWallpaperID: Wallpaper.ID?
    private var searchQuery: String?
    private var showsFooter = false
    private var isRefreshing = false
    private var errorMessage: String?
    private var canLoadMore = false
    private var minimumColumnCount: Int?
    private var maximumColumnCount: Int?
    private var preferredCardMinimumWidth: CGFloat = 136
    private var isApplyingSelection = false
    private var lastAppliedIDs: [Wallpaper.ID] = []
    private var lastShowsFooter = false
    private var lastLayoutWidth: CGFloat = 0
    private var aspectRatiosByItemID: [Wallpaper.ID: CGFloat] = [:]
    private let thumbnailPrefetchController = WorkspaceThumbnailPrefetchController<Wallpaper.ID>()
    private let aspectRatioLayoutQueue = WorkspaceCoalescingQueue(
        name: "WallhavenGridAspectRatio", interval: 0.03, maxInterval: 0.1
    )
    private var scrollObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }

    override func layout() {
        super.layout()
        updateItemSize()
        scheduleThumbnailPrefetch()
    }

    func focus() { window?.makeFirstResponderUnlessDescendantIsFirstResponder(collectionView) }

    func firstVisibleItemID() -> Wallpaper.ID? {
        collectionView.indexPathsForVisibleItems()
            .filter { wallpapers.indices.contains($0.item) }
            .min { $0.item < $1.item }
            .map { wallpapers[$0.item].id }
    }

    func scrollItemIntoViewIfNeeded(withID itemID: Wallpaper.ID) {
        guard let index = wallpapers.firstIndex(where: { $0.id == itemID }) else { return }
        scrollItemIntoViewIfNeeded(at: IndexPath(item: index, section: 0))
    }

    func update(
        wallpapers: [Wallpaper],
        selectedWallpaperID: Wallpaper.ID?,
        searchQuery: String?,
        minimumColumnCount: Int?,
        maximumColumnCount: Int?,
        preferredCardMinimumWidth: CGFloat,
        showsFooter: Bool,
        isRefreshing: Bool,
        errorMessage: String?,
        canLoadMore: Bool
    ) {
        let previousItemIDs = lastAppliedIDs
        let previousShowsFooter = lastShowsFooter
        let nextItemIDs = wallpapers.map(\.id)
        let contentChanged = nextItemIDs != previousItemIDs || showsFooter != previousShowsFooter
        self.wallpapers = wallpapers
        self.selectedWallpaperID = selectedWallpaperID
        self.searchQuery = searchQuery
        self.minimumColumnCount = minimumColumnCount
        self.maximumColumnCount = maximumColumnCount
        self.preferredCardMinimumWidth = preferredCardMinimumWidth
        self.showsFooter = showsFooter
        self.isRefreshing = isRefreshing
        self.errorMessage = errorMessage
        self.canLoadMore = canLoadMore

        let itemSizeChanged = updateItemSize()
        if contentChanged {
            lastAppliedIDs = nextItemIDs
            lastShowsFooter = showsFooter
            thumbnailPrefetchController.reset()
            applyContentChange(
                previousItemIDs: previousItemIDs,
                previousShowsFooter: previousShowsFooter,
                nextItemIDs: nextItemIDs,
                showsFooter: showsFooter
            )
            prefetchInitialThumbnails()
        } else if itemSizeChanged {
            refreshVisibleSelection()
        } else {
            refreshVisibleItems()
        }
        syncSelection()
        scheduleThumbnailPrefetch()
    }

    private func refreshVisibleItems() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            if indexPath.item >= wallpapers.count {
                guard let footer = collectionView.item(at: indexPath) as? WallhavenGridFooterItem else { continue }
                footer.configure(isRefreshing: isRefreshing, errorMessage: errorMessage, canLoadMore: canLoadMore, hasItems: !wallpapers.isEmpty)
                continue
            }
            guard indexPath.item < wallpapers.count,
                  let cell = collectionView.item(at: indexPath) as? WallhavenGridItemView else { continue }
            let wallpaper = wallpapers[indexPath.item]
            cell.configure(wallpaper: wallpaper, isSelected: wallpaper.id == selectedWallpaperID, searchQuery: searchQuery) { [weak self] ratio in
                self?.updateAspectRatio(ratio, for: wallpaper.id)
            }
        }
    }

    private func applyContentChange(
        previousItemIDs: [Wallpaper.ID],
        previousShowsFooter: Bool,
        nextItemIDs: [Wallpaper.ID],
        showsFooter: Bool
    ) {
        let isAppendOnly = nextItemIDs.count > previousItemIDs.count
            && previousShowsFooter == showsFooter
            && Array(nextItemIDs.prefix(previousItemIDs.count)) == previousItemIDs

        guard isAppendOnly else {
            performWithoutAnimation {
                gridLayout.invalidateLayout()
                collectionView.reloadData()
            }
            return
        }

        let oldItemCount = previousItemIDs.count
        performWithoutAnimation {
            collectionView.performBatchUpdates {
                let indexPaths = Set((oldItemCount..<nextItemIDs.count).map { IndexPath(item: $0, section: 0) })
                collectionView.insertItems(at: indexPaths)
            }
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        wallpapers.count + (showsFooter ? 1 : 0)
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        if indexPath.item >= wallpapers.count {
            let footer = collectionView.makeItem(withIdentifier: WallhavenGridFooterItem.reuseID, for: indexPath) as? WallhavenGridFooterItem ?? WallhavenGridFooterItem()
            footer.configure(isRefreshing: isRefreshing, errorMessage: errorMessage, canLoadMore: canLoadMore, hasItems: !wallpapers.isEmpty)
            footer.onRetry = { [weak self] in
                if self?.errorMessage != nil {
                    self?.onRetry?()
                } else {
                    self?.onNeedsMore?()
                }
            }
            return footer
        }
        let item = collectionView.makeItem(withIdentifier: WallhavenGridItemView.reuseID, for: indexPath) as? WallhavenGridItemView ?? WallhavenGridItemView()
        let wallpaper = wallpapers[indexPath.item]
        item.configure(wallpaper: wallpaper, isSelected: wallpaper.id == selectedWallpaperID, searchQuery: searchQuery) { [weak self] ratio in
            self?.updateAspectRatio(ratio, for: wallpaper.id)
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection, let indexPath = indexPaths.first, wallpapers.indices.contains(indexPath.item) else { return }
        let wallpaper = wallpapers[indexPath.item]
        selectedWallpaperID = wallpaper.id
        refreshVisibleSelection()
        onSelect?(wallpaper)
    }

    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        guard indexPath.item >= max(wallpapers.count - 3, 0) else { return }
        onNeedsMore?()
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard wallpapers.indices.contains(indexPath.item) else { return nil }
        return wallpapers[indexPath.item].sourcePageUrl as NSURL
    }

    private func setupView() {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.hasVerticalScroller = true
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = collectionView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateItemSize()
                self?.scheduleThumbnailPrefetch()
            }
        }

        gridLayout.columnSpacing = 8
        gridLayout.rowSpacing = 10
        gridLayout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        gridLayout.minAspectRatio = 0.15
        gridLayout.maxAspectRatio = 6.0
        gridLayout.aspectRatioProvider = { [weak self] indexPath in
            guard let self, indexPath.item < self.wallpapers.count else { return 16.0 / 9.0 }
            let wallpaper = self.wallpapers[indexPath.item]
            // API dimensions take priority over cached thumbnail ratios.
            if let ratio = wallpaper.aspectRatio.map({ CGFloat($0) }), ratio.isFinite, ratio > 0 { return ratio }
            if let ratio = self.aspectRatiosByItemID[wallpaper.id], ratio.isFinite, ratio > 0 { return ratio }
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
        collectionView.arrowKeyHandler = { [weak self] delta in self?.selectAdjacent(delta: delta) ?? false }
        collectionView.keyboardContext = WorkspaceKeyboardContext(
            stepSelection: { [weak self] delta in self?.selectAdjacent(delta: delta) ?? false },
            onEscape: { [weak self] in self?.onEscape?() ?? false },
            onEnter: { [weak self] in
                guard let self, let id = self.selectedWallpaperID, let indexPath = self.wallpapers.firstIndex(where: { $0.id == id }) else { return false }
                self.openDetail(for: IndexPath(item: indexPath, section: 0))
                return true
            }
        )
        collectionView.contextMenuProvider = { [weak self] indexPath in self?.makeContextMenu(for: indexPath) }
        collectionView.doubleClickHandler = { [weak self] indexPath in self?.openDetail(for: indexPath) }
        collectionView.register(WallhavenGridItemView.self, forItemWithIdentifier: WallhavenGridItemView.reuseID)
        collectionView.register(WallhavenGridFooterItem.self, forItemWithIdentifier: WallhavenGridFooterItem.reuseID)

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
        let prefChanged = gridLayout.preferredCardMinimumWidth != preferredCardMinimumWidth
            || gridLayout.minimumColumnCount != minimumColumnCount
            || gridLayout.maximumColumnCount != maximumColumnCount
        guard widthChanged || prefChanged else { return false }
        lastLayoutWidth = visibleWidth
        gridLayout.minimumColumnCount = minimumColumnCount
        gridLayout.maximumColumnCount = maximumColumnCount
        gridLayout.preferredCardMinimumWidth = preferredCardMinimumWidth
        performWithoutAnimation { gridLayout.invalidateLayout() }
        return true
    }

    private func updateAspectRatio(_ ratio: CGFloat, for itemID: Wallpaper.ID) {
        guard ratio.isFinite, ratio > 0 else { return }
        // If API dimensions already provide aspect ratio, don't override with thumbnail decode size.
        if let apiRatio = wallpapers.first(where: { $0.id == itemID })?.aspectRatio.map({ CGFloat($0) }),
           apiRatio > 0 { return }
        let clamped = max(gridLayout.minAspectRatio, min(gridLayout.maxAspectRatio, ratio))
        let current = aspectRatiosByItemID[itemID] ?? wallpapers.first(where: { $0.id == itemID })?.aspectRatio.map { CGFloat($0) } ?? 0.74
        let threshold: CGFloat = current < 0.5 ? 0.01 : 0.1
        guard abs(current - clamped) > threshold else { return }
        aspectRatiosByItemID[itemID] = clamped
        aspectRatioLayoutQueue.add(id: "invalidate") { [weak self] in
            self?.performWithoutAnimation { self?.collectionView.collectionViewLayout?.invalidateLayout() }
        }
    }

    private func prefetchInitialThumbnails() {
        thumbnailPrefetchController.prefetchInitial(
            itemCount: wallpapers.count,
            itemID: { [weak self] index in self?.wallpaperID(at: index) },
            request: { [weak self] index in self?.thumbnailRequest(at: index) }
        )
    }

    private func scheduleThumbnailPrefetch() {
        thumbnailPrefetchController.schedule(
            scrollView: scrollView,
            layout: gridLayout,
            itemCount: wallpapers.count,
            itemID: { [weak self] index in self?.wallpaperID(at: index) },
            request: { [weak self] index in self?.thumbnailRequest(at: index) }
        )
    }

    private func wallpaperID(at index: Int) -> Wallpaper.ID? {
        guard wallpapers.indices.contains(index) else { return nil }
        return wallpapers[index].id
    }

    private func thumbnailRequest(at index: Int) -> ImageRequest? {
        guard wallpapers.indices.contains(index),
              let thumbURL = wallpapers[index].thumbnailUrl else { return nil }
        return RemoteImagePipeline.shared.request(
            for: thumbURL,
            priority: .veryLow,
            maxPixelSize: 512,
            configureURLRequest: WallhavenRequestFactory.configureImageRequest
        )
    }

    private func syncSelection() {
        guard let selectedWallpaperID, let index = wallpapers.firstIndex(where: { $0.id == selectedWallpaperID }) else {
            isApplyingSelection = true; collectionView.selectionIndexPaths = []; isApplyingSelection = false; return
        }
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
        isApplyingSelection = false
        refreshVisibleSelection()
    }

    private func refreshVisibleSelection() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? WallhavenGridItemView, wallpapers.indices.contains(indexPath.item) else { continue }
            let id = wallpapers[indexPath.item].id
            item.applySelectionState(id == selectedWallpaperID)
        }
    }

    private func scrollItemIntoViewIfNeeded(at indexPath: IndexPath) {
        guard wallpapers.indices.contains(indexPath.item) else { return }
        guard let attributes = gridLayout.layoutAttributesForItem(at: indexPath) else {
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
            return
        }
        let frame = attributes.frame
        let visible = scrollView.contentView.bounds
        guard frame.isValidScrollRect, visible.isValidScrollRect, gridLayout.collectionViewContentSize.isValidScrollSize else { return }
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
        guard !wallpapers.isEmpty else { return false }
        let current = selectedWallpaperID.flatMap { id in wallpapers.firstIndex { $0.id == id } } ?? collectionView.selectionIndexPaths.first?.item ?? 0
        let next = min(max(current + delta, 0), wallpapers.count - 1)
        guard next != current else { return true }
        selectedWallpaperID = wallpapers[next].id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [IndexPath(item: next, section: 0)]
        isApplyingSelection = false
        collectionView.scrollToItems(at: [IndexPath(item: next, section: 0)], scrollPosition: .nearestVerticalEdge)
        refreshVisibleSelection()
        onSelect?(wallpapers[next])
        return true
    }

    private func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        guard let indexPath, wallpapers.indices.contains(indexPath.item) else { return nil }
        let wallpaper = wallpapers[indexPath.item]
        selectedWallpaperID = wallpaper.id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [indexPath]
        isApplyingSelection = false
        refreshVisibleSelection()
        onSelect?(wallpaper)
        return contextMenuProvider?(wallpaper)
    }

    private func openDetail(for indexPath: IndexPath) {
        guard wallpapers.indices.contains(indexPath.item) else { return }
        let wallpaper = wallpapers[indexPath.item]
        selectedWallpaperID = wallpaper.id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [indexPath]
        isApplyingSelection = false
        refreshVisibleSelection()
        onSelect?(wallpaper)
        onOpenDetail?()
    }

    private func performWithoutAnimation(_ updates: () -> Void) {
        NSView.performWithoutAnimation(updates)
    }
}

final class WallhavenGridCollectionView: WorkspaceCollectionView {
    var arrowKeyHandler: ((Int) -> Bool)?
    var doubleClickHandler: ((IndexPath) -> Void)?

    override func accessibilityLabel() -> String? { "Wallhaven Grid" }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedIndexPath = indexPathForItem(at: point)
        super.mouseDown(with: event)
        if event.clickCount == 2, let clickedIndexPath { doubleClickHandler?(clickedIndexPath) }
    }

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        clearHoverOnVisibleItems()
        super.viewDidEndLiveResize()
    }

    override func clearHoverOnVisibleItems() {
        lastHoveredIndexPath = nil
        for item in visibleItems() { (item as? WallhavenGridItemView)?.clearHoverState() }
    }

    override func syncHoverOnVisibleItems(windowLocation: NSPoint?) {
        for item in visibleItems() { (item as? WallhavenGridItemView)?.syncHoverState(windowLocation: windowLocation) }
    }
}

private extension NSRect {
    var isValidScrollRect: Bool {
        origin.x.isFinite && origin.y.isFinite && size.isValidScrollSize && size.width >= 0 && size.height >= 0
    }
}

private extension NSSize {
    var isValidScrollSize: Bool {
        width.isFinite && height.isFinite
    }
}
