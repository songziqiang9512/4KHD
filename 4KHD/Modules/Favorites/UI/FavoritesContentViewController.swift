import AppKit
import Observation

/// 统一收藏列表:列表 / 瀑布流网格双布局,交互与 MissKon/4KHD 一致
/// (单击选中、双击打开详情、hover 高亮、方向键、右键菜单、搜索高亮)。
/// 木瓜视频 / 91PORNY / 糖心Vlog 收藏双击直接播放，不打开详情栏。
@MainActor
final class FavoritesContentViewController: NSViewController, WorkspaceFocusable {
    let moduleStore: FavoritesModuleStore
    private let preferences: FavoritesContentPreferences
    private let detailPane: WorkspaceDetailPaneController
    private let tableView = WorkspaceTableView()
    private let tableScrollView = NSScrollView()
    private let gridView = FavoritesGridContainerView()
    private var activeView: NSView?
    private var isObserving = false
    private var isApplyingSelection = false
    private var lastAppliedRecordIdentities: [FavoritesModuleStore.SelectionIdentity] = []
    private var lastGridColumnCount = 4
    private var pendingScrollRecordIdentity: FavoritesModuleStore.SelectionIdentity?
    private var lastSearchQuery: String?
    /// 行渲染用的记录快照,避免每行经 visibleRecords 计算属性全量重算(O(n²))。
    private var recordsSnapshot: [FavoriteRecord] = []
    private let reloadQueue = WorkspaceCoalescingQueue(
        name: "FavoritesContent Reload",
        interval: 0.05,
        maxInterval: 0.12
    )

    private static let tableRowHeight: CGFloat = 96

