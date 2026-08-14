import AppKit
import Observation

@MainActor
final class GalleryContentViewController: NSViewController, WorkspaceFocusable {
    enum Row: Hashable {
        case item(GalleryItem.ID)
        case footer
    }

    let library: FourKHDGalleryStore
    private let preferences: GalleryContentPreferences
    private let detailPane: WorkspaceDetailPaneController
    private let tableView = GalleryContentTableView()
    private let tableScrollView = NSScrollView()
    private let gridView = GalleryGridContainerView()
    private var activeView: NSView?
    var rows: [Row] = []
    var rowItems: [GalleryItem.ID: GalleryItem] = [:]
    private var isObserving = false
    private var isApplyingSelection = false
    private var lastAppliedRows: [Row] = []
    private var lastAppliedGridItemIDs: [GalleryItem.ID] = []
    private var lastGridColumnCount = 4
    private var lastVisibleListSignature: [Int: GalleryVisibleListRowSignature] = [:]
    private var pendingScrollItemID: GalleryItem.ID?
    private let reloadQueue = WorkspaceCoalescingQueue(
        name: "GalleryContent Reload",
        interval: 0.05,
        maxInterval: 0.12
    )

    init(
        library: FourKHDGalleryStore,
        preferences: GalleryContentPreferences,
        detailPane: WorkspaceDetailPaneController
    ) {
        self.library = library
        self.preferences = preferences
        self.detailPane = detailPane
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
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

    func focus() {
        switch preferences.layout {
        case .list:
            tableView.window?.makeFirstResponderUnlessDescendantIsFirstResponder(tableView)
        case .grid:
            gridView.focus()
        }
    }

    private func setupTable() {
        tableScrollView.drawsBackground = false
        tableScrollView.borderType = .noBorder
        tableScrollView.automaticallyAdjustsContentInsets = true
        tableScrollView.hasVerticalScroller = true
        tableScrollView.contentView.drawsBackground = false
        tableScrollView.documentView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("GalleryItem"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 96
        tableView.intercellSpacing = NSSize(width: 0, height: 3)
        tableView.floatsGroupRows = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .controlBackgroundColor
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
        tableView.contextMenuProvider = { [weak self] row in
            self?.makeContextMenu(forRow: row)
        }
        tableView.arrowKeyHandler = { [weak self] delta in
            self?.selectAdjacentFromTable(delta: delta) ?? false
        }
        tableView.keyboardContext = WorkspaceKeyboardContext(
            stepSelection: tableView.arrowKeyHandler,
            onEscape: { [weak self] in self?.clearSearch() ?? false },
            onEnter: { [weak self] in self?.openSelectedTableItemInDetail(); return true }
        )
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedTableItemInDetail)
    }

    private func setupGrid() {
        gridView.onSelect = { [weak self] item in
            self?.library.select(item)
        }
        gridView.onOpenDetail = { [weak self] in
            self?.detailPane.setPresented(true)
        }
        gridView.onNeedsMore = { [weak self] in
            self?.library.loadMoreListIfNeeded()
        }
        gridView.onEscape = { [weak self] in self?.clearSearch() ?? false }
        gridView.onRetry = { [weak self] in self?.library.refreshFromNetwork() }
        gridView.contextMenuProvider = { [weak self] item in
            self?.makeContextMenu(for: item)
        }
    }

    func reloadContent() {
        rebuildRows()
        capturePendingScrollItemIfSwitchingLayout()

        switch preferences.layout {
        case .list:
            setActiveView(tableScrollView)
            if rows != lastAppliedRows {
                lastAppliedRows = rows
                tableView.reloadData()
            } else {
                let visibleSignature = visibleListSignature()
                if visibleSignature != lastVisibleListSignature {
                    reloadVisibleListRows()
                }
            }
            syncTableSelection()
            lastVisibleListSignature = visibleListSignature()
            if let pendingScrollItemID,
               let row = rows.firstIndex(of: .item(pendingScrollItemID)) {
                tableView.scrollRowToVisible(row)
            }
        case .grid:
            setActiveView(gridView)
            let columnCountChanged = preferences.gridColumnCount != lastGridColumnCount
            let itemIDs = library.visibleItems.map(\.id)
            if rows != lastAppliedRows || columnCountChanged || itemIDs != lastAppliedGridItemIDs {
                lastAppliedRows = rows
                lastAppliedGridItemIDs = itemIDs
                lastGridColumnCount = preferences.gridColumnCount
                gridView.update(
                    items: library.visibleItems,
                    selectedItemID: library.selectedItemID,
                    searchQuery: library.activeSearchQuery,
                    minimumColumnCount: GalleryContentPreferences.minimumGridColumnCount,
                    maximumColumnCount: preferences.gridColumnCount,
                    preferredCardMinimumWidth: 136,
                    showsFooter: shouldShowFooter,
                    isRefreshing: library.isRefreshingList,
                    errorMessage: library.feedErrorMessage,
                    canLoadMore: library.canLoadMoreList,
                    isFavorite: { [weak library] item in library?.isFavorite(item) ?? false },
                    isCached: { [weak library] item in library?.isCached(item) ?? false }
                )
            } else {
                gridView.refreshMetadata(
                    selectedItemID: library.selectedItemID,
                    isFavorite: { [weak library] item in library?.isFavorite(item) ?? false },
                    isCached: { [weak library] item in library?.isCached(item) ?? false },
                    isRefreshing: library.isRefreshingList,
                    errorMessage: library.feedErrorMessage,
                    canLoadMore: library.canLoadMoreList,
                    showsFooter: shouldShowFooter
                )
            }
            if let pendingScrollItemID {
                DispatchQueue.main.async { [weak self] in
                    self?.gridView.scrollItemIntoViewIfNeeded(withID: pendingScrollItemID)
                }
            }
        }
        pendingScrollItemID = nil
    }

    private func setActiveView(_ nextView: NSView) {
        animateViewTransition(to: nextView, activeView: &activeView)
    }

    private func capturePendingScrollItemIfSwitchingLayout() {
        if activeView === gridView, preferences.layout == .list {
            pendingScrollItemID = gridView.firstVisibleItemID()
        } else if activeView === tableScrollView, preferences.layout == .grid {
            pendingScrollItemID = firstVisibleTableItemID()
        }
    }

    private func firstVisibleTableItemID() -> GalleryItem.ID? {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else { return nil }
        let upperBound = min(visibleRows.location + visibleRows.length, rows.count)
        guard visibleRows.location < upperBound else { return nil }
        for row in visibleRows.location..<upperBound {
            if case .item(let id) = rows[row] {
                return id
            }
        }
        return nil
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = library.section
            _ = library.selectedItemID
            _ = library.visibleItems
            _ = library.allItems
            _ = library.canLoadMoreList
            _ = library.isRefreshingList
            _ = library.feedErrorMessage
            _ = library.activeSearchQuery
            _ = library.favorites.favorites
            _ = preferences.layout
            _ = preferences.gridColumnCount
            _ = detailPane.isPresented
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.reloadQueue.add(id: "reload") { [weak self] in
                    self?.reloadContent()
                }
                self.observeState()
            }
        }
    }

    private var shouldShowFooter: Bool {
        library.feedErrorMessage != nil || library.isRefreshingList || library.canLoadMoreList || !library.visibleItems.isEmpty
    }

    private func rebuildRows() {
        rows = []
        rowItems = [:]

        for item in library.visibleItems {
            rows.append(.item(item.id))
            rowItems[item.id] = item
        }

        if shouldShowFooter {
            rows.append(.footer)
        }
    }

    private func loadMoreIfNeeded(for row: Int) {
        guard rows.indices.contains(row) else { return }
        switch rows[row] {
        case .item(let id):
            if id == library.visibleItems.last?.id {
                library.loadMoreListIfNeeded()
            }
        case .footer:
            if library.canLoadMoreList {
                library.loadMoreListIfNeeded()
            }
        }
    }

    private func syncTableSelection() {
        guard preferences.layout == .list else { return }
        guard let selectedID = library.selectedItemID,
              let row = rows.firstIndex(of: .item(selectedID)) else {
            isApplyingSelection = true
            tableView.deselectAll(nil)
            isApplyingSelection = false
            return
        }
        guard tableView.selectedRow != row else { return }
        isApplyingSelection = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        isApplyingSelection = false
    }

    private func visibleListSignature() -> [Int: GalleryVisibleListRowSignature] {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else { return [:] }
        var signature: [Int: GalleryVisibleListRowSignature] = [:]
        for row in visibleRows.location..<(visibleRows.location + visibleRows.length) where rows.indices.contains(row) {
            switch rows[row] {
            case .item(let id):
                guard let item = rowItems[id] else { continue }
                signature[row] = GalleryVisibleListRowSignature(
                    row: rows[row],
                    title: item.title,
                    subtitle: item.subtitle,
                    isFavorite: library.isFavorite(item),
                    isCached: library.isCached(item)
                )
            case .footer:
                signature[row] = GalleryVisibleListRowSignature(
                    row: rows[row],
                    title: library.feedErrorMessage ?? "\(library.isRefreshingList)",
                    subtitle: "\(library.canLoadMoreList)",
                    isFavorite: false,
                    isCached: false
                )
            }
        }
        return signature
    }

    private func reloadVisibleListRows() {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0, tableView.numberOfColumns > 0 else { return }
        let validRows = visibleRows.location..<(visibleRows.location + visibleRows.length)
        let rowIndexes = IndexSet(validRows.filter { rows.indices.contains($0) })
        guard !rowIndexes.isEmpty else { return }
        tableView.reloadData(forRowIndexes: rowIndexes, columnIndexes: IndexSet(integer: 0))
    }

    private func selectAdjacentFromTable(delta: Int) -> Bool {
        guard preferences.layout == .list else {
            return false
        }
        guard !rows.isEmpty else { return false }

        let selectedRow = rows.firstIndex { row in
            guard case .item(let id) = row else { return false }
            return id == library.selectedItemID
        }
        let currentRow = selectedRow ?? (tableView.selectedRow >= 0 ? tableView.selectedRow : 0)
        let start = min(max(currentRow + (delta < 0 ? -1 : 1), 0), rows.count - 1)
        let range: AnySequence<Int>
        if delta < 0 {
            range = AnySequence(stride(from: start, through: 0, by: -1))
        } else {
            range = AnySequence(stride(from: start, to: rows.count, by: 1))
        }

        for row in range {
            guard case .item(let id) = rows[row], let item = rowItems[id] else { continue }
            library.select(item)
            return true
        }

        return true
    }

    @objc private func openSelectedTableItemInDetail() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard rows.indices.contains(row), case .item(let id) = rows[row], let item = rowItems[id] else { return }
        library.select(item)
        detailPane.setPresented(true)
    }

}

