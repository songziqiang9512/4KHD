import AppKit
import Nuke
import Observation

@MainActor
final class MrdsContentViewController: NSViewController, WorkspaceFocusable {
    private enum Row: Hashable {
        case item(MrdsGalleryItem.ID)
        case footer
    }

    private struct FooterState: Equatable {
        var isRefreshing = false
        var errorMessage: String?
        var canLoadMore = false
        var showsFooter = false
    }

    private let store: MrdsGalleryStore
    private let preferences: MrdsContentPreferences
    private let detailPane: WorkspaceDetailPaneController
    private let tableView = WorkspaceTableView()
    private let tableScrollView = NSScrollView()
    private let collectionView = MrdsGridCollectionView()
    private let gridScrollView = NSScrollView()
    private let gridLayout = WorkspaceThumbnailWaterfallLayout()
    private var activeView: NSView?
    private var rows: [Row] = []
    private var isApplyingSelection = false
    private var isObserving = false
    private var lastAppliedListItems: [MrdsGalleryItem] = []
    private var lastAppliedListItemIDs: [MrdsGalleryItem.ID] = []
    private var lastListFavoriteItemIDs: Set<MrdsGalleryItem.ID> = []
    private var lastListSearchQuery: String?
    private var lastListFooterState = FooterState()
    private var lastAppliedGridItems: [MrdsGalleryItem] = []
    private var lastAppliedGridItemIDs: [MrdsGalleryItem.ID] = []
    private var lastGridFavoriteItemIDs: Set<MrdsGalleryItem.ID> = []
    private var lastGridSelectedItemID: MrdsGalleryItem.ID?
    private var lastGridSearchQuery: String?
    private var lastGridFooterState = FooterState()
    private var lastGridLayoutWidth: CGFloat = 0
    private var aspectRatiosByItemID: [MrdsGalleryItem.ID: CGFloat] = [:]
    private let thumbnailPrefetchController = WorkspaceThumbnailPrefetchController<MrdsGalleryItem.ID>()
    private let aspectRatioLayoutQueue = WorkspaceCoalescingQueue(
        name: "Mrds Grid Aspect Ratio", interval: 0.03, maxInterval: 0.1
    )
    private let thumbnailResolutionQueue = WorkspaceCoalescingQueue(
        name: "Mrds Grid Thumbnail Resolution", interval: 0.03, maxInterval: 0.1
    )
    private let reloadQueue = WorkspaceCoalescingQueue(name: "Mrds Content Reload", interval: 0.05, maxInterval: 0.12)

    init(store: MrdsGalleryStore, preferences: MrdsContentPreferences, detailPane: WorkspaceDetailPaneController) {
        self.store = store
        self.preferences = preferences
        self.detailPane = detailPane
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        setupTable()
        setupGrid()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadContent()
        observeState()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard preferences.layout == .grid else { return }
        updateGridLayoutIfNeeded()
        scheduleThumbnailPrefetch()
    }

    func focus() {
        if preferences.layout == .list {
            tableView.window?.makeFirstResponder(tableView)
        } else {
            collectionView.window?.makeFirstResponder(collectionView)
        }
    }

