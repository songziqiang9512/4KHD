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
        static let wallhavenFilters = NSToolbarItem.Identifier("WorkspaceToolbar.wallhavenFilters")
        static let wallhavenSave = NSToolbarItem.Identifier("WorkspaceToolbar.wallhavenSave")
        static let wallhavenInfo = NSToolbarItem.Identifier("WorkspaceToolbar.wallhavenInfo")
        static let wallhavenBack = NSToolbarItem.Identifier("WorkspaceToolbar.wallhavenBack")
    }

    private let appContext: WorkspaceAppContext
    private weak var splitController: WorkspaceSplitViewController?
    private var routeObserverID: UUID?
    private var detailObserverID: UUID?
    private weak var searchItem: NSSearchToolbarItem?
    private weak var localGridColumnsControl: NSSegmentedControl?
    private weak var localSortItem: NSMenuToolbarItem?
    private weak var wallhavenFilterItem: NSMenuToolbarItem?
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
            ItemID.wallhavenFilters,
            ItemID.wallhavenSave,
            ItemID.wallhavenInfo,
            ItemID.wallhavenBack,
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
        if currentModuleID == .missKon || currentModuleID == .fourKHDGallery || currentModuleID == .wallhaven {
            identifiers.append(ItemID.localGridColumns)
        }
        if currentModuleID == .wallhaven {
            identifiers.append(ItemID.wallhavenFilters)
        }
        if currentModuleID == .fourKHDGallery || currentModuleID == .missKon || currentModuleID == .wallhaven {
            identifiers.append(ItemID.favorite)
        }
        if currentModuleID == .wallhaven {
            if appContext.wallhavenStore.activeSearchQuery != nil || appContext.wallhavenStore.isBrowsingUploader {
                identifiers.append(ItemID.wallhavenBack)
            }
            identifiers.append(ItemID.wallhavenSave)
            identifiers.append(ItemID.wallhavenInfo)
        } else {
            identifiers.append(ItemID.detailActions)
        }
        identifiers += [
            ItemID.resetZoom,
            ItemID.immersive,
            ItemID.share,
            ItemID.detailPane
        ]
        if currentModuleID != .wallhaven {
            identifiers.append(ItemID.filmstrip)
        }
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
                systemSymbolName: "plus.magnifyingglass",
                accessibilityDescription: "增加列数"
            ) ?? NSImage()
            let decreaseImage = NSImage(
                systemSymbolName: "minus.magnifyingglass",
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
        case ItemID.wallhavenFilters:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "筛选"
            item.paletteLabel = "筛选"
            item.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "筛选")
            item.visibilityPriority = .standard
            wallhavenFilterItem = item
            updateWallhavenFilterItem()
            return item
        case ItemID.wallhavenSave:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(saveCurrentImage(_:))
            item.label = "保存原图"
            item.paletteLabel = "保存原图"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "保存原图")
            item.toolTip = "保存原图"
            item.visibilityPriority = .standard
            return item
        case ItemID.wallhavenInfo:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(showCurrentInspector(_:))
            item.label = "显示信息"
            item.paletteLabel = "显示信息"
            item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "显示简介")
            item.toolTip = "显示简介"
            item.visibilityPriority = .standard
            return item
        case ItemID.wallhavenBack:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(wallhavenClearTagSearch(_:))
            item.label = "返回浏览"
            item.paletteLabel = "返回浏览"
            item.image = NSImage(systemSymbolName: "arrow.backward", accessibilityDescription: "返回浏览")
            item.toolTip = "返回默认浏览"
            item.visibilityPriority = .high
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
        case ItemID.wallhavenSave:
            canSaveCurrentImage
        case ItemID.wallhavenInfo:
            true
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
        switch currentModuleID {
        case .missKon:
            appContext.toolbarContext.adjustMissKonGridColumns(delta: delta)
        case .wallhaven:
            appContext.toolbarContext.adjustWallhavenGridColumns(delta: delta)
        case .fourKHDGallery:
            appContext.toolbarContext.adjustGalleryGridColumns(delta: delta)
        default:
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
            _ = gallerySnapshot.canIncreaseGridColumns
            _ = gallerySnapshot.canDecreaseGridColumns
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
        case .wallhaven(let snapshot):
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
        updateWallhavenFilterItem()
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
        case .wallhaven(let snapshot):
            text = snapshot.searchText
            searchField.placeholderString = "搜索 Wallhaven"
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
        case .gallery(let s):
            localGridColumnsControl.setEnabled(s.canIncreaseGridColumns, forSegment: 0)
            localGridColumnsControl.setEnabled(s.canDecreaseGridColumns, forSegment: 1)
        case .wallhaven(let s):
            localGridColumnsControl.setEnabled(s.canIncreaseGridColumns, forSegment: 0)
            localGridColumnsControl.setEnabled(s.canDecreaseGridColumns, forSegment: 1)
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
        case .wallhaven(let snapshot):
            refreshItem.isEnabled = !snapshot.isRefreshing
            refreshItem.toolTip = snapshot.isRefreshing ? "正在刷新 Wallhaven" : "刷新 Wallhaven"
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
        case .wallhaven(let s):
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
        case .wallhaven:
            isPresented = false
            filmstripItem.isEnabled = false
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
        case .wallhaven(let snapshot):
            shareItem.isEnabled = snapshot.canShare
            shareItem.toolTip = snapshot.canShare ? "共享当前链接" : "先选择一张壁纸"
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
        case .wallhaven(let snapshot):
            return !snapshot.isRefreshing
        }
    }

    private var canFavoriteCurrentModule: Bool {
        switch appContext.toolbarContext.snapshot(for: currentModuleID) {
        case .gallery(let snapshot):
            return snapshot.canFavorite
        case .missKon(let snapshot):
            return snapshot.canFavorite
        case .wallhaven(let snapshot):
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
        case .wallhaven(let snapshot):
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
        case .wallhaven(let snapshot):
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
        case .wallhaven:
            return false
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
        case .wallhaven(let snapshot):
            return snapshot.canShare
        }
    }

    private var canAdjustLocalGridColumns: Bool {
        switch appContext.toolbarContext.snapshot(for: currentModuleID) {
        case .local(let snapshot):
            return snapshot.canIncreaseGridColumns || snapshot.canDecreaseGridColumns
        case .missKon(let snapshot):
            return snapshot.canIncreaseGridColumns || snapshot.canDecreaseGridColumns
        case .gallery(let snapshot):
            return snapshot.canIncreaseGridColumns || snapshot.canDecreaseGridColumns
        case .wallhaven(let snapshot):
            return snapshot.canIncreaseGridColumns || snapshot.canDecreaseGridColumns
        }
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
        case .wallhaven:
            let openItem = NSMenuItem(title: "在 Wallhaven 打开", action: #selector(openCurrentReference(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "在浏览器中打开")
            menu.addItem(openItem)

            let saveItem = NSMenuItem(title: "保存原图...", action: #selector(saveCurrentImage(_:)), keyEquivalent: "")
            saveItem.target = self
            saveItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "保存原图")
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

    // MARK: - Wallhaven filter menu

    private func makeWallhavenFilterMenu() -> NSMenu {
        let store = appContext.wallhavenStore
        let menu = NSMenu(title: "筛选")

        // Category submenu
        let catItem = NSMenuItem(title: "分类", action: nil, keyEquivalent: "")
        catItem.submenu = NSMenu(title: "分类")
        for cat in WallhavenCategory.allCases {
            let item = NSMenuItem(title: cat.title, action: #selector(wallhavenSelectCategory(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = cat
            item.state = store.category == cat ? .on : .off
            catItem.submenu?.addItem(item)
        }
        menu.addItem(catItem)

        // Sorting submenu
        let sortItem = NSMenuItem(title: "排序", action: nil, keyEquivalent: "")
        sortItem.submenu = NSMenu(title: "排序")
        for s in WallhavenSorting.allCases {
            let item = NSMenuItem(title: s.title, action: #selector(wallhavenSelectSorting(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            item.state = store.sorting == s ? .on : .off
            sortItem.submenu?.addItem(item)
        }
        menu.addItem(sortItem)

        // Ratio submenu
        let ratioItem = NSMenuItem(title: "比例", action: nil, keyEquivalent: "")
        ratioItem.submenu = NSMenu(title: "比例")
        for r in WallhavenRatio.allCases {
            let item = NSMenuItem(title: r.title, action: #selector(wallhavenSelectRatio(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = r
            item.state = store.ratio == r ? .on : .off
            ratioItem.submenu?.addItem(item)
        }
        menu.addItem(ratioItem)

        // Resolution submenu
        let resItem = NSMenuItem(title: "分辨率", action: nil, keyEquivalent: "")
        resItem.submenu = NSMenu(title: "分辨率")
        for r in WallhavenResolution.allCases {
            let item = NSMenuItem(title: r.title, action: #selector(wallhavenSelectResolution(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = r
            item.state = store.resolution == r ? .on : .off
            resItem.submenu?.addItem(item)
        }
        menu.addItem(resItem)

        // Purity submenu — only relevant items enabled
        let purityItem = NSMenuItem(title: "纯度", action: nil, keyEquivalent: "")
        purityItem.submenu = NSMenu(title: "纯度")
        let allowed = store.allowedPurities
        for p in WallhavenPurity.allCases {
            let item = NSMenuItem(title: p.title, action: #selector(wallhavenSelectPurity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p
            item.state = store.purity == p ? .on : .off
            if !allowed.contains(p) {
                item.isEnabled = false
                item.toolTip = "需要 API Key"
            }
            purityItem.submenu?.addItem(item)
        }
        menu.addItem(purityItem)

        menu.addItem(.separator())

        let keyItem = NSMenuItem(title: "设置 API Key...", action: #selector(wallhavenSetAPIKey(_:)), keyEquivalent: "")
        keyItem.target = self
        keyItem.image = NSImage(systemSymbolName: "key", accessibilityDescription: "设置 API Key")
        menu.addItem(keyItem)

        return menu
    }

    private func updateWallhavenFilterItem() {
        guard currentModuleID == .wallhaven, let wallhavenFilterItem else { return }
        wallhavenFilterItem.menu = makeWallhavenFilterMenu()
    }

    @objc private func wallhavenSelectCategory(_ sender: NSMenuItem) {
        guard let cat = sender.representedObject as? WallhavenCategory else { return }
        appContext.wallhavenStore.setCategory(cat)
    }

    @objc private func wallhavenSelectSorting(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? WallhavenSorting else { return }
        appContext.wallhavenStore.setSorting(s)
    }

    @objc private func wallhavenSelectRatio(_ sender: NSMenuItem) {
        guard let r = sender.representedObject as? WallhavenRatio else { return }
        appContext.wallhavenStore.setRatio(r)
    }

    @objc private func wallhavenSelectResolution(_ sender: NSMenuItem) {
        guard let r = sender.representedObject as? WallhavenResolution else { return }
        appContext.wallhavenStore.setResolution(r)
    }

    @objc private func wallhavenClearTagSearch(_ sender: Any?) {
        if appContext.wallhavenStore.isBrowsingUploader {
            appContext.wallhavenStore.restorePreviousBrowseState()
        } else {
            appContext.wallhavenStore.clearSearch()
        }
        refresh()
    }

    @objc private func wallhavenSelectPurity(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? WallhavenPurity else { return }
        appContext.wallhavenStore.setPurity(p)
    }

    @objc private func wallhavenSetAPIKey(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Wallhaven API Key"
        alert.informativeText = "输入你的 Wallhaven API Key。没有 Key 时仅可用 SFW 内容。"
        alert.alertStyle = .informational

        let inputField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        inputField.placeholderString = "粘贴 API Key"
        inputField.stringValue = appContext.wallhavenStore.feed.accountStore.apiKey ?? ""
        alert.accessoryView = inputField

        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清除")

        alert.window.initialFirstResponder = inputField

        let response = alert.runModal()
        let store = appContext.wallhavenStore.feed.accountStore
        switch response {
        case .alertFirstButtonReturn:
            let key = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            store.apiKey = key.isEmpty ? nil : key
            if let error = store.keychainError {
                let errorAlert = NSAlert()
                errorAlert.messageText = "保存失败，API Key 未启用"
                errorAlert.informativeText = error
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
                // Key was rolled back; don't refresh with invalid state.
            } else {
                appContext.wallhavenStore.refreshFromNetwork()
            }
        case .alertThirdButtonReturn:
            store.apiKey = nil
            appContext.wallhavenStore.refreshFromNetwork()
        default:
            break
        }
        refresh()
    }
}