    init(
        moduleStore: FavoritesModuleStore,
        preferences: FavoritesContentPreferences,
        detailPane: WorkspaceDetailPaneController
    ) {
        self.moduleStore = moduleStore
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

    func focus() {
        switch preferences.layout {
        case .list:
            tableView.window?.makeFirstResponderUnlessDescendantIsFirstResponder(tableView)
        case .grid:
            gridView.focus()
        }
    }

    // MARK: - 布局搭建

    private func setupTable() {
        tableScrollView.drawsBackground = false
        tableScrollView.borderType = .noBorder
        tableScrollView.automaticallyAdjustsContentInsets = true
        tableScrollView.hasVerticalScroller = true
        tableScrollView.contentView.drawsBackground = false
        tableScrollView.documentView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FavoritesRecord"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.tableRowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 3)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .controlBackgroundColor
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.contextMenuProvider = { [weak self] row in
            guard let self, let record = self.record(at: row) else { return nil }
            self.moduleStore.select(record: record)
            self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            return self.makeContextMenu(for: record)
        }
        tableView.keyboardContext = WorkspaceKeyboardContext(
            stepSelection: { [weak self] delta in
                self?.selectAdjacentFromTable(delta: delta) ?? false
            },
            onEscape: { [weak self] in self?.clearSearch() ?? false },
            onEnter: { [weak self] in
                self?.activateSelectedTableItem()
                return true
            }
        )
        tableView.target = self
        tableView.doubleAction = #selector(activateSelectedTableItem)
    }

    private func setupGrid() {
        gridView.onSelect = { [weak self] record in
            self?.moduleStore.select(record: record)
        }
        gridView.onOpenDetail = { [weak self] in
            guard let self, let record = self.moduleStore.selectedRecord else { return }
            self.activate(record)
        }
        gridView.contextMenuProvider = { [weak self] record in
            guard let self else { return nil }
            self.moduleStore.select(record: record)
            return self.makeContextMenu(for: record)
        }
    }

    // MARK: - 状态观察

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = moduleStore.visibleRecords
            _ = moduleStore.selectedRecordIdentity
            _ = moduleStore.selectedRecord
            _ = moduleStore.activeSearchQuery
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

    // MARK: - 内容刷新

    private func reloadContent() {
        moduleStore.reconcileSelection()
        let records = moduleStore.visibleRecords
        recordsSnapshot = records
        let recordIdentities = records.map { moduleStore.selectionIdentity(for: $0) }
        let recordsChanged = recordIdentities != lastAppliedRecordIdentities
        lastAppliedRecordIdentities = recordIdentities
        let searchQueryChanged = lastSearchQuery != moduleStore.activeSearchQuery
        lastSearchQuery = moduleStore.activeSearchQuery

        // 布局切换时保持滚动位置(与其它模块一致)。
        capturePendingScrollRecordIfSwitchingLayout()

        switch preferences.layout {
        case .list:
            setActiveView(tableScrollView)
            if recordsChanged || searchQueryChanged {
                // 搜索词变化即使结果集相同也要刷新行高亮。
                tableView.reloadData()
            }
            syncTableSelection()
            if let pendingScrollRecordIdentity,
               let row = records.firstIndex(where: {
                   moduleStore.selectionIdentity(for: $0) == pendingScrollRecordIdentity
               })
            {
                tableView.scrollRowToVisible(row)
            }
        case .grid:
            setActiveView(gridView)
            let columnCountChanged = preferences.gridColumnCount != lastGridColumnCount
            lastGridColumnCount = preferences.gridColumnCount
            if recordsChanged || columnCountChanged {
                gridView.update(
                    records: records,
                    selectedRecordIdentity: moduleStore.selectedRecordIdentity,
                    searchQuery: moduleStore.activeSearchQuery,
                    minimumColumnCount: FavoritesContentPreferences.minimumGridColumnCount,
                    maximumColumnCount: preferences.gridColumnCount,
                    preferredCardMinimumWidth: 136
                )
            } else {
                gridView.refreshMetadata(
                    selectedRecordIdentity: moduleStore.selectedRecordIdentity,
                    searchQuery: moduleStore.activeSearchQuery
                )
            }
            syncGridSelection()
            if let pendingScrollRecordIdentity {
                DispatchQueue.main.async { [weak self] in
                    self?.gridView.scrollRecordIntoViewIfNeeded(withIdentity: pendingScrollRecordIdentity)
                }
            }
        }
        pendingScrollRecordIdentity = nil
    }

    private func capturePendingScrollRecordIfSwitchingLayout() {
        if activeView === gridView, preferences.layout == .list {
            pendingScrollRecordIdentity = gridView.firstVisibleRecordIdentity()
        } else if activeView === tableScrollView, preferences.layout == .grid {
            pendingScrollRecordIdentity = firstVisibleTableRecordIdentity()
        }
    }

    private func firstVisibleTableRecordIdentity() -> FavoritesModuleStore.SelectionIdentity? {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else { return nil }
        let upperBound = min(visibleRows.location + visibleRows.length, recordsSnapshot.count)
        guard visibleRows.location < upperBound else { return nil }
        for row in visibleRows.location ..< upperBound {
            if let record = record(at: row) {
                return moduleStore.selectionIdentity(for: record)
            }
        }
        return nil
    }

    private func setActiveView(_ nextView: NSView) {
        animateViewTransition(to: nextView, activeView: &activeView)
    }

    private func syncTableSelection() {
        guard preferences.layout == .list else { return }
        guard let selectedRecordIdentity = moduleStore.selectedRecordIdentity,
              let row = recordsSnapshot.firstIndex(where: {
                  moduleStore.selectionIdentity(for: $0) == selectedRecordIdentity
              })
        else {
            if tableView.selectedRow >= 0 {
                isApplyingSelection = true
                tableView.deselectAll(nil)
                isApplyingSelection = false
            }
            return
        }
        guard tableView.selectedRow != row else { return }
        isApplyingSelection = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        isApplyingSelection = false
    }

    private func syncGridSelection() {
        guard preferences.layout == .grid else { return }
        gridView.refreshMetadata(
            selectedRecordIdentity: moduleStore.selectedRecordIdentity,
            searchQuery: moduleStore.activeSearchQuery
        )
    }

    private func record(at index: Int) -> FavoriteRecord? {
        guard recordsSnapshot.indices.contains(index) else { return nil }
        return recordsSnapshot[index]
    }

    private func selectAdjacentFromTable(delta: Int) -> Bool {
        guard preferences.layout == .list, !recordsSnapshot.isEmpty else { return false }
        let records = recordsSnapshot
        let current = moduleStore.selectedRecordIdentity.flatMap { identity in
            records.firstIndex { moduleStore.selectionIdentity(for: $0) == identity }
        } ?? (delta < 0 ? records.count : -1)
        let next = min(max(current + delta, 0), records.count - 1)
        guard next != current, records.indices.contains(next) else { return false }
        moduleStore.select(record: records[next])
        return true
    }

    private func clearSearch() -> Bool {
        guard moduleStore.activeSearchQuery != nil else { return false }
        moduleStore.clearSearch()
        return true
    }

    @objc private func activateSelectedTableItem() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard let record = record(at: row) else { return }
        activate(record)
    }

    private func activate(_ record: FavoriteRecord) {
        moduleStore.select(record: record)
        if playsFromFeed(record) {
            playFavoriteVideo(record)
            return
        }
        detailPane.setPresented(true)
    }

    private func playsFromFeed(_ record: FavoriteRecord) -> Bool {
        FavoriteSourceAdapterRegistry.shared.adapter(for: record)?.playsFromFeed == true
    }