    private func setupTable() {
        tableScrollView.drawsBackground = false
        tableScrollView.borderType = .noBorder
        tableScrollView.automaticallyAdjustsContentInsets = true
        tableScrollView.hasVerticalScroller = true
        tableScrollView.documentView = tableView
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MrdsItem")))
        tableView.headerView = nil
        tableView.rowHeight = 96
        tableView.intercellSpacing = NSSize(width: 0, height: 3)
        tableView.style = .plain
        tableView.backgroundColor = .controlBackgroundColor
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openTableSelection)
        tableView.keyboardContext = WorkspaceKeyboardContext(
            stepSelection: { [weak self] delta in self?.stepListSelection(delta) ?? false },
            onEscape: { [weak self] in self?.clearSearch() ?? false },
            onEnter: { [weak self] in self?.openTableSelection(); return true }
        )
        tableView.contextMenuProvider = { [weak self] row in
            self?.makeContextMenu(forRow: row)
        }
    }

    private func setupGrid() {
        gridLayout.columnSpacing = 8
        gridLayout.rowSpacing = 10
        gridLayout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        gridLayout.treatsLastItemAsFooter = true
        gridLayout.minimumColumnCount = MrdsContentPreferences.minimumGridColumnCount
        gridLayout.maximumColumnCount = preferences.gridColumnCount
        gridLayout.preferredCardMinimumWidth = 136
        gridLayout.aspectRatioProvider = { [weak self] indexPath in
            guard let self, indexPath.item < store.items.count else { return 1 }
            let item = store.items[indexPath.item]
            return aspectRatiosByItemID[item.id] ?? CGFloat(item.coverAspectRatio)
        }
        collectionView.collectionViewLayout = gridLayout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.dataSource = self
        collectionView.delegate = self
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(openGridSelection))
        doubleClick.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(doubleClick)
        collectionView.register(MrdsGridItem.self, forItemWithIdentifier: MrdsGridItem.identifier)
        collectionView.register(MrdsGridFooterItem.self, forItemWithIdentifier: MrdsGridFooterItem.identifier)
        collectionView.keyboardContext = WorkspaceKeyboardContext(
            stepSelection: { [weak self] delta in self?.stepGridSelection(delta) ?? false },
            onEscape: { [weak self] in self?.clearSearch() ?? false },
            onEnter: { [weak self] in self?.openGridSelection(); return true }
        )
        collectionView.contextMenuProvider = { [weak self] indexPath in
            self?.makeContextMenu(for: indexPath)
        }

        gridScrollView.drawsBackground = false
        gridScrollView.borderType = .noBorder
        gridScrollView.automaticallyAdjustsContentInsets = true
        gridScrollView.hasVerticalScroller = true
        gridScrollView.hasHorizontalScroller = false
        gridScrollView.contentView.drawsBackground = false
        gridScrollView.documentView = collectionView
        gridScrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gridBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: gridScrollView.contentView
        )
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = store.items
            _ = store.selectedItemID
            _ = store.isRefreshingList
            _ = store.listErrorMessage
            _ = store.nextPageURL
            _ = store.activeSearchQuery
            _ = store.favoriteItemIDs
            _ = preferences.layout
            _ = preferences.gridColumnCount
            _ = detailPane.isPresented
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isObserving = false
                reloadQueue.add(id: "reload") { [weak self] in self?.reloadContent() }
                observeState()
            }
        }
    }

    private func reloadContent() {
        rows = store.items.map { .item($0.id) }
        if shouldShowFooter { rows.append(.footer) }
        switch preferences.layout {
        case .list:
            setActiveView(tableScrollView)
            reloadListContent()
        case .grid:
            setActiveView(gridScrollView)
            reloadGridContent()
        }
    }

    private var shouldShowFooter: Bool {
        store.listErrorMessage != nil || store.isRefreshingList || store.canLoadMoreList || !store.items.isEmpty
    }

    private func setActiveView(_ nextView: NSView) {
        animateViewTransition(to: nextView, activeView: &activeView)
    }

    private func syncTableSelection() {
        guard let id = store.selectedItemID,
              let row = rows.firstIndex(of: .item(id))
        else {
            isApplyingSelection = true
            tableView.deselectAll(nil)
            isApplyingSelection = false
            return
        }
        isApplyingSelection = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isApplyingSelection = false
    }

    private func reloadListContent() {
        let itemIDs = store.items.map(\.id)
        let favoriteItemIDs = store.favoriteItemIDs
        let footerState = FooterState(
            isRefreshing: store.isRefreshingList,
            errorMessage: store.listErrorMessage,
            canLoadMore: store.canLoadMoreList,
            showsFooter: shouldShowFooter
        )
        let structureChanged = itemIDs != lastAppliedListItemIDs
            || footerState.showsFooter != lastListFooterState.showsFooter
        let presentationChanged = store.items != lastAppliedListItems
            || favoriteItemIDs != lastListFavoriteItemIDs
            || store.activeSearchQuery != lastListSearchQuery
        let footerChanged = footerState != lastListFooterState
        let canAppend = canApplyAppendUpdate(from: lastAppliedListItemIDs, to: itemIDs)
            && footerState.showsFooter == lastListFooterState.showsFooter

        if structureChanged {
            if canAppend {
                let insertedRange = lastAppliedListItemIDs.count ..< itemIDs.count
                NSView.performWithoutAnimation {
                    tableView.insertRows(at: IndexSet(integersIn: insertedRange), withAnimation: [])
                }
                if presentationChanged {
                    reloadVisibleListRows()
                }
                reloadListFooterIfVisible()
            } else {
                NSView.performWithoutAnimation { tableView.reloadData() }
            }
        } else {
            if presentationChanged {
                reloadVisibleListRows()
            }
            if footerChanged {
                reloadListFooterIfVisible()
            }
        }
        syncTableSelection()

        lastAppliedListItems = store.items
        lastAppliedListItemIDs = itemIDs
        lastListFavoriteItemIDs = favoriteItemIDs
        lastListSearchQuery = store.activeSearchQuery
        lastListFooterState = footerState
    }

    private func reloadVisibleListRows() {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        let totalRows = tableView.numberOfRows
        guard visibleRows.location < totalRows else { return }
        let upperBound = min(visibleRows.location + visibleRows.length, totalRows)
        guard upperBound > visibleRows.location else { return }
        tableView.reloadData(
            forRowIndexes: IndexSet(integersIn: visibleRows.location ..< upperBound),
            columnIndexes: IndexSet(integer: 0)
        )
    }

    private func reloadListFooterIfVisible() {
        guard shouldShowFooter else { return }
        let footerRow = store.items.count
        guard footerRow < tableView.numberOfRows else { return }
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard NSLocationInRange(footerRow, visibleRows) else { return }
        tableView.reloadData(
            forRowIndexes: IndexSet(integer: footerRow),
            columnIndexes: IndexSet(integer: 0)
        )
    }

    private func canApplyAppendUpdate(from oldIDs: [MrdsGalleryItem.ID], to newIDs: [MrdsGalleryItem.ID]) -> Bool {
        guard !oldIDs.isEmpty, newIDs.count > oldIDs.count else { return false }
        return Array(newIDs.prefix(oldIDs.count)) == oldIDs
    }

    private func syncGridSelection() {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        guard let id = store.selectedItemID,
              let index = store.items.firstIndex(where: { $0.id == id })
        else {
            collectionView.selectionIndexPaths = []
            refreshVisibleGridSelection()
            return
        }
        collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
        refreshVisibleGridSelection()
    }

    private func stepListSelection(_ delta: Int) -> Bool {
        stepSelection(delta)
    }

    private func stepGridSelection(_ delta: Int) -> Bool {
        stepSelection(delta)
    }

    private func stepSelection(_ delta: Int) -> Bool {
        guard !store.items.isEmpty else { return false }
        guard let current = store.selectedItemID.flatMap({ id in store.items.firstIndex { $0.id == id } }) else {
            store.select(delta < 0 ? store.items[store.items.count - 1] : store.items[0])
            return true
        }
        let next = min(max(current + (delta < 0 ? -1 : 1), 0), store.items.count - 1)
        store.select(store.items[next])
        return true
    }

    private func clearSearch() -> Bool {
        guard store.activeSearchQuery != nil || !store.searchText.isEmpty else { return false }
        store.clearSearch()
        return true
    }

    @objc private func gridSelectionChanged() {
        guard let indexPath = collectionView.selectionIndexPaths.first,
              store.items.indices.contains(indexPath.item) else { return }
        store.select(store.items[indexPath.item])
    }

    @objc private func openGridSelection() {
        gridSelectionChanged()
        guard store.selectedItem != nil else { return }
        detailPane.setPresented(true)
    }

    @objc private func openTableSelection() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard rows.indices.contains(row), case let .item(id) = rows[row],
              let item = store.items.first(where: { $0.id == id }) else { return }
        store.select(item)
        detailPane.setPresented(true)
    }

    private func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard rows.indices.contains(row),
              case let .item(id) = rows[row],
              let item = store.items.first(where: { $0.id == id }) else { return nil }
        if tableView.selectedRow != row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            store.select(item)
        }
        return makeContextMenu(for: item)
    }

    private func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        guard let indexPath, store.items.indices.contains(indexPath.item) else { return nil }
        let item = store.items[indexPath.item]
        if store.selectedItemID != item.id {
            collectionView.selectionIndexPaths = [indexPath]
            store.select(item)
        }
        return makeContextMenu(for: item)
    }

    private func makeContextMenu(for item: MrdsGalleryItem) -> NSMenu {
        let menu = NSMenu(title: "MrdsGalleryItemMenu")
        let favoriteItem = NSMenuItem(
            title: store.isFavorite(item) ? "取消收藏" : "收藏",
            action: #selector(toggleFavoriteFromMenu(_:)),
            keyEquivalent: ""
        )
        favoriteItem.target = self
        favoriteItem.representedObject = item
        favoriteItem.image = NSImage(
            systemSymbolName: store.isFavorite(item) ? "bookmark.slash" : "bookmark",
            accessibilityDescription: favoriteItem.title
        )
        menu.addItem(favoriteItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: "在浏览器中打开",
            action: #selector(openOriginalPageFromMenu(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.representedObject = item.detailURL
        openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: openItem.title)
        menu.addItem(openItem)

        let copyItem = NSMenuItem(
            title: "复制链接",
            action: #selector(copyDetailURLFromMenu(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.representedObject = item.detailURL
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: copyItem.title)
        menu.addItem(copyItem)

        let shareItem = NSMenuItem(
            title: "共享…",
            action: #selector(shareDetailURLFromMenu(_:)),
            keyEquivalent: ""
        )
        shareItem.target = self
        shareItem.representedObject = item.detailURL
        shareItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: shareItem.title)
        menu.addItem(shareItem)
        return menu
    }

    @objc private func toggleFavoriteFromMenu(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MrdsGalleryItem else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await store.toggleFavorite(for: item)
            } catch {
                let alert = makeAppAlert(
                    title: "收藏保存失败",
                    message: error.localizedDescription,
                    style: .warning
                )
                presentAppAlert(alert, in: view.window)
            }
        }
    }

    @objc private func openOriginalPageFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyDetailURLFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .URL)
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    @objc private func shareDetailURLFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        SharingPresenter.show(items: [url], of: view, preferredEdge: .maxX)
    }

    @objc private func gridBoundsDidChange() {
        updateGridLayoutIfNeeded()
        scheduleThumbnailPrefetch()
        let visible = gridScrollView.contentView.documentVisibleRect
        let height = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
        if visible.maxY >= height - max(visible.height, 500) {
            store.loadMoreListIfNeeded()
        }
    }

    private func reloadGridContent() {
        let itemIDs = store.items.map(\.id)
        let favoriteItemIDs = store.favoriteItemIDs
        let footerState = FooterState(
            isRefreshing: store.isRefreshingList,
            errorMessage: store.listErrorMessage,
            canLoadMore: store.canLoadMoreList,
            showsFooter: shouldShowFooter
        )
        let contentChanged = itemIDs != lastAppliedGridItemIDs
            || footerState.showsFooter != lastGridFooterState.showsFooter
        let presentationChanged = store.items != lastAppliedGridItems
            || favoriteItemIDs != lastGridFavoriteItemIDs
            || store.activeSearchQuery != lastGridSearchQuery
        let footerChanged = footerState != lastGridFooterState
        let selectionChanged = store.selectedItemID != lastGridSelectedItemID
        let previousItemsByID = Dictionary(
            lastAppliedGridItems.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        for item in store.items {
            guard let previous = previousItemsByID[item.id] else { continue }
            if previous.coverURL != item.coverURL || previous.coverAspectRatio != item.coverAspectRatio {
                aspectRatiosByItemID.removeValue(forKey: item.id)
            }
        }
        if aspectRatiosByItemID.count > 1500 {
            let nextItemIDSet = Set(itemIDs)
            aspectRatiosByItemID = aspectRatiosByItemID.filter { nextItemIDSet.contains($0.key) }
        }

        let canAppend = canApplyAppendUpdate(from: lastAppliedGridItemIDs, to: itemIDs)
            && footerState.showsFooter == lastGridFooterState.showsFooter
        updateGridLayoutIfNeeded()
        if contentChanged {
            if canAppend {
                let insertedRange = lastAppliedGridItemIDs.count ..< itemIDs.count
                NSView.performWithoutAnimation {
                    collectionView.insertItems(
                        at: Set(insertedRange.map { IndexPath(item: $0, section: 0) })
                    )
                }
                if presentationChanged {
                    refreshVisibleGridItems()
                }
                reloadGridFooterIfVisible()
            } else {
                thumbnailPrefetchController.reset()
                gridLayout.invalidateLayoutForContentReplacement()
                NSView.performWithoutAnimation { collectionView.reloadData() }
            }
            prefetchInitialThumbnails()
        } else {
            if presentationChanged {
                refreshVisibleGridItems()
            }
            if footerChanged {
                reloadGridFooterIfVisible()
            }
            if selectionChanged {
                refreshVisibleGridSelection()
            }
        }
        syncGridSelection()
        scheduleThumbnailPrefetch()

        lastAppliedGridItems = store.items
        lastAppliedGridItemIDs = itemIDs
        lastGridFavoriteItemIDs = favoriteItemIDs
        lastGridSelectedItemID = store.selectedItemID
        lastGridSearchQuery = store.activeSearchQuery
        lastGridFooterState = footerState
    }

    @discardableResult
    private func updateGridLayoutIfNeeded() -> Bool {
        let visibleWidth = gridScrollView.contentView.bounds.width > 0
            ? gridScrollView.contentView.bounds.width
            : view.bounds.width
        let widthChanged = abs(visibleWidth - lastGridLayoutWidth) > 0.5
        let minimumChanged = gridLayout.minimumColumnCount != MrdsContentPreferences.minimumGridColumnCount
        let maximumChanged = gridLayout.maximumColumnCount != preferences.gridColumnCount
        let preferredWidthChanged = abs(gridLayout.preferredCardMinimumWidth - 136) > 0.001
        guard widthChanged || minimumChanged || maximumChanged || preferredWidthChanged else { return false }
        lastGridLayoutWidth = visibleWidth
        gridLayout.minimumColumnCount = MrdsContentPreferences.minimumGridColumnCount
        gridLayout.maximumColumnCount = preferences.gridColumnCount
        gridLayout.preferredCardMinimumWidth = 136
        NSView.performWithoutAnimation { gridLayout.invalidateLayout() }
        thumbnailResolutionQueue.add(id: "refresh-visible-items") { [weak self] in
            guard let self,
                  self.preferences.layout == .grid,
                  self.activeView === self.gridScrollView else { return }
            self.collectionView.layoutSubtreeIfNeeded()
            self.refreshVisibleGridItems()
            self.scheduleThumbnailPrefetch()
        }
        return true
    }

    private func refreshVisibleGridItems() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard store.items.indices.contains(indexPath.item),
                  let itemView = collectionView.item(at: indexPath) as? MrdsGridItem else { continue }
            configure(itemView, with: store.items[indexPath.item])
        }
    }

    private func refreshVisibleGridSelection() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard store.items.indices.contains(indexPath.item),
                  let itemView = collectionView.item(at: indexPath) as? MrdsGridItem else { continue }
            itemView.applySelectionState(store.items[indexPath.item].id == store.selectedItemID)
        }
    }

    private func reloadGridFooterIfVisible() {
        guard shouldShowFooter else { return }
        let footerIndexPath = IndexPath(item: store.items.count, section: 0)
        guard collectionView.indexPathsForVisibleItems().contains(footerIndexPath) else { return }
        NSView.performWithoutAnimation { collectionView.reloadItems(at: [footerIndexPath]) }
    }

    private func configure(_ itemView: MrdsGridItem, with model: MrdsGalleryItem) {
        itemView.thumbnailMaxPixelSize = thumbnailMaxPixelSize
        itemView.configure(
            item: model,
            isFavorite: store.isFavorite(model),
            isSelected: model.id == store.selectedItemID,
            searchQuery: store.activeSearchQuery,
            onImageAspectRatioResolved: { [weak self] ratio in
                self?.updateAspectRatio(ratio, for: model.id, knownAspectRatio: CGFloat(model.coverAspectRatio))
            }
        )
    }

    private func updateAspectRatio(_ ratio: CGFloat, for itemID: MrdsGalleryItem.ID, knownAspectRatio: CGFloat) {
        guard ratio.isFinite, ratio > 0 else { return }
        let clamped = max(gridLayout.minAspectRatio, min(gridLayout.maxAspectRatio, ratio))
        let current = aspectRatiosByItemID[itemID] ?? knownAspectRatio
        guard abs(current - clamped) > 0.1 else { return }
        aspectRatiosByItemID[itemID] = clamped
        aspectRatioLayoutQueue.add(id: "invalidate") { [weak self] in
            self?.gridLayout.invalidateCachedFrames()
        }
    }

    private var thumbnailMaxPixelSize: CGFloat {
        let width = gridLayout.resolvedColumnWidth
        guard width > 0 else { return 512 }
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let requested = width * scale
        let buckets: [CGFloat] = [512, 768, 1024, 1536]
        return buckets.first { $0 >= requested } ?? 1536
    }

    private func prefetchInitialThumbnails() {
        thumbnailPrefetchController.prefetchInitial(
            itemCount: store.items.count,
            itemID: { [weak self] index in self?.itemID(at: index) },
            request: { [weak self] index in self?.thumbnailRequest(at: index) }
        )
    }

    private func scheduleThumbnailPrefetch() {
        thumbnailPrefetchController.schedule(
            scrollView: gridScrollView,
            layout: gridLayout,
            itemCount: store.items.count,
            itemID: { [weak self] index in self?.itemID(at: index) },
            request: { [weak self] index in self?.thumbnailRequest(at: index) }
        )
    }

    private func itemID(at index: Int) -> MrdsGalleryItem.ID? {
        guard store.items.indices.contains(index) else { return nil }
        return store.items[index].id
    }

    private func thumbnailRequest(at index: Int) -> ImageRequest? {
        guard store.items.indices.contains(index), let url = store.items[index].coverURL else { return nil }
        return RemoteImagePipeline.shared.request(
            for: url,
            priority: .veryLow,
            maxPixelSize: thumbnailMaxPixelSize,
            configureURLRequest: MrdsRequestFactory.configureImageRequest
        )
    }
}

