import AppKit

@MainActor
final class WorkspaceSplitViewController: NSSplitViewController {
    private enum SplitState {
        static let widthsKey = "com.songziqiang.4khd.workspaceSplitWidths.v1"
        static let sidebarHiddenKey = "com.songziqiang.4khd.workspaceSidebarHidden.v1"
        static let defaultSidebarWidth: CGFloat = 240
        static let defaultContentWidth: CGFloat = 430
    }

    private let appContext: WorkspaceAppContext
    private let immersive = ImmersiveController()
    private let sidebarDisclosure = SidebarDisclosureState()
    private let sidebarController: WorkspaceSidebarViewController
    private let contentController: WorkspaceColumnHostController
    private let detailController: WorkspaceColumnHostController
    private let sidebarItem: NSSplitViewItem
    private let contentItem: NSSplitViewItem
    private let detailItem: NSSplitViewItem
    private var routeObserverID: UUID?
    private var detailObserverID: UUID?
    private var immersiveObserverID: UUID?
    private var toolbarMonitor: Any?
    private var didBootstrap = false
    private var didRestoreSplitViewState = false
    private var isRestoringSplitViewState = false
    private var expandedSidebarNodeIDs: [String] = ["group:线上", "group:本地"]

    var isSidebarCollapsed: Bool {
        sidebarItem.isCollapsed
    }

    init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
        sidebarController = WorkspaceSidebarViewController(appContext: appContext)
        contentController = WorkspaceColumnHostController(respectsSafeAreaTop: true)
        detailController = WorkspaceColumnHostController(respectsSafeAreaTop: true)
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
            context: WorkspaceKeyboardContext(
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
        sidebarController.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true

        contentItem.holdingPriority = NSLayoutConstraint.Priority(255)
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
        appContext.detailPaneController.toggle()
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

    @objc func importLocalFolder(_ sender: Any?) {
        appContext.importRootFolder()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(moveFocusToSearchField(_:)):
            return searchFieldIsAvailable
        case #selector(refreshCurrentContent(_:)):
            return canRefreshCurrentModule
        case #selector(importLocalFolder(_:)):
            return true
        case #selector(toggleWorkspaceSidebar(_:)):
            updateToggleSidebarValidationItem(item)
            return true
        case #selector(toggleWorkspaceDetailPane(_:)):
            updateToggleDetailPaneValidationItem(item)
            return true
        case #selector(navigateToSidebar(_:)):
            return !sidebarItem.isCollapsed
        case #selector(navigateToContent(_:)):
            return !contentItem.isCollapsed
        case #selector(navigateToDetail(_:)):
            return !detailItem.isCollapsed
        default:
            return true
        }
    }

