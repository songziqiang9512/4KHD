import AppKit
import Nuke

@MainActor
final class MissKonGridContainerView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((MissKonItem) -> Void)?
    var onOpenDetail: (() -> Void)?
    var onNeedsMore: (() -> Void)?
    var onEscape: (() -> Bool)?
    var onRetry: (() -> Void)?
    var contextMenuProvider: ((MissKonItem) -> NSMenu?)?

    private let scrollView = NSScrollView()
    private let collectionView = MissKonGridCollectionView()
    private let gridLayout = WorkspaceThumbnailWaterfallLayout()
    private var items: [MissKonItem] = []
    private var selectedItemID: MissKonItem.ID?
    private var previousSelectedItemID: MissKonItem.ID?
    private var searchQuery: String?
    private var showsFooter = false
    private var isRefreshing = false
    private var errorMessage: String?
    private var canLoadMore = false
    private var minimumColumnCount: Int?
    private var maximumColumnCount: Int?
    private var preferredCardMinimumWidth: CGFloat = 136
    private var isApplyingSelection = false
    private var lastAppliedIDs: [MissKonItem.ID] = []
    private var lastShowsFooter = false
    private var lastLayoutWidth: CGFloat = 0
    private var aspectRatiosByItemID: [MissKonItem.ID: CGFloat] = [:]
    private let aspectRatioLayoutQueue = WorkspaceCoalescingQueue(
        name: "MissKonGridAspectRatio", interval: 0.03, maxInterval: 0.1
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
    }

    func focus() { window?.makeFirstResponderUnlessDescendantIsFirstResponder(collectionView) }

    func firstVisibleItemID() -> MissKonItem.ID? {
        collectionView.indexPathsForVisibleItems()
            .filter { items.indices.contains($0.item) }
            .min { $0.item < $1.item }
            .map { items[$0.item].id }
    }

    func scrollItemIntoViewIfNeeded(withID itemID: MissKonItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        scrollItemIntoViewIfNeeded(at: IndexPath(item: index, section: 0))
    }

    func update(
        items: [MissKonItem],
        selectedItemID: MissKonItem.ID?,
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
        let contentChanged = items.map(\.id) != previousItemIDs || showsFooter != lastShowsFooter
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

        if updateItemSize() || contentChanged {
            lastAppliedIDs = items.map(\.id)
            lastShowsFooter = showsFooter
            performWithoutAnimation { collectionView.reloadData() }
        } else {
            refreshVisibleItems()
        }
        syncSelection()
    }

    private func refreshVisibleItems() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard indexPath.item < items.count,
                  let cell = collectionView.item(at: indexPath) as? MissKonGridItemView else { continue }
            let item = items[indexPath.item]
            cell.configure(item: item, isSelected: item.id == selectedItemID, searchQuery: searchQuery) { [weak self] ratio in
                self?.updateAspectRatio(ratio, for: item.id)
            }
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count + (showsFooter ? 1 : 0)
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        if indexPath.item >= items.count {
            let footer = collectionView.makeItem(withIdentifier: MissKonGridFooterItem.reuseID, for: indexPath) as? MissKonGridFooterItem ?? MissKonGridFooterItem()
            footer.configure(isRefreshing: isRefreshing, errorMessage: errorMessage, canLoadMore: canLoadMore, hasItems: !items.isEmpty)
            footer.onRetry = { [weak self] in
                if self?.errorMessage != nil {
                    self?.onRetry?()
                } else {
                    self?.onNeedsMore?()
                }
            }
            return footer
        }
        let item = collectionView.makeItem(withIdentifier: MissKonGridItemView.reuseID, for: indexPath) as? MissKonGridItemView ?? MissKonGridItemView()
        let galleryItem = items[indexPath.item]
        item.configure(item: galleryItem, isSelected: galleryItem.id == selectedItemID, searchQuery: searchQuery) { [weak self] ratio in
            self?.updateAspectRatio(ratio, for: galleryItem.id)
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection, let indexPath = indexPaths.first, items.indices.contains(indexPath.item) else { return }
        let item = items[indexPath.item]
        previousSelectedItemID = selectedItemID
        selectedItemID = item.id
        refreshVisibleSelection()
        onSelect?(item)
    }

    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        guard indexPath.item >= max(items.count - 3, 0) else { return }
        onNeedsMore?()
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard items.indices.contains(indexPath.item) else { return nil }
        return items[indexPath.item].detailURL as NSURL
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
            Task { @MainActor [weak self] in self?.updateItemSize() }
        }

        gridLayout.columnSpacing = 8
        gridLayout.rowSpacing = 10
        gridLayout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        gridLayout.aspectRatioProvider = { [weak self] indexPath in
            guard let self, indexPath.item < self.items.count else { return 16.0 / 9.0 }
            let item = self.items[indexPath.item]
            if let ratio = self.aspectRatiosByItemID[item.id], ratio.isFinite, ratio > 0 { return ratio }
            if let ratio = item.coverAspectRatio.map({ CGFloat($0) }), ratio.isFinite, ratio > 0 { return ratio }
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
                guard let self, let id = self.selectedItemID, let indexPath = self.items.firstIndex(where: { $0.id == id }) else { return false }
                self.openDetail(for: IndexPath(item: indexPath, section: 0))
                return true
            }
        )
        collectionView.contextMenuProvider = { [weak self] indexPath in self?.makeContextMenu(for: indexPath) }
        collectionView.doubleClickHandler = { [weak self] indexPath in self?.openDetail(for: indexPath) }
        collectionView.register(MissKonGridItemView.self, forItemWithIdentifier: MissKonGridItemView.reuseID)
        collectionView.register(MissKonGridFooterItem.self, forItemWithIdentifier: MissKonGridFooterItem.reuseID)

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

    private func updateAspectRatio(_ ratio: CGFloat, for itemID: MissKonItem.ID) {
        guard ratio.isFinite, ratio > 0 else { return }
        let clamped = max(gridLayout.minAspectRatio, min(gridLayout.maxAspectRatio, ratio))
        let current = aspectRatiosByItemID[itemID] ?? items.first(where: { $0.id == itemID })?.coverAspectRatio.map { CGFloat($0) } ?? 0.74
        let threshold: CGFloat = current < 0.5 ? 0.01 : 0.1
        guard abs(current - clamped) > threshold else { return }
        aspectRatiosByItemID[itemID] = clamped
        aspectRatioLayoutQueue.add(id: "invalidate") { [weak self] in
            self?.performWithoutAnimation { self?.collectionView.collectionViewLayout?.invalidateLayout() }
        }
    }

    private func syncSelection() {
        guard let selectedItemID, let index = items.firstIndex(where: { $0.id == selectedItemID }) else {
            isApplyingSelection = true; collectionView.selectionIndexPaths = []; isApplyingSelection = false; return
        }
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
        isApplyingSelection = false
        refreshVisibleSelection()
    }

    private func refreshVisibleSelection() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? MissKonGridItemView, items.indices.contains(indexPath.item) else { continue }
            let id = items[indexPath.item].id
            item.applySelectionState(id == selectedItemID)
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
        let current = selectedItemID.flatMap { id in items.firstIndex { $0.id == id } } ?? collectionView.selectionIndexPaths.first?.item ?? 0
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
        guard let indexPath, items.indices.contains(indexPath.item) else { return nil }
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

    private func performWithoutAnimation(_ updates: () -> Void) {
        NSView.performWithoutAnimation(updates)
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

final class MissKonGridCollectionView: WorkspaceCollectionView {
    var arrowKeyHandler: ((Int) -> Bool)?
    var doubleClickHandler: ((IndexPath) -> Void)?

    override func accessibilityLabel() -> String? { "MissKon Grid" }

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
        for item in visibleItems() { (item as? MissKonGridItemView)?.clearHoverState() }
    }

    override func syncHoverOnVisibleItems(windowLocation: NSPoint?) {
        for item in visibleItems() { (item as? MissKonGridItemView)?.syncHoverState(windowLocation: windowLocation) }
    }
}