@MainActor
private final class MrdsGridCollectionView: WorkspaceCollectionView {
    override func accessibilityLabel() -> String? {
        "每日大赛图片网格"
    }

    override func viewDidEndLiveResize() {
        clearHoverOnVisibleItems()
        super.viewDidEndLiveResize()
    }

    override func clearHoverOnVisibleItems() {
        lastHoveredIndexPath = nil
        for item in visibleItems() {
            (item as? MrdsGridItem)?.clearHoverState()
        }
    }

    override func syncHoverOnVisibleItems(windowLocation: NSPoint?) {
        for item in visibleItems() {
            (item as? MrdsGridItem)?.syncHoverState(windowLocation: windowLocation)
        }
    }
}

extension MrdsContentViewController: NSTableViewDataSource, NSTableViewDelegate {
    nonisolated func numberOfRows(in _: NSTableView) -> Int {
        MainActor.assumeIsolated { rows.count }
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return 96 }
        return rows[row] == .footer ? 42 : 96
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case let .item(id):
            guard let item = store.items.first(where: { $0.id == id }) else { return nil }
            let cell = tableView.makeView(withIdentifier: MrdsListRowView.identifier, owner: self) as? MrdsListRowView
                ?? MrdsListRowView()
            cell.configure(item: item, isFavorite: store.isFavorite(item), searchQuery: store.activeSearchQuery)
            if item.id == store.items.last?.id { store.loadMoreListIfNeeded() }
            return cell
        case .footer:
            let cell = tableView.makeView(withIdentifier: MrdsListFooterView.identifier, owner: self) as? MrdsListFooterView
                ?? MrdsListFooterView()
            cell.configure(
                isRefreshing: store.isRefreshingList,
                errorMessage: store.listErrorMessage,
                canLoadMore: store.canLoadMoreList,
                hasItems: !store.items.isEmpty
            )
            cell.onRetry = { [weak store] in store?.retryLastFailure() }
            if store.canLoadMoreList { store.loadMoreListIfNeeded() }
            return cell
        }
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isApplyingSelection, rows.indices.contains(tableView.selectedRow),
              case let .item(id) = rows[tableView.selectedRow],
              let item = store.items.first(where: { $0.id == id }) else { return }
        store.select(item)
    }
}

