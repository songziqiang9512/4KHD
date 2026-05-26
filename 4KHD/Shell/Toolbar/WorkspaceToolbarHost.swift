import AppKit
import Observation

@MainActor
final class WorkspaceToolbarHost: NSToolbar, NSToolbarDelegate, NSToolbarItemValidation, NSSearchFieldDelegate {
    private enum ItemID {
        static let sidebarTrackingSeparator = NSToolbarItem.Identifier("WorkspaceToolbar.sidebarTrackingSeparator")
        static let search = NSToolbarItem.Identifier("WorkspaceToolbar.search")
        static let layout = NSToolbarItem.Identifier("WorkspaceToolbar.layout")
        static let localGridColumns = NSToolbarItem.Identifier("WorkspaceToolbar.localGridColumns")
        static let localSort = NSToolbarItem.Identifier("WorkspaceToolbar.localSort")
        static let refresh = NSToolbarItem.Identifier("WorkspaceToolbar.refresh")
        static let favorite = NSToolbarItem.Identifier("WorkspaceToolbar.favorite")
        static let resetZoom = NSToolbarItem.Identifier("WorkspaceToolbar.resetZoom")
        static let immersive = NSToolbarItem.Identifier("WorkspaceToolbar.immersive")
        static let filmstrip = NSToolbarItem.Identifier("WorkspaceToolbar.filmstrip")
        static let detailActions = NSToolbarItem.Identifier("WorkspaceToolbar.detailActions")
        static let share = NSToolbarItem.Identifier("WorkspaceToolbar.share")
        static let detailPane = NSToolbarItem.Identifier("WorkspaceToolbar.detailPane")
        static let importFolder = NSToolbarItem.Identifier("WorkspaceToolbar.importFolder")
    }

    private let appContext: WorkspaceAppContext
    private weak var splitController: WorkspaceSplitViewController?
    private var routeObserverID: UUID?
    private var detailObserverID: UUID?
    private weak var searchItem: NSSearchToolbarItem?
    private weak var localGridColumnsControl: NSSegmentedControl?
    private weak var localSortItem: NSMenuToolbarItem?
    private weak var refreshItem: NSToolbarItem?
    private weak var favoriteItem: NSToolbarItem?
    private weak var resetZoomItem: NSToolbarItem?
    private weak var immersiveItem: NSToolbarItem?
    private weak var filmstripItem: NSToolbarItem?
    private weak var detailActionsItem: NSMenuToolbarItem?
    private weak var shareItem: NSToolbarItem?
    private weak var detailPaneItem: NSToolbarItem?
    private var isObservingToolbarState = false
    private var lastDefaultItemIdentifiers: [NSToolbarItem.Identifier] = []
    private let refreshQueue = WorkspaceCoalescingQueue(
        name: "Workspace Toolbar Refresh",
        interval: 0.05,
        maxInterval: 0.1
    )

    var searchFieldIsAvailable: Bool {
        searchItem?.searchField.window != nil
    }

    init(appContext: WorkspaceAppContext, splitController: WorkspaceSplitViewController) {
        self.appContext = appContext
        self.splitController = splitController
        super.init(identifier: "WorkspaceToolbar")
        displayMode = .iconOnly
        allowsUserCustomization = false
        autosavesConfiguration = false
        delegate = self
        routeObserverID = appContext.routeController.addObserver { [weak self] _ in
            self?.scheduleRefresh()
        }
        detailObserverID = appContext.detailPaneController.addObserver { [weak self] _ in
            self?.scheduleRefresh()
        }
        observeToolbarState()
    }

