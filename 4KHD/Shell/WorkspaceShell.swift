import AppKit

@MainActor
final class WorkspaceSplitViewController: NSSplitViewController {
    private let appContext: WorkspaceAppContext
    private let windowStateStore = WorkspaceWindowStateStore()
    private let immersive = ImmersiveController()
    private let sidebarDisclosure = SidebarDisclosureState()
    private let sidebarController: WorkspaceSidebarViewController
    private let contentController: WorkspaceColumnHostController
    private let detailController: WorkspaceColumnHostController
    private let sidebarItem: NSSplitViewItem
    private let contentItem: NSSplitViewItem
    private let detailItem: NSSplitViewItem
    private lazy var splitLayoutController = WorkspaceSplitLayoutController(
        hostView: view,
        splitView: splitView,
        sidebarItem: sidebarItem,
        detailItem: detailItem,
        stateStore: windowStateStore
    )
    private lazy var commandValidator = WorkspaceCommandValidator(appContext: appContext)
    private var routeObserverID: UUID?
    private var detailObserverID: UUID?
    private var immersiveObserverID: UUID?
    private var toolbarMonitor: Any?
    private let splitResizeStateSaveQueue = WorkspaceCoalescingQueue(
        name: "Workspace Split Resize State Save",
        interval: 0.2,
        maxInterval: 0.8
    )
    private var didBootstrap = false
    private var didRestoreSplitViewState = false
    private var isRestoringSplitViewState = false
    private var isApplyingRememberedSidebarWidth = false
    private var lastPresentedSplitViewWidths: [Int]?
    private var lastSidebarWidth: Int?
    private var activeSplitDividerIndex: Int?
    private var splitViewWidthsBeforeSidebarDrag: [Int]?
    private var isNormalizingDraggedSidebarCollapse = false
    private var isApplyingImmersiveLayout = false
    private var sidebarCollapsedBeforeImmersive = false
    private var contentCollapsedBeforeImmersive = false
    private var expandedSidebarNodeIDs = WorkspaceWindowState.defaultExpandedSidebarNodeIDs

    var isSidebarCollapsed: Bool {
        sidebarItem.isCollapsed
    }

    var isImmersiveMode: Bool {
        immersive.isImmersive
    }