extension MrdsContentViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    nonisolated func numberOfSections(in _: NSCollectionView) -> Int {
        1
    }

    nonisolated func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        MainActor.assumeIsolated { store.items.count + (shouldShowFooter ? 1 : 0) }
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        if indexPath.item >= store.items.count {
            let item = collectionView.makeItem(withIdentifier: MrdsGridFooterItem.identifier, for: indexPath) as! MrdsGridFooterItem
            item.configure(
                isRefreshing: store.isRefreshingList,
                errorMessage: store.listErrorMessage,
                canLoadMore: store.canLoadMoreList,
                hasItems: !store.items.isEmpty,
                onRetry: { [weak store] in store?.retryLastFailure() }
            )
            if store.canLoadMoreList { store.loadMoreListIfNeeded() }
            return item
        }
        let item = collectionView.makeItem(withIdentifier: MrdsGridItem.identifier, for: indexPath) as! MrdsGridItem
        let model = store.items[indexPath.item]
        configure(item, with: model)
        return item
    }

    func collectionView(_: NSCollectionView, didSelectItemsAt _: Set<IndexPath>) {
        guard !isApplyingSelection else { return }
        gridSelectionChanged()
        refreshVisibleGridSelection()
    }
}

@MainActor
private final class MrdsListRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("MrdsListRowView")
    private let cover = MrdsThumbnailView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let favoriteIcon = NSImageView()
    private let videoIcon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        favoriteIcon.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "已收藏")
        favoriteIcon.contentTintColor = .systemRed
        videoIcon.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "含视频")
        videoIcon.contentTintColor = .systemBlue
        let icons = NSStackView(views: [videoIcon, favoriteIcon])
        icons.orientation = .horizontal
        icons.spacing = 8
        let text = NSStackView(views: [titleLabel, subtitleLabel, icons])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 5
        let root = NSStackView(views: [cover, text])
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 10
        addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        cover.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cover.widthAnchor.constraint(equalToConstant: 64),
            cover.heightAnchor.constraint(equalToConstant: 86),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 4),
        ])
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func configure(item: MrdsGalleryItem, isFavorite: Bool, searchQuery: String?) {
        cover.setImage(url: item.coverURL)
        if let searchQuery, !searchQuery.isEmpty {
            titleLabel.attributedStringValue = highlightedAttributedString(item.title, query: searchQuery)
        } else {
            titleLabel.stringValue = item.title
        }
        subtitleLabel.stringValue = [item.category, item.metadataText, item.publishedDate].filter { !$0.isEmpty }.joined(separator: " · ")
        favoriteIcon.isHidden = !isFavorite
        videoIcon.isHidden = !item.hasVideo
    }
}