    private func playFavoriteVideo(_ record: FavoriteRecord) {
        Task { [weak self] in
            await self?.performFavoriteVideoAction(record, title: "无法播放") { record, url, actions in
                actions.play(record, url)
            }
        }
    }

    private func saveFavoriteVideo(_ record: FavoriteRecord) {
        Task { [weak self] in
            await self?.performFavoriteVideoAction(record, title: "无法下载视频") { record, url, actions in
                actions.saveAsMP4(record, url)
            }
        }
    }

    private func performFavoriteVideoAction(
        _ record: FavoriteRecord,
        title: String,
        action: @MainActor (FavoriteRecord, URL, FavoriteVideoActions) -> Void
    ) async {
        guard let adapter = FavoriteSourceAdapterRegistry.shared.adapter(for: record),
              let actions = adapter.videoActions
        else { return }
        do {
            let url = try await adapter.resolvePlayableVideoURL(for: record)
            action(record, url, actions)
        } catch is CancellationError {
            return
        } catch {
            let alert = makeAppAlert(
                title: title,
                message: error.localizedDescription,
                style: .warning
            )
            presentAppAlert(alert, in: view.window)
        }
    }

    // MARK: - 右键菜单

    private func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard let record = record(at: row) else { return nil }
        return makeContextMenu(for: record)
    }

    private func makeContextMenu(for record: FavoriteRecord) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if playsFromFeed(record) {
            menu.addItem(menuItem(
                "播放",
                action: #selector(playFromMenu(_:)),
                representedObject: record,
                symbolName: "play.fill"
            ))
            let downloadItem = menuItem(
                "下载视频",
                action: #selector(saveFromMenu(_:)),
                representedObject: record,
                symbolName: "arrow.down.circle"
            )
            downloadItem.isEnabled = FavoriteSourceAdapterRegistry.shared
                .adapter(for: record)?.videoActions?.canSaveAsMP4 == true
            menu.addItem(downloadItem)
            menu.addItem(.separator())
        }

        let unfavoriteItem = NSMenuItem(
            title: "取消收藏",
            action: #selector(unfavoriteFromMenu(_:)),
            keyEquivalent: ""
        )
        unfavoriteItem.target = self
        unfavoriteItem.representedObject = record
        unfavoriteItem.image = NSImage(systemSymbolName: "heart.slash", accessibilityDescription: "取消收藏")
        menu.addItem(unfavoriteItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "在浏览器中打开", action: #selector(openInBrowser(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = record
        openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "在浏览器中打开")
        menu.addItem(openItem)

        let copyItem = NSMenuItem(title: "复制链接", action: #selector(copyDetailLink(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = record
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制链接")
        menu.addItem(copyItem)

        let shareItem = NSMenuItem(title: "分享...", action: #selector(shareRecord(_:)), keyEquivalent: "")
        shareItem.target = self
        shareItem.representedObject = record
        shareItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "分享")
        menu.addItem(shareItem)

        return menu
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        representedObject: Any,
        symbolName: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        if let symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        }
        return item
    }

    @objc private func playFromMenu(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? FavoriteRecord else { return }
        moduleStore.select(record: record)
        playFavoriteVideo(record)
    }

    @objc private func saveFromMenu(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? FavoriteRecord else { return }
        moduleStore.select(record: record)
        saveFavoriteVideo(record)
    }

    @objc private func unfavoriteFromMenu(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? FavoriteRecord else { return }
        Task {
            do {
                try await moduleStore.favoritesStore.toggle(record)
            } catch {
                let alert = makeAppAlert(
                    title: "取消收藏失败",
                    message: error.localizedDescription,
                    style: .warning
                )
                presentAppAlert(alert, in: view.window)
            }
        }
    }

    @objc private func openInBrowser(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? FavoriteRecord,
              let url = URL(string: record.detailURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyDetailLink(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? FavoriteRecord else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.detailURL, forType: .string)
    }

    @objc private func shareRecord(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? FavoriteRecord,
              let url = URL(string: record.detailURL) else { return }
        SharingPresenter.show(items: [url], of: view, preferredEdge: .maxX)
    }
}

// MARK: - 列表数据源

extension FavoritesContentViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int {
        recordsSnapshot.count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard let record = record(at: row) else { return nil }
        let cell = tableView.makeView(withIdentifier: FavoritesListRowView.reuseID, owner: self)
            as? FavoritesListRowView ?? FavoritesListRowView()
        cell.configure(
            record: record,
            source: FavoriteSource.source(for: record),
            searchQuery: moduleStore.activeSearchQuery
        )
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isApplyingSelection else { return }
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        guard let record = record(at: row) else { return }
        moduleStore.select(record: record)
    }
}