    init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
        sidebarController = WorkspaceSidebarViewController(appContext: appContext)
        contentController = WorkspaceColumnHostController(backgroundMaterial: .contentBackground)
        detailController = WorkspaceColumnHostController(backgroundMaterial: .contentBackground)
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        contentItem = NSSplitViewItem(contentListWithViewController: contentController)
        detailItem = NSSplitViewItem(viewController: detailController)
        super.init(nibName: nil, bundle: nil)
        sidebarController.delegate = self
        configureSplitItems()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.frame.size = NSSize(width: 1280, height: 820)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(detailItem)
        installObservers()
        bootstrapIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { @MainActor [weak self] in
            self?.restoreSplitViewStateIfNeeded()
        }
    }

    override func keyDown(with event: NSEvent) {
        let handled = WorkspaceKeyboardHandler.keyDown(
            event,
            context: makeKeyboardContext()
        )
        if handled {
            return
        }
        super.keyDown(with: event)
    }

    deinit {
        if let routeObserverID {
            let routeController = appContext.routeController
            Task { @MainActor in
                routeController.removeObserver(id: routeObserverID)
            }
        }
        if let detailObserverID {
            let detailPaneController = appContext.detailPaneController
            Task { @MainActor in
                detailPaneController.removeObserver(id: detailObserverID)
            }
        }
        if let immersiveObserverID {
            let immersive = immersive
            Task { @MainActor in
                immersive.removeObserver(id: immersiveObserverID)
            }
        }
        if let toolbarMonitor {
            NSEvent.removeMonitor(toolbarMonitor)
        }
    }

    private func configureSplitItems() {
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        sidebarItem.canCollapse = true
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.minimumThickness = WorkspaceSplitLayoutMetrics.minimumSidebarWidth

        contentItem.holdingPriority = NSLayoutConstraint.Priority(255)
        contentItem.minimumThickness = WorkspaceSplitLayoutMetrics.minimumContentWidth
        if #available(macOS 26.0, *) {
            contentItem.automaticallyAdjustsSafeAreaInsets = true
        }

        detailItem.minimumThickness = 384
        detailItem.canCollapse = true
        if #unavailable(macOS 26.0) {
            detailItem.titlebarSeparatorStyle = .line
        }
    }

    private func setSidebarCollapsed(_ isCollapsed: Bool, animated: Bool) {
        if animated {
            sidebarItem.animator().isCollapsed = isCollapsed
        } else {
            sidebarItem.isCollapsed = isCollapsed
        }
    }

    @objc func toggleWorkspaceSidebar(_ sender: Any?) {
        super.toggleSidebar(sender)
    }

    @objc func toggleWorkspaceDetailPane(_ sender: Any?) {
        if appContext.detailPaneController.isPresented {
            rememberPresentedDetailSplitViewState()
        }
        appContext.detailPaneController.toggle()
    }

    @objc func toggleImmersiveMode(_ sender: Any?) {
        immersive.toggle()
    }

    @objc func navigateToSidebar(_ sender: Any?) {
        _ = focusSidebarColumn()
    }

    @objc func navigateToContent(_ sender: Any?) {
        _ = focusContentColumn()
    }

    @objc func navigateToDetail(_ sender: Any?) {
        _ = focusDetailColumn()
    }

    @objc func moveFocusToSearchField(_ sender: Any?) {
        _ = focusSearchField()
    }

    @objc func refreshCurrentContent(_ sender: Any?) {
        appContext.toolbarContext.refresh(for: currentModuleID)
        refreshToolbarState()
    }

    @objc func toggleCurrentFavorite(_ sender: Any?) {
        appContext.toolbarContext.toggleFavorite(for: currentModuleID)
        refreshToolbarState()
    }

    @objc func selectPreviousImage(_ sender: Any?) {
        appContext.toolbarContext.stepImage(-1, for: currentModuleID)
        refreshToolbarState()
    }

    @objc func selectNextImage(_ sender: Any?) {
        appContext.toolbarContext.stepImage(1, for: currentModuleID)
        refreshToolbarState()
    }

    @objc func setContentListLayout(_ sender: Any?) {
        setContentLayout(isList: true)
    }

    @objc func setContentGridLayout(_ sender: Any?) {
        setContentLayout(isList: false)
    }

    @objc func selectLocalSortFieldFromMenu(_ sender: NSMenuItem) {
        guard let field = sender.representedObject as? LocalImageSortField,
              case .local(let snapshot) = appContext.toolbarContext.snapshot(for: currentModuleID) else { return }
        appContext.toolbarContext.setLocalSort(field: field, direction: snapshot.sortDirection)
        refreshToolbarState()
    }

    @objc func selectLocalSortDirectionFromMenu(_ sender: NSMenuItem) {
        guard let direction = sender.representedObject as? LocalImageSortDirection,
              case .local(let snapshot) = appContext.toolbarContext.snapshot(for: currentModuleID) else { return }
        appContext.toolbarContext.setLocalSort(field: snapshot.sortField, direction: direction)
        refreshToolbarState()
    }

    @objc func openCurrentReference(_ sender: Any?) {
        guard let reference = currentReference else { return }
        NSWorkspace.shared.open(reference.url)
    }

    @objc func showCurrentInspector(_ sender: Any?) {
        WorkspaceInspectorPresenter.show()
    }

    @objc func saveCurrentImage(_ sender: Any?) {
        appContext.toolbarContext.saveCurrentImage(for: currentModuleID)
        refreshToolbarState()
    }

    @objc func resetCurrentZoom(_ sender: Any?) {
        appContext.toolbarContext.resetZoom(for: currentModuleID)
        refreshToolbarState()
    }

    @objc func copyCurrentReference(_ sender: Any?) {
        currentReference?.writeToPasteboard()
    }

    @objc func revealCurrentFileInFinder(_ sender: Any?) {
        guard let fileURL = currentReference?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    @objc func quickLookCurrentFile(_ sender: Any?) {
        guard let fileURL = currentReference?.fileURL else { return }
        LocalQuickLookController.shared.open(url: fileURL)
    }

    @objc func setCurrentFileAsDesktopWallpaper(_ sender: Any?) {
        guard let fileURL = currentReference?.fileURL else { return }
        LocalDesktopWallpaperSetter.setDesktopWallpaper(fileURL)
    }

    @objc func shareCurrentContent(_ sender: Any?) {
        let items = appContext.toolbarContext.shareItems(for: currentModuleID)
        guard !items.isEmpty else { return }
        SharingPresenter.show(items: items, of: view, preferredEdge: .maxY)
    }

    @objc func importLocalFolder(_ sender: Any?) {
        appContext.importRootFolder()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        commandValidator.validate(item, state: commandValidationState)
    }

    func saveStateToUserDefaults() {
        splitResizeStateSaveQueue.performCallsImmediately()
        cacheCurrentSidebarWidth()
        if saveVisibleSplitViewStateIfNeeded() {
            return
        }
        saveWindowStateToUserDefaults(includeHiddenDetailWidth: false)
    }

    private func installObservers() {
        routeObserverID = appContext.routeController.addObserver { [weak self] route in
            self?.reloadColumns(for: route)
        }
        detailObserverID = appContext.detailPaneController.addObserver { [weak self] isPresented in
            self?.applyDetailPaneVisibility(isPresented)
        }
        immersiveObserverID = immersive.addObserver { [weak self] immersive in
            self?.applyImmersiveState(immersive)
        }
        toolbarMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDragged]
        ) { [weak self] event in
            self?.trackSplitDividerDrag(event)
            self?.handleToolbarPointer(event)
            return event
        }
    }

    private func focusSidebarColumn() -> Bool {
        guard !sidebarItem.isCollapsed else { return false }
        sidebarController.focus()
        return true
    }

    private func focusContentColumn() -> Bool {
        guard !contentItem.isCollapsed else { return false }
        contentController.focus()
        return true
    }

    private func focusDetailColumn() -> Bool {
        guard !detailItem.isCollapsed else { return false }
        detailController.focus()
        return true
    }

    private func focusSearchField() -> Bool {
        (view.window?.toolbar as? WorkspaceToolbarHost)?.focusSearchField() ?? false
    }

    private func refreshToolbarState() {
        (view.window?.toolbar as? WorkspaceToolbarHost)?.refreshVisibleState()
    }

    private var currentModuleID: WorkspaceModuleID {
        appContext.routeController.route.moduleID
    }

    private var currentReference: WorkspaceCurrentReference? {
        appContext.toolbarContext.currentReference(for: currentModuleID)
    }

    private var commandValidationState: WorkspaceCommandValidationState {
        WorkspaceCommandValidationState(
            currentModuleID: currentModuleID,
            currentReference: currentReference,
            searchFieldIsAvailable: (view.window?.toolbar as? WorkspaceToolbarHost)?.searchFieldIsAvailable == true,
            isSidebarCollapsed: sidebarItem.isCollapsed,
            isContentCollapsed: contentItem.isCollapsed,
            isDetailCollapsed: detailItem.isCollapsed,
            isImmersive: immersive.isImmersive
        )
    }

    private func makeKeyboardContext() -> WorkspaceKeyboardContext {
        WorkspaceKeyboardContext(
            toggleSidebar: { [weak self] in
                self?.toggleWorkspaceSidebar(nil)
            },
            toggleDetailPane: { [weak self] in
                self?.toggleWorkspaceDetailPane(nil)
            },
            focusSidebar: { [weak self] in
                self?.focusSidebarColumn() ?? false
            },
            focusContent: { [weak self] in
                self?.focusContentColumn() ?? false
            },
            focusDetail: { [weak self] in
                self?.focusDetailColumn() ?? false
            }
        )
    }

    private func setContentLayout(isList: Bool) {
        switch currentModuleID {
        case .fourKHDGallery:
            appContext.toolbarContext.setGalleryLayout(isList ? .list : .grid)
        case .localLibrary:
            appContext.toolbarContext.setLocalLayout(isList ? .list : .grid)
        }
        refreshToolbarState()
    }

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        if let state = windowStateStore.load() {
            expandedSidebarNodeIDs = state.expandedSidebarNodeIDs
            cachePresentedSplitViewWidths(state.presentedSplitViewWidths ?? state.splitViewWidths)
            cacheSidebarWidth(state.splitViewWidths.first)
            sidebarController.restoreExpandedNodeIDs(state.expandedSidebarNodeIDs)
            appContext.detailPaneController.setPresented(state.isDetailPanePresented)
        } else {
            let legacyWidths = windowStateStore.legacySplitViewWidths()
            cachePresentedSplitViewWidths(legacyWidths)
            cacheSidebarWidth(legacyWidths?.first)
            sidebarController.restoreExpandedNodeIDs(expandedSidebarNodeIDs)
            appContext.detailPaneController.setPresented(windowStateStore.legacyDetailPanePresented())
        }
        CookieBridge.shared.start()
        appContext.routeController.applyCurrentRoute()
        appContext.moduleRegistry.bootstrapModules()
    }

    private func reloadColumns(for route: WorkspaceRoute) {
        sidebarController.reload()
        let moduleContext = WorkspaceModuleControllerContext(
            appContext: appContext,
            immersive: immersive,
            detailPaneController: appContext.detailPaneController,
            sidebarDisclosure: sidebarDisclosure
        )
        contentController.setContentController(
            appContext.moduleRegistry.contentController(for: route, context: moduleContext)
        )
        detailController.setContentController(
            appContext.moduleRegistry.detailController(for: route, context: moduleContext)
        )
    }

    private func applyDetailPaneVisibility(_ isPresented: Bool) {
        splitResizeStateSaveQueue.performCallsImmediately()
        cacheCurrentSidebarWidth()
        if didRestoreSplitViewState {
            if !isPresented {
                if !saveVisibleSplitViewStateIfNeeded() {
                    saveWindowStateToUserDefaults(includeHiddenDetailWidth: false)
                }
            } else {
                saveWindowStateToUserDefaults(includeHiddenDetailWidth: false)
            }
        }
        guard !immersive.isImmersive else { return }
        detailItem.isCollapsed = !isPresented
        if isPresented {
            splitLayoutController.restoreDetailWidthForPresentedDetail(preferredWidths: lastPresentedSplitViewWidths)
        }
        splitView.adjustSubviews()
    }

    private func applyImmersiveState(_ immersive: ImmersiveController) {
        view.window?.toolbar?.isVisible = !immersive.isImmersive || immersive.isToolbarVisible
        refreshToolbarState()
        if immersive.isImmersive {
            if !isApplyingImmersiveLayout {
                sidebarCollapsedBeforeImmersive = sidebarItem.isCollapsed
                contentCollapsedBeforeImmersive = contentItem.isCollapsed
                isApplyingImmersiveLayout = true
            }
            setSidebarCollapsed(!immersive.peekRevealing, animated: true)
            contentItem.animator().isCollapsed = !immersive.peekRevealing
            detailItem.animator().isCollapsed = false
        } else {
            guard isApplyingImmersiveLayout else { return }
            isApplyingImmersiveLayout = false
            setSidebarCollapsed(sidebarCollapsedBeforeImmersive, animated: true)
            contentItem.animator().isCollapsed = contentCollapsedBeforeImmersive
            applyDetailPaneVisibility(appContext.detailPaneController.isPresented)
        }
    }

    private func restoreSplitViewStateIfNeeded() {
        guard !didRestoreSplitViewState,
              splitView.arrangedSubviews.count == 3 else { return }
        didRestoreSplitViewState = true

        splitView.layoutSubtreeIfNeeded()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRestoringSplitViewState = true
            defer { self.isRestoringSplitViewState = false }
            if let state = self.windowStateStore.load(), state.splitViewWidths.count == 3 {
                self.cachePresentedSplitViewWidths(state.presentedSplitViewWidths ?? state.splitViewWidths)
                self.cacheSidebarWidth(state.splitViewWidths.first)
                self.restoreSplitViewState(state)
            } else if let legacyWidths = self.windowStateStore.legacySplitViewWidths(), legacyWidths.count == 3 {
                self.cachePresentedSplitViewWidths(legacyWidths)
                self.cacheSidebarWidth(legacyWidths.first)
                self.splitLayoutController.restoreSplitViewWidths(
                    legacyWidths,
                    isSidebarHidden: self.windowStateStore.legacySidebarHidden()
                )
            } else {
                self.splitLayoutController.applyDefaultSplitViewWidths()
            }
        }
    }

    private func restoreSplitViewState(_ state: WorkspaceWindowState) {
        restoreFullScreenState(state.isFullScreen)
        expandedSidebarNodeIDs = state.expandedSidebarNodeIDs
        cachePresentedSplitViewWidths(state.presentedSplitViewWidths ?? state.splitViewWidths)
        cacheSidebarWidth(state.splitViewWidths.first)
        sidebarController.restoreExpandedNodeIDs(state.expandedSidebarNodeIDs)
        splitLayoutController.restoreSplitViewWidths(state.splitViewWidths, isSidebarHidden: state.isSidebarHidden)
    }

    private func restoreFullScreenState(_ isFullScreen: Bool) {
        guard isFullScreen,
              let window = view.window,
              !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(self)
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        if isRestoringSplitViewState || isApplyingRememberedSidebarWidth {
            splitResizeStateSaveQueue.add(id: "split-widths") { [weak self] in
                self?.saveSplitViewStateAfterResize()
            }
            return
        }

        if activeSplitDividerIndex == 0, sidebarItem.isCollapsed, !isNormalizingDraggedSidebarCollapse {
            normalizeDraggedSidebarCollapse()
            splitResizeStateSaveQueue.add(id: "split-widths") { [weak self] in
                self?.saveSplitViewStateAfterResize()
            }
            return
        }

        if activeSplitDividerIndex == 0 {
            cacheCurrentSidebarWidth()
        } else if activeSplitDividerIndex == 1 {
            restoreRememberedSidebarWidthIfNeeded()
        }
        splitResizeStateSaveQueue.add(id: "split-widths") { [weak self] in
            self?.saveSplitViewStateAfterResize()
        }
    }

    @discardableResult
    private func saveVisibleSplitViewStateIfNeeded() -> Bool {
        guard didRestoreSplitViewState,
              !isRestoringSplitViewState,
              !immersive.isImmersive,
              splitView.arrangedSubviews.count == 3 else { return false }

        guard !detailItem.isCollapsed,
              let widths = splitLayoutController.currentSplitViewWidths(),
              widths[1] >= Int(WorkspaceSplitLayoutMetrics.minimumContentWidth),
              widths[2] >= Int(detailItem.minimumThickness) else { return false }
        let normalizedWidths = widthsByApplyingRememberedSidebarWidth(to: widths)
        guard normalizedWidths.first ?? 0 >= Int(sidebarItem.minimumThickness) else { return false }
        cachePresentedSplitViewWidths(normalizedWidths)
        cacheSidebarWidth(normalizedWidths.first)
        saveWindowStateToUserDefaults(widths: normalizedWidths, includeHiddenDetailWidth: true)
        return true
    }

    private func saveSplitViewStateAfterResize() {
        cacheCurrentSidebarWidth()
        if saveVisibleSplitViewStateIfNeeded() {
            return
        }
        saveWindowStateToUserDefaults(includeHiddenDetailWidth: false)
    }

    private func rememberPresentedDetailSplitViewState() {
        splitResizeStateSaveQueue.performCallsImmediately()
        cacheCurrentSidebarWidth()
        _ = saveVisibleSplitViewStateIfNeeded()
    }

    private func saveWindowStateToUserDefaults(
        widths: [Int]? = nil,
        includeHiddenDetailWidth: Bool
    ) {
        let storedState = windowStateStore.load()
        let fallback = widthsByApplyingRememberedSidebarWidth(to: lastPresentedSplitViewWidths
            ?? storedState?.presentedSplitViewWidths
            ?? storedState?.splitViewWidths
            ?? windowStateStore.legacySplitViewWidths()
            ?? [])
        let nextWidths: [Int]
        if let widths {
            nextWidths = widths
        } else if includeHiddenDetailWidth,
                  let current = splitLayoutController.currentSplitViewWidths(),
                  current.count == 3 {
            nextWidths = current
        } else {
            nextWidths = fallback
        }

        let state = WorkspaceWindowState(
            isFullScreen: view.window?.styleMask.contains(.fullScreen) ?? false,
            splitViewWidths: nextWidths,
            presentedSplitViewWidths: lastPresentedSplitViewWidths ?? nextWidths,
            isSidebarHidden: isApplyingImmersiveLayout ? sidebarCollapsedBeforeImmersive : sidebarItem.isCollapsed,
            isDetailPanePresented: appContext.detailPaneController.isPresented,
            expandedSidebarNodeIDs: expandedSidebarNodeIDs
        )
        windowStateStore.save(state)
    }

    private func cachePresentedSplitViewWidths(_ widths: [Int]?) {
        guard let widths,
              widths.count == 3,
              widths[0] >= Int(sidebarItem.minimumThickness),
              widths[1] >= Int(WorkspaceSplitLayoutMetrics.minimumContentWidth),
              widths[2] >= Int(detailItem.minimumThickness) else { return }
        lastPresentedSplitViewWidths = widths
    }

    private func cacheCurrentSidebarWidth() {
        cacheSidebarWidth(splitLayoutController.currentSidebarWidth())
    }

    private func cacheSidebarWidth(_ width: Int?) {
        guard let width,
              width >= Int(sidebarItem.minimumThickness) else { return }
        lastSidebarWidth = width
    }

    private func widthsByApplyingRememberedSidebarWidth(to widths: [Int]) -> [Int] {
        guard let lastSidebarWidth,
              widths.count == 3 else { return widths }
        var nextWidths = widths
        nextWidths[0] = lastSidebarWidth
        return nextWidths
    }

    private func trackSplitDividerDrag(_ event: NSEvent) {
        guard event.window == view.window else { return }
        switch event.type {
        case .leftMouseDown:
            activeSplitDividerIndex = splitDividerIndex(at: event)
            if activeSplitDividerIndex == 0 {
                splitViewWidthsBeforeSidebarDrag = splitLayoutController.currentSplitViewWidths()
            }
        case .leftMouseDragged:
            if activeSplitDividerIndex == nil {
                activeSplitDividerIndex = splitDividerIndex(at: event)
                if activeSplitDividerIndex == 0 {
                    splitViewWidthsBeforeSidebarDrag = splitLayoutController.currentSplitViewWidths()
                }
            }
        case .leftMouseUp:
            activeSplitDividerIndex = nil
            splitViewWidthsBeforeSidebarDrag = nil
        default:
            break
        }
    }

    private func splitDividerIndex(at event: NSEvent) -> Int? {
        guard splitView.arrangedSubviews.count >= 2 else { return nil }
        let point = splitView.convert(event.locationInWindow, from: nil)
        let tolerance = max(splitView.dividerThickness, 8)
        for dividerIndex in 0..<(splitView.arrangedSubviews.count - 1) {
            let dividerX = splitView.arrangedSubviews[dividerIndex].frame.maxX
            if abs(point.x - dividerX) <= tolerance {
                return dividerIndex
            }
        }
        return nil
    }

    private func restoreRememberedSidebarWidthIfNeeded() {
        guard !sidebarItem.isCollapsed,
              let lastSidebarWidth,
              splitView.arrangedSubviews.count == 3 else { return }

        let currentSidebarWidth = splitView.arrangedSubviews[0].frame.width
        guard currentSidebarWidth.isFinite,
              abs(currentSidebarWidth - CGFloat(lastSidebarWidth)) >= 1 else { return }

        let targetWidth = splitLayoutController.clampedSidebarWidth(CGFloat(lastSidebarWidth))
        guard abs(currentSidebarWidth - targetWidth) >= 1 else { return }
        isApplyingRememberedSidebarWidth = true
        defer { isApplyingRememberedSidebarWidth = false }
        splitView.setPosition(targetWidth, ofDividerAt: 0)
    }

    private func normalizeDraggedSidebarCollapse() {
        guard !isNormalizingDraggedSidebarCollapse else { return }
        isNormalizingDraggedSidebarCollapse = true
        defer { isNormalizingDraggedSidebarCollapse = false }
        let preferredWidths = splitViewWidthsBeforeSidebarDrag ?? lastPresentedSplitViewWidths
        cachePresentedSplitViewWidths(preferredWidths)
        cacheSidebarWidth(preferredWidths?.first)
        splitLayoutController.restoreContentWidthForHiddenSidebar(preferredWidths: preferredWidths)
    }

    private func handleToolbarPointer(_ event: NSEvent) {
        guard immersive.isImmersive,
              let window = event.window ?? NSApp.keyWindow,
              window == view.window,
              window.isKeyWindow else { return }
        let topDistance = max(window.frame.height - event.locationInWindow.y, 0)
        immersive.handleToolbarPointer(isNearTop: topDistance <= 72)
    }
}