@MainActor
private final class MrdsListFooterView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("MrdsListFooterView")
    private let progress = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")
    var onRetry: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        progress.style = .spinning
        progress.controlSize = .small
        let stack = NSStackView(views: [progress, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(retry)))
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func configure(isRefreshing: Bool, errorMessage: String?, canLoadMore: Bool, hasItems: Bool) {
        progress.isHidden = !isRefreshing || errorMessage != nil
        isRefreshing && errorMessage == nil ? progress.startAnimation(nil) : progress.stopAnimation(nil)
        label.stringValue = errorMessage.map { "\($0) — 点击重试" } ?? (isRefreshing ? "加载中…" : (canLoadMore ? "加载更多" : (hasItems ? "已到末尾" : "无内容")))
        label.textColor = errorMessage == nil ? .tertiaryLabelColor : .systemRed
    }

    @objc private func retry() {
        onRetry?()
    }
}

@MainActor
private final class MrdsGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("MrdsGridItem")
    private static let failedCoverRetryCooldown: TimeInterval = 3
    private let card = WorkspaceThumbnailGridCardView()
    private let videoBadge = NSImageView()
    private var imageTask: RemoteImageLoadTask?
    private var coverRetryTask: Task<Void, Never>?
    private var representedID: String?
    private var currentCoverURL: URL?
    private var failedCoverLoadUptime: TimeInterval?
    private var coverLoadAttemptCount = 0
    private var coverLoadGeneration = 0
    private var requestedMaxPixelSize: CGFloat = 0
    var thumbnailMaxPixelSize: CGFloat = 512

    override func loadView() {
        view = NSView()
        view.addSubview(card)
        view.addSubview(videoBadge)
        card.translatesAutoresizingMaskIntoConstraints = false
        videoBadge.translatesAutoresizingMaskIntoConstraints = false
        videoBadge.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "含视频")
        videoBadge.contentTintColor = .white
        videoBadge.wantsLayer = true
        videoBadge.layer?.shadowColor = NSColor.black.cgColor
        videoBadge.layer?.shadowOpacity = 0.65
        videoBadge.layer?.shadowRadius = 3
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor), card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.topAnchor.constraint(equalTo: view.topAnchor), card.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoBadge.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            videoBadge.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            videoBadge.widthAnchor.constraint(equalToConstant: 26), videoBadge.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        coverRetryTask?.cancel()
        coverRetryTask = nil
        coverLoadGeneration &+= 1
        representedID = nil
        currentCoverURL = nil
        failedCoverLoadUptime = nil
        coverLoadAttemptCount = 0
        requestedMaxPixelSize = 0
        card.resetForReuse(preservingImage: true)
    }

    func configure(
        item: MrdsGalleryItem,
        isFavorite: Bool,
        isSelected: Bool,
        searchQuery: String?,
        onImageAspectRatioResolved: @escaping (CGFloat) -> Void
    ) {
        let imageSourceChanged = representedID != item.id || currentCoverURL != item.coverURL
        let requiresResolutionUpgrade = thumbnailMaxPixelSize > requestedMaxPixelSize + 0.5
        let failedCoverRetryIsDue = failedCoverLoadUptime.map {
            ProcessInfo.processInfo.systemUptime - $0 >= Self.failedCoverRetryCooldown
        } ?? false
        let needsCoverReload = item.coverURL != nil && !card.hasImage && imageTask == nil
        if imageSourceChanged {
            coverRetryTask?.cancel()
            coverRetryTask = nil
            failedCoverLoadUptime = nil
            coverLoadAttemptCount = 0
        }
        representedID = item.id
        let metadata = [item.metadataText, isFavorite ? "已收藏" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        card.setText(title: item.title, metadata: metadata, highlightQuery: searchQuery)
        applySelectionState(isSelected)
        videoBadge.isHidden = !item.hasVideo
        guard imageSourceChanged
            || (failedCoverLoadUptime == nil && requiresResolutionUpgrade)
            || failedCoverRetryIsDue
            || needsCoverReload else { return }
        loadCover(for: item, onImageAspectRatioResolved: onImageAspectRatioResolved)
    }

    func applySelectionState(_ isSelected: Bool) {
        card.applySelectionState(isSelected)
    }

    func syncHoverState(windowLocation: NSPoint?) {
        card.syncHoverState(windowLocation: windowLocation)
    }

    func clearHoverState() {
        card.clearHoverState()
    }

    private func loadCover(
        for item: MrdsGalleryItem,
        onImageAspectRatioResolved: @escaping (CGFloat) -> Void
    ) {
        let url = item.coverURL
        if url != nil,
           currentCoverURL == url,
           imageTask != nil,
           failedCoverLoadUptime == nil
        {
            requestedMaxPixelSize = max(requestedMaxPixelSize, thumbnailMaxPixelSize)
            return
        }
        imageTask?.cancel()
        imageTask = nil
        coverRetryTask?.cancel()
        coverRetryTask = nil
        currentCoverURL = item.coverURL
        failedCoverLoadUptime = nil
        requestedMaxPixelSize = thumbnailMaxPixelSize
        coverLoadGeneration &+= 1
        let loadGeneration = coverLoadGeneration
        card.setMissingVisible(false)
        guard let url = item.coverURL else {
            card.setImage(nil, animated: false)
            card.setPlaceholder("无封面", isVisible: true)
            return
        }
        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .normal,
            maxPixelSize: thumbnailMaxPixelSize,
            configureURLRequest: MrdsRequestFactory.configureImageRequest
        )
        if let cached = RemoteImagePipeline.shared.cachedImage(with: request) {
            card.setImage(cached, animated: false)
            failedCoverLoadUptime = nil
            coverLoadAttemptCount = 0
            if cached.size.width > 0, cached.size.height > 0 {
                onImageAspectRatioResolved(cached.size.width / cached.size.height)
            }
            return
        }
        if !card.hasImage {
            card.setPlaceholder("加载中…", isVisible: true)
        }
        coverLoadAttemptCount += 1
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self,
                      representedID == item.id,
                      currentCoverURL == url,
                      coverLoadGeneration == loadGeneration else { return }
                imageTask = nil
                if let image, image.size.width > 0, image.size.height > 0 {
                    card.setImage(image, animated: false)
                    failedCoverLoadUptime = nil
                    coverLoadAttemptCount = 0
                    onImageAspectRatioResolved(image.size.width / image.size.height)
                } else {
                    failedCoverLoadUptime = ProcessInfo.processInfo.systemUptime
                    if !card.hasImage {
                        card.setImage(nil, animated: false)
                        card.setPlaceholder("加载失败", isVisible: true)
                    }
                    scheduleOneAutomaticCoverRetry(
                        for: item,
                        url: url,
                        loadGeneration: loadGeneration,
                        onImageAspectRatioResolved: onImageAspectRatioResolved
                    )
                }
            }
        }
    }

    private func scheduleOneAutomaticCoverRetry(
        for item: MrdsGalleryItem,
        url: URL,
        loadGeneration: Int,
        onImageAspectRatioResolved: @escaping (CGFloat) -> Void
    ) {
        guard coverLoadAttemptCount == 1 else { return }
        coverRetryTask?.cancel()
        coverRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.failedCoverRetryCooldown))
            guard !Task.isCancelled,
                  let self,
                  representedID == item.id,
                  currentCoverURL == url,
                  coverLoadGeneration == loadGeneration,
                  failedCoverLoadUptime != nil,
                  imageTask == nil else { return }
            coverRetryTask = nil
            loadCover(for: item, onImageAspectRatioResolved: onImageAspectRatioResolved)
        }
    }
}

