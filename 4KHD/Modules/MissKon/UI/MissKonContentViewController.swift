import AppKit
import Observation

@MainActor
final class MissKonContentViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, WorkspaceFocusable {
    static let minimumGridColumnCount = MissKonContentPreferences.minimumGridColumnCount

    let library: MissKonGalleryStore
    private let preferences: MissKonContentPreferences
    private let detailPane: WorkspaceDetailPaneController
    private let tableView = MissKonContentTableView()
    private let tableScrollView = NSScrollView()
    private let gridView = MissKonGridContainerView()
    private var activeView: NSView?
    private var isObserving = false
    private var isApplyingSelection = false
    private var lastAppliedVisibleIDs: [MissKonItem.ID] = []
    private var lastShowsFooter = false
    private var lastListSearchQuery: String?
    private var lastListFooterState = ListFooterState()
    private var pendingScrollItemID: MissKonItem.ID?
    private var pendingScrollOffset: CGFloat?
    private var lastSection: MissKonSection?
    private let reloadQueue = WorkspaceCoalescingQueue(name: "MissKonContent Reload", interval: 0.05, maxInterval: 0.12)

    init(library: MissKonGalleryStore, preferences: MissKonContentPreferences, detailPane: WorkspaceDetailPaneController) {
        self.library = library
        self.preferences = preferences
        self.detailPane = detailPane
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

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
        case .list: tableView.window?.makeFirstResponderUnlessDescendantIsFirstResponder(tableView)
        case .grid: gridView.focus()
        }
    }

    private func setupTable() {
        tableScrollView.drawsBackground = false
        tableScrollView.borderType = .noBorder
        tableScrollView.automaticallyAdjustsContentInsets = true
        tableScrollView.hasVerticalScroller = true
        tableScrollView.contentView.drawsBackground = false
        tableScrollView.documentView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MissKonItem"))
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
        tableView.contextMenuProvider = { [weak self] row in self?.makeContextMenu(forRow: row) }
        tableView.arrowKeyHandler = { [weak self] delta in self?.selectAdjacentFromTable(delta: delta) ?? false }
        tableView.keyboardContext = WorkspaceKeyboardContext(
            stepSelection: { [weak self] delta in self?.selectAdjacentFromTable(delta: delta) ?? false },
            onEscape: { [weak self] in self?.clearSearch() ?? false },
            onEnter: { [weak self] in self?.openSelectedTableItemInDetail(); return true }
        )
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedTableItemInDetail)
    }

    private func setupGrid() {
        gridView.onSelect = { [weak self] item in self?.library.select(item) }
        gridView.onOpenDetail = { [weak self] in self?.detailPane.setPresented(true) }
        gridView.onNeedsMore = { [weak self] in self?.library.loadMoreListIfNeeded() }
        gridView.onEscape = { [weak self] in self?.clearSearch() ?? false }
        gridView.onRetry = { [weak self] in self?.library.retryLastFailure() }
        gridView.contextMenuProvider = { [weak self] item in self?.makeContextMenu(for: item) }
    }

    private var shouldShowFooter: Bool {
        library.feedErrorMessage != nil || library.isRefreshingList || library.canLoadMoreList || !library.visibleItems.isEmpty
    }

    private func reloadContent() {
        // Save scroll offset for the outgoing section before content changes.
        if let lastSection, lastSection != library.section {
            saveCurrentScrollOffset(for: lastSection)
        }
        lastSection = library.section

        // Capture scroll target for restoring position when returning to a section.
        if let cachedOffset = library.feed.cachedScrollOffsets[library.section] {
            pendingScrollOffset = cachedOffset
            library.feed.cachedScrollOffsets[library.section] = nil
        }

        capturePendingScrollItemIfSwitchingLayout()

        switch preferences.layout {
        case .list:
            setActiveView(tableScrollView)
            let currentShowsFooter = shouldShowFooter
            let currentIDs = library.visibleItems.map(\.id)
            let currentSearchQuery = library.activeSearchQuery
            let currentFooterState = ListFooterState(
                isRefreshing: library.isRefreshingList,
                errorMessage: library.feedErrorMessage,
                canLoadMore: library.canLoadMoreList,
                showsFooter: currentShowsFooter
            )
            if canApplyAppendUpdate(from: lastAppliedVisibleIDs, to: currentIDs),
               currentShowsFooter == lastShowsFooter {
                let insertedRange = lastAppliedVisibleIDs.count..<currentIDs.count
                lastAppliedVisibleIDs = currentIDs
                NSView.performWithoutAnimation {
                    tableView.insertRows(at: IndexSet(integersIn: insertedRange), withAnimation: [])
                }
                reloadFooterRowIfVisible()
            } else if currentIDs != lastAppliedVisibleIDs || currentShowsFooter != lastShowsFooter {
                lastAppliedVisibleIDs = currentIDs
                lastShowsFooter = currentShowsFooter
                NSView.performWithoutAnimation { tableView.reloadData() }
            } else if currentSearchQuery != lastListSearchQuery {
                reloadVisibleListRows()
            } else if currentFooterState != lastListFooterState {
                reloadFooterRowIfVisible()
            }
            lastListSearchQuery = currentSearchQuery
            lastListFooterState = currentFooterState
            syncTableSelection()
            if let pendingScrollItemID,
               let row = library.visibleItems.firstIndex(where: { $0.id == pendingScrollItemID }) {
                tableView.scrollRowToVisible(row)
            } else if let offset = pendingScrollOffset, library.visibleItems.indices.contains(0) {
                let clipView = tableScrollView.contentView
                let clamped = min(max(offset, -tableScrollView.contentInsets.top),
                                  max(0, tableView.frame.height - clipView.bounds.height))
                clipView.setBoundsOrigin(NSPoint(x: 0, y: clamped))
            }
        case .grid:
            setActiveView(gridView)
            gridView.update(
                items: library.visibleItems,
                selectedItemID: library.selectedItemID,
                searchQuery: library.activeSearchQuery,
                minimumColumnCount: Self.minimumGridColumnCount,
                maximumColumnCount: preferences.gridColumnCount,
                preferredCardMinimumWidth: 136,
                showsFooter: shouldShowFooter,
                isRefreshing: library.isRefreshingList,
                errorMessage: library.feedErrorMessage,
                canLoadMore: library.canLoadMoreList
            )
            if let pendingScrollItemID {
                DispatchQueue.main.async { [weak self] in
                    self?.gridView.scrollItemIntoViewIfNeeded(withID: pendingScrollItemID)
                }
            } else if let offset = pendingScrollOffset {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let clipView = self.gridView.scrollView.contentView
                    let maxY = max(0, self.gridView.scrollView.documentView?.frame.height ?? 0 - clipView.bounds.height)
                    clipView.setBoundsOrigin(NSPoint(x: 0, y: min(offset, maxY)))
                }
            }
        }
        pendingScrollItemID = nil
        pendingScrollOffset = nil
    }

    private func reloadVisibleListRows() {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        let totalRows = tableView.numberOfRows
        guard visibleRows.location < totalRows else { return }
        let upperBound = min(visibleRows.location + visibleRows.length, totalRows)
        let rowRange = NSRange(location: visibleRows.location, length: upperBound - visibleRows.location)
        guard rowRange.length > 0 else { return }
        let columnIndexes = IndexSet(integer: 0)
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: rowRange.lowerBound..<rowRange.upperBound), columnIndexes: columnIndexes)
    }

    private func reloadFooterRowIfVisible() {
        guard shouldShowFooter else { return }
        let footerRow = library.visibleItems.count
        guard footerRow < tableView.numberOfRows else { return }
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard NSLocationInRange(footerRow, visibleRows) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: footerRow), columnIndexes: IndexSet(integer: 0))
    }

    private func canApplyAppendUpdate(from oldIDs: [MissKonItem.ID], to newIDs: [MissKonItem.ID]) -> Bool {
        guard !oldIDs.isEmpty, newIDs.count > oldIDs.count else { return false }
        return Array(newIDs.prefix(oldIDs.count)) == oldIDs
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

    private func firstVisibleTableItemID() -> MissKonItem.ID? {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else { return nil }
        let upperBound = min(visibleRows.location + visibleRows.length, library.visibleItems.count)
        guard visibleRows.location < upperBound else { return nil }
        return library.visibleItems[visibleRows.location].id
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
            _ = preferences.layout
            _ = preferences.gridColumnCount
            _ = detailPane.isPresented
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.reloadQueue.add(id: "reload") { [weak self] in self?.reloadContent() }
                self.observeState()
            }
        }
    }

    private func syncTableSelection() {
        guard let selectedID = library.selectedItemID,
              let row = library.visibleItems.firstIndex(where: { $0.id == selectedID }) else {
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
        guard !library.visibleItems.isEmpty else { return false }
        let current = library.selectedItemID.flatMap { id in library.visibleItems.firstIndex { $0.id == id } } ?? 0
        let next = min(max(current + delta, 0), library.visibleItems.count - 1)
        guard next != current, library.visibleItems.indices.contains(next) else { return true }
        library.select(library.visibleItems[next])
        return true
    }

    // 列表单击选中与网格一致：同步 library 选中，详情面板与方向键导航跟随。
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let row = tableView.selectedRow
        guard library.visibleItems.indices.contains(row) else { return }
        library.select(library.visibleItems[row])
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        library.visibleItems.count + (shouldShowFooter ? 1 : 0)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row >= library.visibleItems.count {
            library.loadMoreListIfNeeded()
            let footer = tableView.makeView(withIdentifier: MissKonFooterRowView.reuseID, owner: self) as? MissKonFooterRowView ?? MissKonFooterRowView()
            footer.configure(isRefreshing: library.isRefreshingList, errorMessage: library.feedErrorMessage, canLoadMore: library.canLoadMoreList, hasItems: !library.visibleItems.isEmpty)
            footer.onRetry = { [weak self] in
                guard let self else { return }
                if self.library.feedErrorMessage != nil {
                    self.library.retryLastFailure()
                } else {
                    self.library.loadMoreListIfNeeded()
                }
            }
            return footer
        }
        // Trigger load more when approaching the end
        if row >= library.visibleItems.count - 3 {
            library.loadMoreListIfNeeded()
        }
        let cell = tableView.makeView(withIdentifier: MissKonListRowView.reuseID, owner: self) as? MissKonListRowView ?? MissKonListRowView()
        cell.configure(item: library.visibleItems[row], searchQuery: library.activeSearchQuery)
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        library.visibleItems.indices.contains(row) ? library.visibleItems[row].detailURL as NSURL : nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        row >= library.visibleItems.count ? 34 : 96
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        library.visibleItems.indices.contains(row)
    }

    @objc private func openSelectedTableItemInDetail() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard library.visibleItems.indices.contains(row) else { return }
        library.select(library.visibleItems[row])
        detailPane.setPresented(true)
    }

    // MARK: - Context Menu

    func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard library.visibleItems.indices.contains(row) else { return nil }
        if tableView.selectedRow != row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            library.select(library.visibleItems[row])
        }
        return makeContextMenu(for: library.visibleItems[row])
    }

    func makeContextMenu(for item: MissKonItem) -> NSMenu? {
        let menu = NSMenu(title: "MissKonItemMenu")
        menu.autoenablesItems = false

        let favItem = NSMenuItem(
            title: library.isFavorite(item) ? "取消收藏" : "收藏",
            action: #selector(toggleFavoriteFromMenu(_:)),
            keyEquivalent: ""
        )
        favItem.target = self
        favItem.representedObject = item
        favItem.image = NSImage(systemSymbolName: library.isFavorite(item) ? "bookmark.slash" : "bookmark", accessibilityDescription: nil)
        menu.addItem(favItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "在浏览器中打开", action: #selector(openInBrowser(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "在浏览器中打开")
        menu.addItem(openItem)

        // 详情页解析出 MediaFire 下载链接(短链)后提供快捷入口;
        // 只对当前详情图集显示,避免打开别的图集的链接。
        if library.detail.currentItem?.id == item.id,
           let mediaFireURL = library.detail.mediaFireDownloadURL {
            let mediaFireItem = NSMenuItem(title: "MediaFire", action: #selector(openMediaFire(_:)), keyEquivalent: "")
            mediaFireItem.target = self
            mediaFireItem.representedObject = mediaFireURL
            mediaFireItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "MediaFire")
            menu.addItem(mediaFireItem)
        }

        menu.addItem(.separator())

        let copyItem = NSMenuItem(title: "复制链接", action: #selector(copyDetailLink(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制链接")
        menu.addItem(copyItem)

        let shareItem = NSMenuItem(title: "分享...", action: #selector(shareItem(_:)), keyEquivalent: "")
        shareItem.target = self
        shareItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "分享")
        menu.addItem(shareItem)

        return menu
    }

    @objc private func openInBrowser(_ sender: NSMenuItem) {
        guard let item = library.selectedItemID.flatMap({ id in library.visibleItems.first { $0.id == id } }) else { return }
        NSWorkspace.shared.open(item.detailURL)
    }

    @objc private func openMediaFire(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyDetailLink(_ sender: NSMenuItem) {
        guard let item = library.selectedItemID.flatMap({ id in library.visibleItems.first { $0.id == id } }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.detailURL.absoluteString, forType: .string)
    }

    @objc private func toggleFavoriteFromMenu(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MissKonItem else { return }
        Task {
            do {
                try await library.toggleFavorite(for: item)
                reloadContent()
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

    @objc private func shareItem(_ sender: NSMenuItem) {
        guard let item = library.selectedItemID.flatMap({ id in library.visibleItems.first { $0.id == id } }),
              let row = library.visibleItems.firstIndex(where: { $0.id == item.id }) else { return }
        SharingPresenter.show(items: [item.detailURL as NSURL], relativeTo: tableView.rect(ofRow: row), of: tableView, preferredEdge: .maxX)
    }

    private func saveCurrentScrollOffset(for section: MissKonSection) {
        let offset: CGFloat
        switch preferences.layout {
        case .list:
            offset = tableScrollView.contentView.bounds.origin.y
        case .grid:
            offset = gridView.scrollView.contentView.bounds.origin.y
        }
        library.feed.cachedScrollOffsets[section] = offset
    }

    private func clearSearch() -> Bool {
        guard library.activeSearchQuery != nil else { return false }
        library.clearSearch()
        return true
    }
}

final class MissKonContentTableView: WorkspaceTableView {
    var arrowKeyHandler: ((Int) -> Bool)?
    override func accessibilityLabel() -> String? { "MissKon 图片列表" }
}

private struct ListFooterState: Equatable {
    var isRefreshing = false
    var errorMessage: String?
    var canLoadMore = false
    var showsFooter = false
}