    func saveStateToUserDefaults() {
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
        toolbarMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
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

    private var searchFieldIsAvailable: Bool {
        (view.window?.toolbar as? WorkspaceToolbarHost)?.searchFieldIsAvailable == true
    }

    private var currentModuleID: WorkspaceModuleID {
        appContext.routeController.route.moduleID
    }

    private var canRefreshCurrentModule: Bool {
        switch appContext.toolbarContext.snapshot(for: currentModuleID) {
        case .gallery(let gallerySnapshot):
            return !gallerySnapshot.isRefreshing
        case .local(let localSnapshot):
            return !localSnapshot.isRefreshing && localSnapshot.hasSelection
        }
    }

    private func updateToggleSidebarValidationItem(_ item: NSValidatedUserInterfaceItem) {
        guard let menuItem = item as? NSMenuItem else { return }
        menuItem.title = sidebarItem.isCollapsed ? "Show Sidebar" : "Hide Sidebar"
    }

    private func updateToggleDetailPaneValidationItem(_ item: NSValidatedUserInterfaceItem) {
        let isPresented = !detailItem.isCollapsed
        if let menuItem = item as? NSMenuItem {
            menuItem.title = isPresented ? "Hide Detail" : "Show Detail"
            menuItem.state = isPresented ? .on : .off
        }
    }

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        if let state = storedWindowState() {
            expandedSidebarNodeIDs = state.expandedSidebarNodeIDs
            sidebarController.restoreExpandedNodeIDs(state.expandedSidebarNodeIDs)
            appContext.detailPaneController.setPresented(state.isDetailPanePresented)
        } else {
            sidebarController.restoreExpandedNodeIDs(expandedSidebarNodeIDs)
            appContext.detailPaneController.setPresented(legacyDetailPanePresented())
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
        saveWindowStateToUserDefaults(includeHiddenDetailWidth: false)
        guard !immersive.isImmersive else { return }
        if !isPresented {
            saveVisibleSplitViewStateIfNeeded()
        }
        detailItem.isCollapsed = !isPresented
        if isPresented {
            restoreDetailWidthForPresentedDetail()
        }
        splitView.adjustSubviews()
    }

    private func applyImmersiveState(_ immersive: ImmersiveController) {
        view.window?.toolbar?.isVisible = !immersive.isImmersive || immersive.isToolbarVisible
        if immersive.isImmersive {
            setSidebarCollapsed(!immersive.peekRevealing, animated: true)
            contentItem.animator().isCollapsed = !immersive.peekRevealing
            detailItem.animator().isCollapsed = false
        } else {
            setSidebarCollapsed(false, animated: true)
            contentItem.animator().isCollapsed = false
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
            if let state = self.storedWindowState(), state.splitViewWidths.count == 3 {
                self.restoreSplitViewState(state)
            } else if let legacyWidths = self.legacySplitViewWidths(), legacyWidths.count == 3 {
                self.restoreSplitViewWidths(legacyWidths, isSidebarHidden: self.legacySidebarHidden())
            } else {
                self.applyDefaultSplitViewWidths()
            }
        }
    }

    private func restoreSplitViewState(_ state: WorkspaceWindowState) {
        restoreFullScreenState(state.isFullScreen)
        expandedSidebarNodeIDs = state.expandedSidebarNodeIDs
        sidebarController.restoreExpandedNodeIDs(state.expandedSidebarNodeIDs)
        restoreSplitViewWidths(state.splitViewWidths, isSidebarHidden: state.isSidebarHidden)
    }

    private func restoreFullScreenState(_ isFullScreen: Bool) {
        guard isFullScreen,
              let window = view.window,
              !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(self)
    }

    private func restoreSplitViewWidths(_ widths: [Int], isSidebarHidden: Bool) {
        let dividerThickness = splitView.dividerThickness
        let sidebarWidth = CGFloat(widths[0])
        let contentWidth = CGFloat(widths[1])

        if isSidebarHidden {
            splitView.setPosition(0, ofDividerAt: 0)
            splitView.setPosition(contentWidth, ofDividerAt: 1)
        } else {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            splitView.setPosition(sidebarWidth + dividerThickness + contentWidth, ofDividerAt: 1)
        }

        sidebarItem.isCollapsed = isSidebarHidden
    }

    private func applyDefaultSplitViewWidths() {
        let dividerThickness = splitView.dividerThickness
        let windowWidth = view.window?.frame.width ?? view.bounds.width
        let maxContentWidth = max(
            320,
            windowWidth - SplitState.defaultSidebarWidth - detailItem.minimumThickness - (dividerThickness * 2)
        )
        let contentWidth = min(SplitState.defaultContentWidth, maxContentWidth)
        splitView.setPosition(SplitState.defaultSidebarWidth, ofDividerAt: 0)
        splitView.setPosition(SplitState.defaultSidebarWidth + dividerThickness + contentWidth, ofDividerAt: 1)
    }

    private func restoreDetailWidthForPresentedDetail() {
        if let widths = storedWindowState()?.splitViewWidths ?? legacySplitViewWidths(),
           widths.count == 3,
           widths[2] >= Int(detailItem.minimumThickness) {
            restoreDetailWidth(CGFloat(widths[2]))
            return
        }
        applyDefaultSplitViewWidths()
    }

    private func restoreDetailWidth(_ storedDetailWidth: CGFloat) {
        let dividerThickness = splitView.dividerThickness
        let sidebarWidth = sidebarItem.isCollapsed
            ? 0
            : max(splitView.arrangedSubviews.first?.frame.width ?? 0, SplitState.defaultSidebarWidth)
        let windowWidth = view.window?.frame.width ?? view.bounds.width
        let dividerTotal = sidebarItem.isCollapsed ? dividerThickness : dividerThickness * 2
        let maximumDetailWidth = max(
            detailItem.minimumThickness,
            windowWidth - sidebarWidth - 320 - dividerTotal
        )
        let detailWidth = min(max(storedDetailWidth, detailItem.minimumThickness), maximumDetailWidth)
        let contentWidth = max(320, windowWidth - sidebarWidth - detailWidth - dividerTotal)

        if !sidebarItem.isCollapsed {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        }
        splitView.setPosition(sidebarWidth + dividerThickness + contentWidth, ofDividerAt: 1)
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        saveVisibleSplitViewStateIfNeeded()
    }

    private func saveVisibleSplitViewStateIfNeeded() {
        guard didRestoreSplitViewState,
              !isRestoringSplitViewState,
              !immersive.isImmersive,
              splitView.arrangedSubviews.count == 3 else { return }

        guard !detailItem.isCollapsed,
              let widths = currentSplitViewWidths(),
              widths[2] >= Int(detailItem.minimumThickness) else { return }
        saveWindowStateToUserDefaults(widths: widths, includeHiddenDetailWidth: true)
    }

    private func currentSplitViewWidths() -> [Int]? {
        guard let window = view.window,
              splitView.arrangedSubviews.count == 3 else { return nil }

        let dividerThickness = splitView.dividerThickness
        let isSidebarHidden = sidebarItem.isCollapsed
        let detailWidth = splitView.arrangedSubviews[2].frame.width
        let sidebarWidth: CGFloat
        let contentWidth: CGFloat

        if isSidebarHidden {
            sidebarWidth = 0
            contentWidth = window.frame.width - (detailWidth + dividerThickness)
        } else {
            sidebarWidth = splitView.arrangedSubviews[0].frame.width
            contentWidth = window.frame.width - sidebarWidth - detailWidth - (dividerThickness * 2)
        }

        guard sidebarWidth.isFinite,
              contentWidth.isFinite,
              detailWidth.isFinite,
              contentWidth > 0,
              detailWidth > 0 else { return nil }

        return [sidebarWidth, contentWidth, detailWidth].map { Int(floor($0)) }
    }

    private func saveWindowStateToUserDefaults(
        widths: [Int]? = nil,
        includeHiddenDetailWidth: Bool
    ) {
        let fallback = storedWindowState()?.splitViewWidths ?? legacySplitViewWidths() ?? []
        let nextWidths: [Int]
        if let widths {
            nextWidths = widths
        } else if includeHiddenDetailWidth,
                  let current = currentSplitViewWidths(),
                  current.count == 3 {
            nextWidths = current
        } else {
            nextWidths = fallback
        }

        let state = WorkspaceWindowState(
            isFullScreen: view.window?.styleMask.contains(.fullScreen) ?? false,
            splitViewWidths: nextWidths,
            isSidebarHidden: sidebarItem.isCollapsed,
            isDetailPanePresented: appContext.detailPaneController.isPresented,
            expandedSidebarNodeIDs: expandedSidebarNodeIDs
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: WorkspaceWindowState.defaultsKey)
    }

    private func storedWindowState() -> WorkspaceWindowState? {
        guard let data = UserDefaults.standard.data(forKey: WorkspaceWindowState.defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WorkspaceWindowState.self, from: data)
    }

    private func legacySplitViewWidths() -> [Int]? {
        UserDefaults.standard.array(forKey: SplitState.widthsKey) as? [Int]
    }

    private func legacySidebarHidden() -> Bool {
        UserDefaults.standard.bool(forKey: SplitState.sidebarHiddenKey)
    }

    private func legacyDetailPanePresented() -> Bool {
        let stored = UserDefaults.standard.object(forKey: WorkspaceDetailPaneController.defaultsKey) as? Bool
        return stored ?? true
    }

    private func handleToolbarPointer(_ event: NSEvent) {
        guard immersive.isImmersive,
              let window = event.window ?? NSApp.keyWindow,
              window == view.window,
              window.isKeyWindow else { return }
        let topDistance = max(window.frame.height - event.locationInWindow.y, 0)
        immersive.handleToolbarPointer(isNearTop: topDistance <= 72)
        if event.locationInWindow.x <= 6 {
            immersive.revealColumns()
        }
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
        didChangeExpandedNodeIDs expandedNodeIDs: [String]
    ) {
        expandedSidebarNodeIDs = expandedNodeIDs
        saveWindowStateToUserDefaults(includeHiddenDetailWidth: false)
    }

    func sidebarViewControllerKeyboardContext(
        _ controller: WorkspaceSidebarViewController
    ) -> WorkspaceKeyboardContext {
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
}