    deinit {
        if let routeObserverID {
            Task { @MainActor [appContext] in
                appContext.routeController.removeObserver(id: routeObserverID)
            }
        }
        if let detailObserverID {
            Task { @MainActor [appContext] in
                appContext.detailPaneController.removeObserver(id: detailObserverID)
            }
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            .toggleSidebar,
            ItemID.sidebarTrackingSeparator,
            ItemID.localGridColumns,
            ItemID.localSort,
            ItemID.refresh,
            ItemID.favorite,
            ItemID.resetZoom,
            ItemID.immersive,
            ItemID.filmstrip,
            ItemID.detailActions,
            ItemID.share,
            ItemID.detailPane,
            ItemID.importFolder,
            ItemID.search
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        defaultItemIdentifiers()
    }

    private func defaultItemIdentifiers() -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = [
            .flexibleSpace,
            .toggleSidebar,
            ItemID.sidebarTrackingSeparator,
            ItemID.refresh,
            .flexibleSpace
        ]
        if currentModuleID == .localLibrary {
            identifiers.append(ItemID.localGridColumns)
            identifiers.append(ItemID.localSort)
            identifiers.append(ItemID.importFolder)
        }
        if currentModuleID == .missKon {
            identifiers.append(ItemID.localGridColumns)
        }
        if currentModuleID == .fourKHDGallery || currentModuleID == .missKon {
            identifiers.append(ItemID.favorite)
        }
        identifiers += [
            ItemID.resetZoom,
            ItemID.immersive,
            ItemID.filmstrip,
            ItemID.detailActions,
            ItemID.share,
            ItemID.detailPane
        ]
        identifiers.append(ItemID.search)
        return identifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleSidebar:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = splitController
            item.action = #selector(WorkspaceSplitViewController.toggleWorkspaceSidebar(_:))
            item.label = "侧边栏"
            item.paletteLabel = "侧边栏"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "切换侧边栏")
            item.toolTip = "切换侧边栏"
            item.visibilityPriority = .high
            return item
        case ItemID.sidebarTrackingSeparator:
            guard let splitController else { return nil }
            let item = NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitController.splitView,
                dividerIndex: 0
            )
            item.visibilityPriority = .high
            return item
        case ItemID.search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "搜索"
            item.paletteLabel = "搜索"
            item.visibilityPriority = .high
            item.searchField.delegate = self
            item.searchField.sendsSearchStringImmediately = true
            item.searchField.target = self
            item.searchField.action = #selector(searchFieldChanged(_:))
            searchItem = item
            updateSearchField()
            return item
        case ItemID.localGridColumns:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let increaseImage = NSImage(
                systemSymbolName: "minus.magnifyingglass",
                accessibilityDescription: "增加列数"
            ) ?? NSImage()
            let decreaseImage = NSImage(
                systemSymbolName: "plus.magnifyingglass",
                accessibilityDescription: "减少列数"
            ) ?? NSImage()
            let control = NSSegmentedControl(
                images: [increaseImage, decreaseImage],
                trackingMode: .momentary,
                target: self,
                action: #selector(localGridColumnsChanged(_:))
            )
            control.translatesAutoresizingMaskIntoConstraints = false
            control.segmentStyle = .automatic
            control.setWidth(32, forSegment: 0)
            control.setWidth(32, forSegment: 1)
            control.setToolTip("增加列数", forSegment: 0)
            control.setToolTip("减少列数", forSegment: 1)
            control.widthAnchor.constraint(equalToConstant: 72).isActive = true
            control.heightAnchor.constraint(equalToConstant: 28).isActive = true
            item.view = control
            item.label = "列数"
            item.paletteLabel = "列数"
            item.visibilityPriority = .high
            localGridColumnsControl = control
            updateLocalGridColumnsControl()
            return item
        case ItemID.localSort:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "排序"
            item.paletteLabel = "排序"
            item.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "排序")
            item.menu = makeLocalSortMenu()
            item.visibilityPriority = .standard
            localSortItem = item
            updateLocalSortItem()
            return item
        case ItemID.refresh:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(refreshContent(_:))
            item.label = "刷新"
            item.paletteLabel = "刷新"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
            item.toolTip = "刷新当前内容"
            item.visibilityPriority = .high
            refreshItem = item
            updateRefreshItem()
            return item
        case ItemID.favorite:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(toggleFavorite(_:))
            item.label = "收藏"
            item.paletteLabel = "收藏"
            item.visibilityPriority = .standard
            favoriteItem = item
            updateFavoriteItem()
            return item
        case ItemID.resetZoom:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(resetZoom(_:))
            item.label = "适合窗口"
            item.paletteLabel = "适合窗口"
            item.image = NSImage(systemSymbolName: "1.magnifyingglass", accessibilityDescription: "适合窗口")
            item.toolTip = "适合窗口"
            item.visibilityPriority = .standard
            resetZoomItem = item
            updateResetZoomItem()
            return item
        case ItemID.filmstrip:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(toggleFilmstrip(_:))
            item.label = "缩略图"
            item.paletteLabel = "缩略图"
            item.visibilityPriority = .standard
            filmstripItem = item
            updateFilmstripItem()
            return item
        case ItemID.immersive:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(toggleImmersiveMode(_:))
            item.label = "大图模式"
            item.paletteLabel = "大图模式"
            item.visibilityPriority = .high
            immersiveItem = item
            updateImmersiveItem()
            return item
        case ItemID.detailActions:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "操作"
            item.paletteLabel = "操作"
            item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "操作")
            item.visibilityPriority = .standard
            detailActionsItem = item
            updateDetailActionsItem()
            return item
        case ItemID.share:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(shareContent(_:))
            item.label = "共享"
            item.paletteLabel = "共享"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "共享")
            item.toolTip = "共享当前项目"
            item.visibilityPriority = .standard
            shareItem = item
            updateShareItem()
            return item
        case ItemID.detailPane:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = splitController
            item.action = #selector(WorkspaceSplitViewController.toggleWorkspaceDetailPane(_:))
            item.label = "详情区"
            item.paletteLabel = "详情区"
            item.visibilityPriority = .high
            detailPaneItem = item
            configureDetailPaneItem(item)
            return item
        case ItemID.importFolder:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "导入目录"
            item.paletteLabel = "导入目录"
            item.toolTip = "导入本地图片文件夹"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "导入目录")
            item.target = self
            item.action = #selector(importFolder(_:))
            item.visibilityPriority = .standard
            return item
        default:
            return nil
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let searchField = notification.object as? NSSearchField,
              searchField === searchItem?.searchField else { return }
        appContext.toolbarContext.setSearchText(searchField.stringValue, for: currentModuleID)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case ItemID.refresh:
            canRefreshCurrentModule
        case ItemID.localSort:
            currentModuleID == .localLibrary
        case ItemID.localGridColumns:
            canAdjustLocalGridColumns
        case ItemID.favorite:
            canFavoriteCurrentModule
        case ItemID.resetZoom:
            canResetCurrentZoom
        case ItemID.filmstrip:
            canUseFilmstrip
        case ItemID.immersive:
            true
        case ItemID.detailActions:
            appContext.toolbarContext.currentReference(for: currentModuleID) != nil
        case ItemID.share:
            canShareCurrentModule
        default:
            true
        }
    }

    func focusSearchField() -> Bool {
        guard let searchField = searchItem?.searchField else { return false }
        searchField.window?.makeFirstResponder(searchField)
        return true
    }

    func refreshVisibleState() {
        refresh()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let searchField = notification.object as? NSSearchField,
              searchField === searchItem?.searchField else { return }
        appContext.toolbarContext.submitSearch(for: currentModuleID)
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        appContext.toolbarContext.setSearchText(sender.stringValue, for: currentModuleID)
    }

    @objc private func localGridColumnsChanged(_ sender: NSSegmentedControl) {
        let delta: Int
        switch sender.selectedSegment {
        case 0: delta = 1
        case 1: delta = -1
        default: return
        }
        if currentModuleID == .missKon {
            appContext.toolbarContext.adjustMissKonGridColumns(delta: delta)
        } else {
            appContext.toolbarContext.adjustLocalGridColumns(delta: delta)
        }
        refresh()
    }

    @objc private func refreshContent(_ sender: Any?) {
        appContext.toolbarContext.refresh(for: currentModuleID)
        refresh()
    }

    @objc private func toggleFavorite(_ sender: Any?) {
        appContext.toolbarContext.toggleFavorite(for: currentModuleID)
        refresh()
    }

    @objc private func resetZoom(_ sender: Any?) {
        appContext.toolbarContext.resetZoom(for: currentModuleID)
        refresh()
    }

    @objc private func toggleFilmstrip(_ sender: Any?) {
        appContext.toolbarContext.toggleFilmstrip()
        refresh()
    }

    @objc private func toggleImmersiveMode(_ sender: Any?) {
        splitController?.toggleImmersiveMode(sender)
        refresh()
    }

    @objc private func shareContent(_ sender: Any?) {
        let items = appContext.toolbarContext.shareItems(for: currentModuleID)
        guard !items.isEmpty,
              let anchorView = shareItem?.view ?? splitController?.view else { return }
        SharingPresenter.show(items: items, of: anchorView, preferredEdge: .minY)
    }

    @objc private func selectLocalSortField(_ sender: NSMenuItem) {
        guard let field = sender.representedObject as? LocalImageSortField,
              case .local(let snapshot) = appContext.toolbarContext.snapshot(for: currentModuleID) else { return }
        appContext.toolbarContext.setLocalSort(field: field, direction: snapshot.sortDirection)
        refresh()
    }

    @objc private func selectLocalSortDirection(_ sender: NSMenuItem) {
        guard let direction = sender.representedObject as? LocalImageSortDirection,
              case .local(let snapshot) = appContext.toolbarContext.snapshot(for: currentModuleID) else { return }
        appContext.toolbarContext.setLocalSort(field: snapshot.sortField, direction: direction)
        refresh()
    }

    @objc private func importFolder(_ sender: Any?) {
        appContext.importRootFolder()
    }

    @objc private func openCurrentReference(_ sender: Any?) {
        guard let reference = appContext.toolbarContext.currentReference(for: currentModuleID) else { return }
        NSWorkspace.shared.open(reference.url)
    }

    @objc private func showCurrentInspector(_ sender: Any?) {
        WorkspaceInspectorPresenter.show()
    }

    @objc private func saveCurrentImage(_ sender: Any?) {
        appContext.toolbarContext.saveCurrentImage(for: currentModuleID)
        refresh()
    }

    @objc private func revealCurrentFileInFinder(_ sender: Any?) {
        guard let fileURL = appContext.toolbarContext.currentReference(for: currentModuleID)?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    @objc private func quickLookCurrentFile(_ sender: Any?) {
        guard let fileURL = appContext.toolbarContext.currentReference(for: currentModuleID)?.fileURL else { return }
        LocalQuickLookController.shared.open(url: fileURL)
    }

    private var currentModuleID: WorkspaceModuleID {
        appContext.routeController.route.moduleID
    }

    private func scheduleRefresh() {
        refreshQueue.add(id: "refresh") { [weak self] in
            self?.refresh()
        }
    }

    private func observeToolbarState() {
        guard !isObservingToolbarState else { return }
        isObservingToolbarState = true
        withObservationTracking {
            _ = appContext.routeController.route
            _ = appContext.detailPaneController.isPresented
            observeSnapshot(appContext.toolbarContext.snapshot(for: currentModuleID))
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingToolbarState = false
                self.scheduleRefresh()
                self.observeToolbarState()
            }
        }
    }

    private func observeSnapshot(_ snapshot: WorkspaceToolbarSnapshot) {
        switch snapshot {
        case .gallery(let gallerySnapshot):
            _ = gallerySnapshot.searchText
            _ = gallerySnapshot.layout
            _ = gallerySnapshot.isRefreshing
            _ = gallerySnapshot.canFavorite
            _ = gallerySnapshot.isFavorite
            _ = gallerySnapshot.canSelectPreviousImage
            _ = gallerySnapshot.canSelectNextImage
            _ = gallerySnapshot.canSaveImage
            _ = gallerySnapshot.canResetZoom
            _ = gallerySnapshot.canShare
            _ = gallerySnapshot.isFilmstripPresented
        case .local(let localSnapshot):
            _ = localSnapshot.searchText
            _ = localSnapshot.layout
            _ = localSnapshot.sortField
            _ = localSnapshot.sortDirection
            _ = localSnapshot.isRefreshing
            _ = localSnapshot.hasSelection
            _ = localSnapshot.canIncreaseGridColumns
            _ = localSnapshot.canDecreaseGridColumns
            _ = localSnapshot.canSelectPreviousImage
            _ = localSnapshot.canSelectNextImage
            _ = localSnapshot.canSaveImage
            _ = localSnapshot.canResetZoom
            _ = localSnapshot.canShare
            _ = localSnapshot.isFilmstripPresented
        case .missKon(let snapshot):
            _ = snapshot.searchText
            _ = snapshot.layout
            _ = snapshot.isRefreshing
            _ = snapshot.canFavorite
            _ = snapshot.isFavorite
            _ = snapshot.canIncreaseGridColumns
            _ = snapshot.canDecreaseGridColumns
            _ = snapshot.canSelectPreviousImage
            _ = snapshot.canSelectNextImage
            _ = snapshot.canSaveImage
            _ = snapshot.canResetZoom
            _ = snapshot.canShare
            _ = snapshot.isFilmstripPresented
        }
    }

    private func refresh() {
        syncToolbarItemIdentifiers()
        updateSearchField()
        updateLocalGridColumnsControl()
        updateLocalSortItem()
        updateRefreshItem()
        updateFavoriteItem()
        updateResetZoomItem()
        updateImmersiveItem()
        updateFilmstripItem()
        updateDetailActionsItem()
        updateShareItem()
        configureDetailPaneItem(detailPaneItem)
        validateVisibleItems()
    }

    private func updateSearchField() {
        guard let searchField = searchItem?.searchField else { return }
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        let text: String
        switch snapshot {
        case .gallery(let gallerySnapshot):
            text = gallerySnapshot.searchText
            searchField.placeholderString = "搜索 4KHD"
        case .local(let localSnapshot):
            text = localSnapshot.searchText
            searchField.placeholderString = "搜索本地图片"
        case .missKon(let snapshot):
            text = snapshot.searchText
            searchField.placeholderString = "搜索 MissKon"
        }
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    private func updateLocalSortItem() {
        guard let localSortItem else { return }
        localSortItem.menu = makeLocalSortMenu()
        if case .local(let snapshot) = appContext.toolbarContext.snapshot(for: currentModuleID) {
            localSortItem.toolTip = "排序：\(snapshot.sortField.title)，\(snapshot.sortDirection.title)"
        } else {
            localSortItem.toolTip = "本地图片排序"
        }
    }

    private func updateLocalGridColumnsControl() {
        guard let localGridColumnsControl else { return }
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        switch snapshot {
        case .local(let s):
            localGridColumnsControl.setEnabled(s.canIncreaseGridColumns, forSegment: 0)
            localGridColumnsControl.setEnabled(s.canDecreaseGridColumns, forSegment: 1)
        case .missKon(let s):
            localGridColumnsControl.setEnabled(s.canIncreaseGridColumns, forSegment: 0)
            localGridColumnsControl.setEnabled(s.canDecreaseGridColumns, forSegment: 1)
        default:
            localGridColumnsControl.setEnabled(false, forSegment: 0)
            localGridColumnsControl.setEnabled(false, forSegment: 1)
        }
    }

    private func updateRefreshItem() {
        guard let refreshItem else { return }
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        switch snapshot {
        case .gallery(let gallerySnapshot):
            refreshItem.isEnabled = !gallerySnapshot.isRefreshing
            refreshItem.toolTip = gallerySnapshot.isRefreshing ? "正在刷新 4KHD" : "刷新 4KHD"
        case .local(let localSnapshot):
            refreshItem.isEnabled = !localSnapshot.isRefreshing && localSnapshot.hasSelection
            refreshItem.toolTip = localSnapshot.hasSelection ? "刷新本地图片" : "先选择一个本地目录"
        case .missKon(let snapshot):
            refreshItem.isEnabled = !snapshot.isRefreshing
            refreshItem.toolTip = snapshot.isRefreshing ? "正在刷新 MissKon" : "刷新 MissKon"
        }
    }

    private func updateFavoriteItem() {
        guard let favoriteItem else { return }
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        let canFavorite: Bool
        let isFavorite: Bool
        switch snapshot {
        case .gallery(let s):
            canFavorite = s.canFavorite
            isFavorite = s.isFavorite
        case .missKon(let s):
            canFavorite = s.canFavorite
            isFavorite = s.isFavorite
        case .local:
            favoriteItem.isEnabled = false
            favoriteItem.image = NSImage(systemSymbolName: "heart", accessibilityDescription: "收藏")
            favoriteItem.toolTip = "收藏"
            return
        }
        favoriteItem.isEnabled = canFavorite
        if isFavorite {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            favoriteItem.image = NSImage(
                systemSymbolName: "heart.fill", accessibilityDescription: "取消收藏"
            )?.withSymbolConfiguration(config)
        } else {
            favoriteItem.image = NSImage(
                systemSymbolName: "heart", accessibilityDescription: "收藏"
            )
        }
        favoriteItem.toolTip = isFavorite ? "取消收藏" : "收藏"
    }

    private func updateResetZoomItem() {
        guard let resetZoomItem else { return }
        resetZoomItem.isEnabled = canResetCurrentZoom
    }

    private func updateFilmstripItem() {
        guard let filmstripItem else { return }
        let isPresented: Bool
        switch appContext.toolbarContext.snapshot(for: currentModuleID) {
        case .gallery(let snapshot):
            isPresented = snapshot.isFilmstripPresented
            filmstripItem.isEnabled = snapshot.canResetZoom
        case .local(let snapshot):
            isPresented = snapshot.isFilmstripPresented
            filmstripItem.isEnabled = snapshot.hasSelection
        case .missKon(let snapshot):
            isPresented = snapshot.isFilmstripPresented
            filmstripItem.isEnabled = snapshot.canSaveImage
        }
        filmstripItem.image = NSImage(
            systemSymbolName: isPresented ? "rectangle.bottomthird.inset.filled" : "rectangle",
            accessibilityDescription: isPresented ? "隐藏缩略图" : "显示缩略图"
        )
        filmstripItem.toolTip = isPresented ? "隐藏缩略图" : "显示缩略图"
    }

    private func updateImmersiveItem() {
        guard let immersiveItem else { return }
        let isImmersive = splitController?.isImmersiveMode == true
        immersiveItem.image = NSImage(
            systemSymbolName: isImmersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: isImmersive ? "退出大图模式" : "进入大图模式"
        )
        immersiveItem.toolTip = isImmersive ? "退出大图模式" : "进入大图模式"
    }

    private func updateDetailActionsItem() {
        guard let detailActionsItem else { return }
        detailActionsItem.menu = makeDetailActionsMenu()
        detailActionsItem.isEnabled = appContext.toolbarContext.currentReference(for: currentModuleID) != nil
    }

    private func updateShareItem() {
        guard let shareItem else { return }
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        switch snapshot {
        case .gallery(let gallerySnapshot):
            shareItem.isEnabled = gallerySnapshot.canShare
            shareItem.toolTip = gallerySnapshot.canShare ? "共享当前图集链接" : "先选择一个图集"
        case .local(let localSnapshot):
            shareItem.isEnabled = localSnapshot.canShare
            shareItem.toolTip = localSnapshot.canShare ? "共享当前本地图片" : "先选择一张本地图片"
        case .missKon(let snapshot):
            shareItem.isEnabled = snapshot.canShare
            shareItem.toolTip = snapshot.canShare ? "共享当前链接" : "先选择一个图集"
        }
    }

    private var canRefreshCurrentModule: Bool {
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        switch snapshot {
        case .gallery(let gallerySnapshot):
            return !gallerySnapshot.isRefreshing
        case .local(let localSnapshot):
            return !localSnapshot.isRefreshing && localSnapshot.hasSelection
        case .missKon(let snapshot):
            return !snapshot.isRefreshing
        }
    }

    private var canFavoriteCurrentModule: Bool {
        switch appContext.toolbarContext.snapshot(for: currentModuleID) {
        case .gallery(let snapshot):
            return snapshot.canFavorite
        case .missKon(let snapshot):
            return snapshot.canFavorite
        case .local:
            return false
        }
    }

    private var canResetCurrentZoom: Bool {
        switch appContext.toolbarContext.snapshot(for: currentModuleID) {
        case .gallery(let snapshot):
            return snapshot.canResetZoom
        case .local(let snapshot):
            return snapshot.canResetZoom
        case .missKon(let snapshot):
            return snapshot.canResetZoom
        }
    }

    private var canSaveCurrentImage: Bool {
        switch appContext.toolbarContext.snapshot(for: currentModuleID) {
        case .gallery(let snapshot):
            return snapshot.canSaveImage
        case .local(let snapshot):
            return snapshot.canSaveImage
        case .missKon(let snapshot):
            return snapshot.canSaveImage
        }
    }

    private var canUseFilmstrip: Bool {
        switch appContext.toolbarContext.snapshot(for: currentModuleID) {
        case .gallery(let snapshot):
            return snapshot.canResetZoom
        case .local(let snapshot):
            return snapshot.hasSelection
        case .missKon(let snapshot):
            return snapshot.canSaveImage
        }
    }

    private var canShareCurrentModule: Bool {
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        switch snapshot {
        case .gallery(let gallerySnapshot):
            return gallerySnapshot.canShare
        case .local(let localSnapshot):
            return localSnapshot.canShare
        case .missKon(let snapshot):
            return snapshot.canShare
        }
    }

    private var canAdjustLocalGridColumns: Bool {
        guard case .local(let snapshot) = appContext.toolbarContext.snapshot(for: currentModuleID) else {
            return false
        }
        return snapshot.canIncreaseGridColumns || snapshot.canDecreaseGridColumns
    }

    private func configureDetailPaneItem(_ item: NSToolbarItem?) {
        guard let item else { return }
        let isPresented = appContext.detailPaneController.isPresented
        let symbolName = isPresented ? "sidebar.right.filled" : "sidebar.right"
        item.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isPresented ? "隐藏详情区" : "显示详情区"
        ) ?? NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: isPresented ? "隐藏详情区" : "显示详情区")
        item.toolTip = isPresented ? "隐藏右侧详情区" : "显示右侧详情区"
    }

    private func syncToolbarItemIdentifiers() {
        let identifiers = defaultItemIdentifiers()
        guard identifiers != lastDefaultItemIdentifiers else { return }
        lastDefaultItemIdentifiers = identifiers

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let currentIdentifiers = items.map(\.itemIdentifier)
        let targetSet = Set(identifiers)
        let originalSet = Set(currentIdentifiers)

        // Remove items that should no longer be present (iterate in reverse
        // so that earlier indices remain valid after each removal).
        for index in (0..<currentIdentifiers.count).reversed() {
            if !targetSet.contains(currentIdentifiers[index]) {
                removeItem(at: index)
            }
        }

        // Insert new items at their correct target position.  Items already
        // present keep their existing toolbar item object, avoiding the visual
        // flicker that a full remove-all / insert-all would cause.
        for (targetIndex, identifier) in identifiers.enumerated() {
            if !originalSet.contains(identifier) {
                insertItem(withItemIdentifier: identifier, at: targetIndex)
            }
        }

        CATransaction.commit()
    }

    private func makeDetailActionsMenu() -> NSMenu {
        let menu = NSMenu(title: "操作")
        switch currentModuleID {
        case .fourKHDGallery:
            let openItem = NSMenuItem(title: "打开原网页", action: #selector(openCurrentReference(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "在浏览器中打开")
            menu.addItem(openItem)

            let saveItem = NSMenuItem(title: "保存图片...", action: #selector(saveCurrentImage(_:)), keyEquivalent: "")
            saveItem.target = self
            saveItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "保存图片")
            saveItem.isEnabled = canSaveCurrentImage
            menu.addItem(saveItem)

            let infoItem = NSMenuItem(title: "显示信息", action: #selector(showCurrentInspector(_:)), keyEquivalent: "")
            infoItem.target = self
            infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "显示简介")
            menu.addItem(infoItem)
        case .missKon:
            let openItem = NSMenuItem(title: "打开原网页", action: #selector(openCurrentReference(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "在浏览器中打开")
            menu.addItem(openItem)

            let saveItem = NSMenuItem(title: "保存图片...", action: #selector(saveCurrentImage(_:)), keyEquivalent: "")
            saveItem.target = self
            saveItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "保存图片")
            saveItem.isEnabled = canSaveCurrentImage
            menu.addItem(saveItem)

            let infoItem = NSMenuItem(title: "显示信息", action: #selector(showCurrentInspector(_:)), keyEquivalent: "")
            infoItem.target = self
            infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "显示简介")
            menu.addItem(infoItem)
        case .localLibrary:
            let saveItem = NSMenuItem(title: "保存副本...", action: #selector(saveCurrentImage(_:)), keyEquivalent: "")
            saveItem.target = self
            saveItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "保存图片")
            saveItem.isEnabled = canSaveCurrentImage
            menu.addItem(saveItem)

            let quickLookItem = NSMenuItem(title: "快速预览", action: #selector(quickLookCurrentFile(_:)), keyEquivalent: "")
            quickLookItem.target = self
            quickLookItem.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "预览")
            menu.addItem(quickLookItem)

            let revealItem = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealCurrentFileInFinder(_:)), keyEquivalent: "")
            revealItem.target = self
            revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "在访达中显示")
            menu.addItem(revealItem)

            let infoItem = NSMenuItem(title: "显示信息", action: #selector(showCurrentInspector(_:)), keyEquivalent: "")
            infoItem.target = self
            infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "显示简介")
            menu.addItem(infoItem)
        }
        return menu
    }

    private func makeLocalSortMenu() -> NSMenu {
        let menu = NSMenu(title: "排序")
        guard case .local(let snapshot) = appContext.toolbarContext.snapshot(for: currentModuleID) else {
            return menu
        }

        for field in LocalImageSortField.allCases {
            let item = NSMenuItem(title: field.title, action: #selector(selectLocalSortField(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = field
            item.state = field == snapshot.sortField ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for direction in LocalImageSortDirection.allCases {
            let item = NSMenuItem(title: direction.title, action: #selector(selectLocalSortDirection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = direction
            item.state = direction == snapshot.sortDirection ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
}