@MainActor
private final class MrdsGridFooterItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("MrdsGridFooterItem")
    private let footer = MrdsListFooterView()
    override func loadView() {
        view = footer
    }

    func configure(isRefreshing: Bool, errorMessage: String?, canLoadMore: Bool, hasItems: Bool, onRetry: @escaping () -> Void) {
        footer.configure(isRefreshing: isRefreshing, errorMessage: errorMessage, canLoadMore: canLoadMore, hasItems: hasItems)
        footer.onRetry = onRetry
    }
}

@MainActor
private final class MrdsThumbnailView: NSImageView {
    private static let failedLoadRetryCooldown: TimeInterval = 3
    private var task: RemoteImageLoadTask?
    private var retryTask: Task<Void, Never>?
    private var loadedURL: URL?
    private var failedLoadUptime: TimeInterval?
    private var loadAttemptCount = 0
    private var loadGeneration = 0
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func setImage(url: URL?) {
        let sourceChanged = loadedURL != url
        let failedLoadRetryIsDue = failedLoadUptime.map {
            ProcessInfo.processInfo.systemUptime - $0 >= Self.failedLoadRetryCooldown
        } ?? false
        if sourceChanged {
            retryTask?.cancel()
            retryTask = nil
            failedLoadUptime = nil
            loadAttemptCount = 0
        }
        guard sourceChanged || failedLoadRetryIsDue else { return }
        startImageLoad(url: url)
    }