extension WorkspaceSplitViewController: WorkspaceSidebarViewControllerDelegate {
    func sidebarViewController(_ controller: WorkspaceSidebarViewController, didSelect route: WorkspaceRoute) {
        appContext.routeController.select(route)
    }

    func sidebarViewControllerDidRequestLocalImport(_ controller: WorkspaceSidebarViewController) {
        appContext.importRootFolder()
    }

    func sidebarViewController(
        _ controller: WorkspaceSidebarViewController,
        didRequestImportLocalFolderAt url: URL
    ) {
        appContext.localLibraryStore.importRootFolder(url)
    }

    func sidebarViewController(
        _ controller: WorkspaceSidebarViewController,
        didRequestRemoveLocalFolder folder: LocalFolderNode
    ) {
        appContext.localLibraryStore.removeFolder(folder)
        if appContext.routeController.route.moduleID == .localLibrary {
            appContext.routeController.applyCurrentRoute()
        }
    }

    func sidebarViewController(
        _ controller: WorkspaceSidebarViewController,
        didChangeExpandedNodeIDs expandedNodeIDs: [String]
    ) {
        expandedSidebarNodeIDs = expandedNodeIDs
        saveWindowStateToUserDefaults(includeHiddenDetailWidth: false)
    }

    func sidebarViewControllerKeyboardContext(
        _ controller: WorkspaceSidebarViewController
    ) -> WorkspaceKeyboardContext {
        makeKeyboardContext()
    }
}
