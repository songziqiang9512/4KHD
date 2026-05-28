import AppKit
import Nuke
import Observation

@MainActor
final class WallhavenContentViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, WorkspaceFocusable {
    static let minimumGridColumnCount = WallhavenContentPreferences.minimumGridColumnCount

    let library: WallhavenGalleryStore
    private let preferences: WallhavenContentPreferences
    private let detailPane: WorkspaceDetailPaneController
    private let tableView = WallhavenContentTableView()
    private let tableScrollView = NSScrollView()
    private let gridView = WallhavenGridContainerView()
    private var activeView: NSView?
    private var isObserving = false
    private var isApplyingSelection = false
    private var lastAppliedVisibleIDs: [Wallpaper.ID] = []
    private var lastShowsFooter = false
    private var pendingScrollItemID: Wallpaper.ID?
    private let reloadQueue = WorkspaceCoalescingQueue(name: "WallhavenContent Reload", interval: 0.05, maxInterval: 0.12)

    init(library: WallhavenGalleryStore, preferences: WallhavenContentPreferences, detailPane: WorkspaceDetailPaneController) {
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

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("WallhavenItem"))
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
        gridView.onSelect = { [weak self] wallpaper in self?.library.select(wallpaper) }
        gridView.onOpenDetail = { [weak self] in self?.detailPane.setPresented(true) }
        gridView.onNeedsMore = { [weak self] in self?.library.loadMoreIfNeeded() }
        gridView.onEscape = { [weak self] in self?.clearSearch() ?? false }
        gridView.onRetry = { [weak self] in self?.library.refreshFromNetwork() }
        gridView.contextMenuProvider = { [weak self] wallpaper in self?.makeContextMenu(for: wallpaper) }
    }

    private var shouldShowFooter: Bool {
        library.feedErrorMessage != nil || library.isRefreshingList || library.canLoadMoreList || !library.wallpapers.isEmpty
    }

    private func reloadContent() {
        capturePendingScrollItemIfSwitchingLayout()

        switch preferences.layout {
        case .list:
            setActiveView(tableScrollView)
            let currentIDs = library.wallpapers.map(\.id)
            if currentIDs != lastAppliedVisibleIDs || shouldShowFooter != lastShowsFooter {
                lastAppliedVisibleIDs = currentIDs
                lastShowsFooter = shouldShowFooter
                NSView.performWithoutAnimation { tableView.reloadData() }
            } else {
                reloadVisibleListRows()
            }
            syncTableSelection()
            if let pendingScrollItemID,
               let row = library.wallpapers.firstIndex(where: { $0.id == pendingScrollItemID }) {
                tableView.scrollRowToVisible(row)
            }
        case .grid:
            setActiveView(gridView)
            gridView.update(
                wallpapers: library.wallpapers,
                selectedWallpaperID: library.selectedWallpaperID,
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
            }
        }
        pendingScrollItemID = nil
    }

    private func reloadVisibleListRows() {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        let rowRange = NSRange(location: visibleRows.location, length: min(visibleRows.length, library.wallpapers.count - visibleRows.location))
        guard rowRange.length > 0 else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: rowRange.lowerBound..<rowRange.upperBound), columnIndexes: IndexSet(integer: 0))
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

    private func firstVisibleTableItemID() -> Wallpaper.ID? {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else { return nil }
        let upperBound = min(visibleRows.location + visibleRows.length, library.wallpapers.count)
        guard visibleRows.location < upperBound else { return nil }
        return library.wallpapers[visibleRows.location].id
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = library.section
            _ = library.selectedWallpaperID
            _ = library.wallpapers
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
        guard let selectedID = library.selectedWallpaperID,
              let row = library.wallpapers.firstIndex(where: { $0.id == selectedID }) else {
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
        guard !library.wallpapers.isEmpty else { return false }
        let current = library.selectedWallpaperID.flatMap { id in library.wallpapers.firstIndex { $0.id == id } } ?? 0
        let next = min(max(current + delta, 0), library.wallpapers.count - 1)
        guard next != current, library.wallpapers.indices.contains(next) else { return true }
        library.select(library.wallpapers[next])
        return true
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        library.wallpapers.count + (shouldShowFooter ? 1 : 0)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row >= library.wallpapers.count {
            library.loadMoreIfNeeded()
            let footer = tableView.makeView(withIdentifier: WallhavenFooterRowView.reuseID, owner: self) as? WallhavenFooterRowView ?? WallhavenFooterRowView()
            footer.configure(isRefreshing: library.isRefreshingList, errorMessage: library.feedErrorMessage, canLoadMore: library.canLoadMoreList, hasItems: !library.wallpapers.isEmpty)
            footer.onRetry = { [weak self] in
                guard let self else { return }
                if self.library.feedErrorMessage != nil { self.library.refreshFromNetwork() }
                else { self.library.loadMoreIfNeeded() }
            }
            return footer
        }
        if row >= library.wallpapers.count - 3 { library.loadMoreIfNeeded() }
        let cell = tableView.makeView(withIdentifier: WallhavenListRowView.reuseID, owner: self) as? WallhavenListRowView ?? WallhavenListRowView()
        cell.configure(wallpaper: library.wallpapers[row], searchQuery: library.activeSearchQuery)
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        library.wallpapers.indices.contains(row) ? library.wallpapers[row].sourcePageUrl as NSURL : nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        row >= library.wallpapers.count ? 34 : 96
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        library.wallpapers.indices.contains(row)
    }

    @objc private func openSelectedTableItemInDetail() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard library.wallpapers.indices.contains(row) else { return }
        library.select(library.wallpapers[row])
        detailPane.setPresented(true)
    }

    // MARK: - Context Menu

    func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard library.wallpapers.indices.contains(row) else { return nil }
        if tableView.selectedRow != row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            library.select(library.wallpapers[row])
        }
        return makeContextMenu(for: library.wallpapers[row])
    }

    func makeContextMenu(for wallpaper: Wallpaper) -> NSMenu? {
        let menu = NSMenu(title: "WallhavenWallpaperMenu")
        menu.autoenablesItems = false

        let openItem = NSMenuItem(title: "在浏览器中打开", action: #selector(openInBrowser(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "在浏览器中打开")
        menu.addItem(openItem)

        menu.addItem(.separator())

        let desktopItem = NSMenuItem(title: "设置为桌面壁纸", action: #selector(setDesktopWallpaper(_:)), keyEquivalent: "")
        desktopItem.target = self
        desktopItem.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "设置为桌面壁纸")
        menu.addItem(desktopItem)

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
        guard let wallpaper = library.selectedWallpaperID.flatMap({ id in library.wallpapers.first { $0.id == id } }) else { return }
        NSWorkspace.shared.open(wallpaper.sourcePageUrl)
    }

    @objc private func copyDetailLink(_ sender: NSMenuItem) {
        guard let wallpaper = library.selectedWallpaperID.flatMap({ id in library.wallpapers.first { $0.id == id } }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(wallpaper.sourcePageUrl.absoluteString, forType: .string)
    }

    @objc private func setDesktopWallpaper(_ sender: NSMenuItem) {
        guard let wallpaper = library.selectedWallpaperID.flatMap({ id in library.wallpapers.first { $0.id == id } }) else { return }
        let effective = library.effectiveSelectedWallpaper ?? wallpaper
        guard let fullImageUrl = effective.fullImageUrl else {
            // Trigger detail resolution, user can retry after it completes.
            library.resolveDetail(for: effective)
            let alert = NSAlert()
            alert.messageText = "正在获取原图"
            alert.informativeText = "原图地址尚未解析，已开始加载详情。请稍后重试。"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        downloadAndSetDesktop(url: fullImageUrl, wallpaperID: effective.id, ext: effective.fileExtensionForSave)
    }

    private func downloadAndSetDesktop(url: URL, wallpaperID: String, ext: String) {
        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .veryHigh,
            configureURLRequest: WallhavenRequestFactory.configureImageRequest
        )
        _ = RemoteImagePipeline.shared.loadData(with: request) { data in
            guard let data else {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "下载失败"
                    alert.informativeText = "无法下载壁纸原图"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                return
            }
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("4KHD-Wallpaper", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempFile = tempDir.appendingPathComponent("wallhaven-\(wallpaperID).\(ext)")
            do {
                try data.write(to: tempFile, options: .atomic)
                Task { @MainActor in
                    LocalDesktopWallpaperSetter.setDesktopWallpaper(tempFile)
                }
            } catch {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "保存失败"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    @objc private func shareItem(_ sender: NSMenuItem) {
        guard let wallpaper = library.selectedWallpaperID.flatMap({ id in library.wallpapers.first { $0.id == id } }),
              let row = library.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        SharingPresenter.show(items: [wallpaper.sourcePageUrl as NSURL], relativeTo: tableView.rect(ofRow: row), of: tableView, preferredEdge: .maxX)
    }

    private func clearSearch() -> Bool {
        guard library.activeSearchQuery != nil else { return false }
        library.clearSearch()
        return true
    }
}

final class WallhavenContentTableView: WorkspaceTableView {
    var arrowKeyHandler: ((Int) -> Bool)?
    override func accessibilityLabel() -> String? { "Wallhaven List" }
}
