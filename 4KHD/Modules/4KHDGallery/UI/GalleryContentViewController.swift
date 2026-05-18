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
        tableScrollView.automaticallyAdjustsContentInsets = true
        tableScrollView.hasVerticalScroller = true
        tableScrollView.documentView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("GalleryItem"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 96
        tableView.intercellSpacing = NSSize(width: 0, height: 3)
        tableView.usesAlternatingRowBackgroundColors = false
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
    }

    private func setupGrid() {
        gridView.onSelect = { [weak self] item in
            self?.library.select(item)
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
            tableView.reloadData()
            syncTableSelection()
        case .grid:
            setActiveView(gridView)
            gridView.update(
                items: library.visibleItems,
                selectedItemID: library.selectedItemID,
                preferredColumnCount: detailPane.gridColumnLimit,
                preferredCardMinimumWidth: detailPane.preferredGridCardMinimumWidth,
                showsFooter: shouldShowFooter,
                isRefreshing: library.isRefreshingList,
                canLoadMore: library.canLoadMoreList,
                isFavorite: { [weak library] item in library?.isFavorite(item) ?? false },
                isCached: { [weak library] item in library?.isCached(item) ?? false }
            )
        }
    }

    private func setActiveView(_ nextView: NSView) {
        guard activeView !== nextView else { return }
        activeView?.removeFromSuperview()
        activeView = nextView
        view.addSubview(nextView)
        nextView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nextView.topAnchor.constraint(equalTo: view.topAnchor),
            nextView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
                self.reloadContent()
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
        if expandedFavoriteAuthorIDs.contains(id) {
            expandedFavoriteAuthorIDs.remove(id)
        } else {
            expandedFavoriteAuthorIDs.insert(id)
        }
        reloadContent()
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