private struct GalleryVisibleListRowSignature: Equatable {
    let row: GalleryContentViewController.Row
    let title: String
    let subtitle: String
    let isFavorite: Bool
    let isCached: Bool
}

extension GalleryContentViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return 96 }
        switch rows[row] {
        case .item:
            return 96
        case .footer:
            return 34
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .item = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard rows.indices.contains(row),
              case .item(let id) = rows[row],
              let item = rowItems[id] else {
            return nil
        }
        return item.detailURL as NSURL
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        loadMoreIfNeeded(for: row)
        switch rows[row] {
        case .item(let id):
            let view = tableView.makeView(withIdentifier: GalleryListRowView.reuseID, owner: self)
                as? GalleryListRowView ?? GalleryListRowView()
            if let item = rowItems[id] {
                view.configure(
                    item: item,
                    isFavorite: library.isFavorite(item),
                    isCached: library.isCached(item),
                    searchQuery: library.activeSearchQuery
                )
            }
            return view
        case .footer:
            let view = tableView.makeView(withIdentifier: GalleryFooterRowView.reuseID, owner: self)
                as? GalleryFooterRowView ?? GalleryFooterRowView()
            view.configure(
                isRefreshing: library.isRefreshingList,
                errorMessage: library.feedErrorMessage,
                canLoadMore: library.canLoadMoreList,
                hasItems: !library.visibleItems.isEmpty
            )
            view.onRetry = { [weak self] in
                guard let self else { return }
                if self.library.feedErrorMessage != nil {
                    self.library.refreshFromNetwork()
                } else {
                    self.library.loadMoreListIfNeeded()
                }
            }
            return view
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case .item(let id) = rows[row], let item = rowItems[id] else { return }
        library.select(item)
    }

    private func clearSearch() -> Bool {
        guard library.activeSearchQuery != nil else { return false }
        library.clearSearch()
        return true
    }
}

final class GalleryContentTableView: WorkspaceTableView {
    var arrowKeyHandler: ((Int) -> Bool)?

    override func accessibilityLabel() -> String? {
        "4KHD Gallery List"
    }
}
