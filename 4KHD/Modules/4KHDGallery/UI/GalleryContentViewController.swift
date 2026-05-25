import AppKit
import Observation

@MainActor
final class GalleryContentViewController: NSViewController, WorkspaceFocusable {
    enum Row: Hashable {
        case group(String)
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
    private var rowGroups: [String: FavoriteAuthorGroup] = [:]
    var expandedFavoriteAuthorIDs = Set<String>()
    var favoriteAuthorOverrides: [String: String] = [:]
    private var isObserving = false
    private var isApplyingSelection = false
    private var lastAppliedRows: [Row] = []
    private var lastVisibleListSignature: [Int: GalleryVisibleListRowSignature] = [:]
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
        gridView.contextMenuProvider = { [weak self] item in
            self?.makeContextMenu(for: item)
        }
    }

    func reloadContent() {
        favoriteAuthorOverrides = loadFavoriteAuthorOverrides()
        rebuildRows()

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
        case .grid:
            setActiveView(gridView)
            if rows != lastAppliedRows {
                lastAppliedRows = rows
                gridView.update(
                    items: library.visibleItems,
                    selectedItemID: library.selectedItemID,
                    minimumColumnCount: nil,
                    maximumColumnCount: nil,
                    preferredCardMinimumWidth: 136,
                    showsFooter: shouldShowFooter,
                    isRefreshing: library.isRefreshingList,
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
                    canLoadMore: library.canLoadMoreList,
                    showsFooter: shouldShowFooter
                )
            }
        }
    }

    private func setActiveView(_ nextView: NSView) {
        animateViewTransition(to: nextView, activeView: &activeView)
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
            _ = library.activeSearchQuery
            _ = library.favorites.favorites
            _ = preferences.layout
            _ = detailPane.isPresented
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                if self.library.section != .favorites {
                    self.expandedFavoriteAuthorIDs.removeAll()
                }
                self.reloadQueue.add(id: "reload") { [weak self] in
                    self?.reloadContent()
                }
                self.observeState()
            }
        }
    }

    private var shouldShowFooter: Bool {
        library.isRefreshingList || library.canLoadMoreList || !library.visibleItems.isEmpty
    }

    var shouldGroupFavorites: Bool {
        library.section == .favorites && library.activeSearchQuery == nil
    }

    private func rebuildRows() {
        rows = []
        rowItems = [:]
        rowGroups = [:]

        if shouldGroupFavorites {
            let groups = favoriteAuthorGroups
            for group in groups {
                rows.append(.group(group.id))
                rowGroups[group.id] = group
                if expandedFavoriteAuthorIDs.contains(group.id) {
                    for item in group.items {
                        rows.append(.item(item.id))
                        rowItems[item.id] = item
                    }
                }
            }
        } else {
            for item in library.visibleItems {
                rows.append(.item(item.id))
                rowItems[item.id] = item
            }
        }

        if shouldShowFooter {
            rows.append(.footer)
        }
    }

    var favoriteAuthorGroups: [FavoriteAuthorGroup] {
        groupedFavoriteItems()
            .map { author, items in
                FavoriteAuthorGroup(
                    author: author,
                    items: items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { lhs, rhs in
                lhs.author.localizedStandardCompare(rhs.author) == .orderedAscending
            }
    }

    private func groupedFavoriteItems() -> [String: [GalleryItem]] {
        let overrides = favoriteAuthorOverrides
        let automaticItems = library.visibleItems.filter { overrides[$0.detailURL.absoluteString] == nil }
        var grouped = FavoriteAuthorNameParser.group(automaticItems)

        for item in library.visibleItems {
            guard let override = overrides[item.detailURL.absoluteString] else { continue }
            let author = normalizedFavoriteAuthorOverride(override)
            grouped[author, default: []].append(item)
        }
        return grouped
    }

    private func toggleFavoriteGroup(_ id: String) {
        let oldRows = rows
        if expandedFavoriteAuthorIDs.contains(id) {
            expandedFavoriteAuthorIDs.remove(id)
        } else {
            expandedFavoriteAuthorIDs.insert(id)
        }
        rebuildRows()
        if tableScrollView.superview != nil {
            animateTableRowChange(from: oldRows, to: rows)
        } else {
            lastAppliedRows = rows
        }
    }

    private func animateTableRowChange(from oldRows: [Row], to newRows: [Row]) {
        let removed = oldRows.enumerated().filter { !newRows.contains($0.element) }
        let inserted = newRows.enumerated().filter { !oldRows.contains($0.element) }
        let removedSet = IndexSet(removed.map(\.offset))
        let insertedSet = IndexSet(inserted.map(\.offset))
        guard !removedSet.isEmpty || !insertedSet.isEmpty else {
            lastAppliedRows = newRows
            return
        }
        lastAppliedRows = newRows
        tableView.beginUpdates()
        if !removedSet.isEmpty {
            tableView.removeRows(at: removedSet, withAnimation: .slideUp)
        }
        if !insertedSet.isEmpty {
            tableView.insertRows(at: insertedSet, withAnimation: .slideDown)
        }
        tableView.endUpdates()
    }

    private func loadMoreIfNeeded(for row: Int) {
        guard rows.indices.contains(row) else { return }
        switch rows[row] {
        case .item(let id):
            if id == library.visibleItems.last?.id {
                library.loadMoreListIfNeeded()
            }
        case .group(let id):
            if id == favoriteAuthorGroups.last?.id {
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
            case .group(let id):
                signature[row] = GalleryVisibleListRowSignature(
                    row: rows[row],
                    title: rowGroups[id]?.author ?? "",
                    subtitle: "\(rowGroups[id]?.items.count ?? 0)",
                    isFavorite: false,
                    isCached: false
                )
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
                    title: "\(library.isRefreshingList)",
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

        let selectedRow = rows.firstIndex { row in
            guard case .item(let id) = row else { return false }
            return id == library.selectedItemID
        }
        let currentRow = selectedRow ?? (tableView.selectedRow >= 0 ? tableView.selectedRow : 0)
        let start = currentRow + (delta < 0 ? -1 : 1)
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

    private func renameFavoriteGroup(_ group: FavoriteAuthorGroup) {
        guard let newAuthor = promptForFavoriteGroupName(currentName: group.author) else { return }
        var overrides = favoriteAuthorOverrides
        for item in group.items {
            overrides[item.detailURL.absoluteString] = newAuthor
        }
        saveFavoriteAuthorOverrides(overrides)
        expandedFavoriteAuthorIDs.remove(group.id)
        expandedFavoriteAuthorIDs.insert(newAuthor.lowercased())
        reloadContent()
    }

    private func promptForFavoriteGroupName(currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "重命名收藏目录"
        alert.informativeText = "目录名会应用到当前目录下的所有收藏图集。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = currentName
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let newAuthor = normalizedFavoriteAuthorOverride(textField.stringValue)
        guard !newAuthor.isEmpty else { return nil }
        return newAuthor
    }

    private func loadFavoriteAuthorOverrides() -> [String: String] {
        let defaultsKey = "com.songziqiang.4khd.favoriteAuthorOverrides.v1"
        guard let json = UserDefaults.standard.string(forKey: defaultsKey),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func setFavoriteAuthorOverride(_ author: String, for item: GalleryItem) {
        var overrides = favoriteAuthorOverrides
        overrides[item.detailURL.absoluteString] = normalizedFavoriteAuthorOverride(author)
        saveFavoriteAuthorOverrides(overrides)
    }

    func removeFavoriteAuthorOverride(for item: GalleryItem) {
        var overrides = favoriteAuthorOverrides
        overrides[item.detailURL.absoluteString] = nil
        saveFavoriteAuthorOverrides(overrides)
    }

    private func saveFavoriteAuthorOverrides(_ overrides: [String: String]) {
        let defaultsKey = "com.songziqiang.4khd.favoriteAuthorOverrides.v1"
        guard let data = try? JSONEncoder().encode(overrides),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: defaultsKey)
        favoriteAuthorOverrides = overrides
    }

    private func normalizedFavoriteAuthorOverride(_ author: String) -> String {
        let normalized = author
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "未知作者" : normalized
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
        case .group:
            return 32
        case .item:
            return 96
        case .footer:
            return 34
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .group = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .item = rows[row] { return true }
        if case .group(let id) = rows[row] {
            toggleFavoriteGroup(id)
        }
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
        case .group(let id):
            let view = tableView.makeView(withIdentifier: GalleryFavoriteGroupHeaderView.reuseID, owner: self)
                as? GalleryFavoriteGroupHeaderView ?? GalleryFavoriteGroupHeaderView()
            if let group = rowGroups[id] {
                view.configure(group: group, isExpanded: expandedFavoriteAuthorIDs.contains(id))
                view.onRename = { [weak self] in self?.renameFavoriteGroup(group) }
            }
            return view
        case .item(let id):
            let view = tableView.makeView(withIdentifier: GalleryListRowView.reuseID, owner: self)
                as? GalleryListRowView ?? GalleryListRowView()
            if let item = rowItems[id] {
                view.configure(
                    item: item,
                    isFavorite: library.isFavorite(item),
                    isCached: library.isCached(item)
                )
            }
            return view
        case .footer:
            let view = tableView.makeView(withIdentifier: GalleryFooterRowView.reuseID, owner: self)
                as? GalleryFooterRowView ?? GalleryFooterRowView()
            view.configure(isRefreshing: library.isRefreshingList, canLoadMore: library.canLoadMoreList, hasItems: !library.visibleItems.isEmpty)
            return view
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case .item(let id) = rows[row], let item = rowItems[id] else { return }
        library.select(item)
    }
}

final class GalleryContentTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var arrowKeyHandler: ((Int) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func accessibilityLabel() -> String? {
        "4KHD Gallery List"
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        return contextMenuProvider?(row)
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
        super.viewDidEndLiveResize()
    }
}

extension GalleryContentTableView: WorkspaceLiveResizeScrollerHiding {}