    private func startImageLoad(url: URL?) {
        task?.cancel()
        task = nil
        retryTask?.cancel()
        retryTask = nil
        loadGeneration &+= 1
        let requestGeneration = loadGeneration
        loadedURL = url
        failedLoadUptime = nil
        guard let url else {
            image = nil
            return
        }
        let request = RemoteImagePipeline.shared.request(for: url, priority: .normal, maxPixelSize: 180, configureURLRequest: MrdsRequestFactory.configureImageRequest)
        if let cached = RemoteImagePipeline.shared.cachedImage(with: request) {
            image = cached
            failedLoadUptime = nil
            loadAttemptCount = 0
            return
        }
        loadAttemptCount += 1
        task = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self,
                      loadedURL == url,
                      loadGeneration == requestGeneration else { return }
                task = nil
                self.image = image
                failedLoadUptime = image == nil ? ProcessInfo.processInfo.systemUptime : nil
                if image == nil {
                    scheduleOneAutomaticRetry(for: url, loadGeneration: requestGeneration)
                } else {
                    loadAttemptCount = 0
                }
            }
        }
    }

    private func scheduleOneAutomaticRetry(for url: URL, loadGeneration: Int) {
        guard loadAttemptCount == 1 else { return }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.failedLoadRetryCooldown))
            guard !Task.isCancelled,
                  let self,
                  loadedURL == url,
                  self.loadGeneration == loadGeneration,
                  image == nil,
                  failedLoadUptime != nil,
                  task == nil else { return }
            retryTask = nil
            startImageLoad(url: url)
        }
    }
}
