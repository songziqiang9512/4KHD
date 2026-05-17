import AppKit
import Observation

// MARK: - Immersive 控制器（窗内大图模式）

@MainActor
@Observable
final class ImmersiveController {
    @ObservationIgnored private var observers: [UUID: (ImmersiveController) -> Void] = [:]

    var isImmersive: Bool = false
    var peekRevealing: Bool = false
    var isToolbarVisible: Bool = true
    @ObservationIgnored private var peekHideWorkItem: DispatchWorkItem?

    func toggle() {
        set(!isImmersive)
    }

    func set(_ on: Bool) {
        if on {
            peekHideWorkItem?.cancel()
            isImmersive = true
            peekRevealing = false
            isToolbarVisible = false
        } else {
            peekHideWorkItem?.cancel()
            isImmersive = false
            peekRevealing = false
            isToolbarVisible = true
        }
        notifyObservers()
    }

    func revealColumns() {
        guard isImmersive else { return }
        peekHideWorkItem?.cancel()
        peekRevealing = true
        notifyObservers()
    }

    func handleColumnHover(_ hovering: Bool) {
        guard isImmersive else { return }
        peekHideWorkItem?.cancel()
        if hovering {
            peekRevealing = true
            notifyObservers()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isImmersive else { return }
            self.peekRevealing = false
            self.notifyObservers()
        }
        peekHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func handleToolbarPointer(isNearTop: Bool) {
        guard isImmersive else { return }
        if isNearTop {
            isToolbarVisible = true
            notifyObservers()
            return
        }

        guard isToolbarVisible else { return }
        isToolbarVisible = false
        notifyObservers()
    }

    func addObserver(_ observer: @escaping (ImmersiveController) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(self)
        return id
    }

    func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer(self)
        }
    }
}

@MainActor
@Observable
final class SidebarDisclosureState {
    private var collapsedFolderIDs = Set<String>()

    func isExpanded(_ folderID: String) -> Bool {
        !collapsedFolderIDs.contains(folderID)
    }

    func setExpanded(_ isExpanded: Bool, for folderID: String) {
        if isExpanded {
            collapsedFolderIDs.remove(folderID)
        } else {
            collapsedFolderIDs.insert(folderID)
        }
    }
}

@MainActor
final class WorkspaceSplitViewController: NSSplitViewController {
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
    private var splitResizeObserver: NSObjectProtocol?
    private var didBootstrap = false
    private var sidebarCollapsedTarget = false

    var isSidebarCollapsed: Bool {
        sidebarItem.isCollapsed
    }

    init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
        sidebarController = WorkspaceSidebarViewController(appContext: appContext)
        contentController = WorkspaceColumnHostController(respectsSafeAreaTop: true)
        detailController = WorkspaceColumnHostController(respectsSafeAreaTop: true)
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        contentItem = NSSplitViewItem(viewController: contentController)
        detailItem = NSSplitViewItem(viewController: detailController)
        super.init(nibName: nil, bundle: nil)
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
        splitView.delegate = self
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(detailItem)
        installObservers()
        bootstrapIfNeeded()
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
        if let splitResizeObserver {
            NotificationCenter.default.removeObserver(splitResizeObserver)
        }
    }

    private func configureSplitItems() {
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 240
        sidebarItem.preferredThicknessFraction = 0.16
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.allowsFullHeightLayout = true

        contentItem.minimumThickness = 280
        contentItem.maximumThickness = expandedContentMaximumThickness
        contentItem.preferredThicknessFraction = 0.28
        contentItem.holdingPriority = NSLayoutConstraint.Priority(250)
        contentItem.canCollapse = false
        contentItem.canCollapseFromWindowResize = false

        detailItem.minimumThickness = 560
        detailItem.holdingPriority = NSLayoutConstraint.Priority(240)
        detailItem.canCollapse = true
        detailItem.canCollapseFromWindowResize = true
    }

    func toggleSidebar() {
        setSidebarCollapsed(!sidebarCollapsedTarget, animated: true)
    }

    private func setSidebarCollapsed(_ isCollapsed: Bool, animated: Bool) {
        sidebarCollapsedTarget = isCollapsed
        if animated {
            sidebarItem.animator().isCollapsed = isCollapsed
        } else {
            sidebarItem.isCollapsed = isCollapsed
        }
        splitView.adjustSubviews()
    }

    @objc func toggleWorkspaceSidebar(_ sender: Any?) {
        toggleSidebar()
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
        splitResizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: splitView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stabilizeSplitLayoutIfNeeded()
            }
        }
    }

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        let storedDetailValue = UserDefaults.standard.object(
            forKey: WorkspaceDetailPaneController.defaultsKey
        ) as? Bool
        appContext.detailPaneController.setPresented(storedDetailValue ?? true)
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
        UserDefaults.standard.set(isPresented, forKey: WorkspaceDetailPaneController.defaultsKey)
        guard !immersive.isImmersive else { return }
        updateContentSizing(forDetailPane: isPresented)
        detailItem.isCollapsed = !isPresented
        contentItem.isCollapsed = false
        splitView.adjustSubviews()
    }

    private var expandedContentMaximumThickness: CGFloat {
        max(720, splitView.bounds.width - sidebarItem.minimumThickness)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !immersive.isImmersive else { return }
        updateContentSizing(forDetailPane: appContext.detailPaneController.isPresented)
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

    private func updateContentSizing(forDetailPane isPresented: Bool) {
        contentItem.maximumThickness = expandedContentMaximumThickness
        contentItem.preferredThicknessFraction = isPresented ? 0.28 : 0.34
    }

    private func stabilizeSplitLayoutIfNeeded() {
        guard !immersive.isImmersive else { return }

        let detailShouldBePresented = appContext.detailPaneController.isPresented
        updateContentSizing(forDetailPane: detailShouldBePresented)

        var needsAdjustment = false
        if contentItem.isCollapsed {
            contentItem.isCollapsed = false
            needsAdjustment = true
        }

        if detailShouldBePresented != !detailItem.isCollapsed {
            appContext.detailPaneController.setPresented(!detailItem.isCollapsed)
        }

        if needsAdjustment {
            splitView.adjustSubviews()
        }
    }

    override func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        if subview === sidebarController.view {
            return sidebarCollapsedTarget
        }
        if subview === detailController.view {
            return true
        }
        return false
    }

    override func splitView(
        _ splitView: NSSplitView,
        shouldCollapseSubview subview: NSView,
        forDoubleClickOnDividerAt dividerIndex: Int
    ) -> Bool {
        false
    }

    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard dividerIndex == 1 else { return proposedPosition }

        let detailCollapseTrigger = splitView.bounds.width - 96
        guard proposedPosition >= detailCollapseTrigger else { return proposedPosition }

        Task { @MainActor [weak self] in
            self?.appContext.detailPaneController.setPresented(false)
        }
        return splitView.bounds.width
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

@MainActor
final class WorkspaceSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private enum Node: Hashable {
        case group(String)
        case gallery(GallerySection)
        case importLocal
        case localFolder(LocalFolderNode)

        var title: String {
            switch self {
            case .group(let title):
                title
            case .gallery(let section):
                section.title
            case .importLocal:
                "导入本地目录"
            case .localFolder(let folder):
                folder.title
            }
        }
    }

    private let appContext: WorkspaceAppContext
    private let rootView = NSView()
    private let materialView = NSVisualEffectView()
    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private var nodes: [Node] = []
    private var childrenByNode: [Node: [Node]] = [:]
    private var isObservingLocalLibrary = false

    fileprivate init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        materialView.material = .sidebar
        materialView.blendingMode = .behindWindow
        materialView.state = .active

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainColumn"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .default
        outlineView.style = .sourceList
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(selectionDidChange(_:))
        outlineView.doubleAction = #selector(doubleClick(_:))
        scrollView.documentView = outlineView

        rootView.addSubview(materialView)
        rootView.addSubview(scrollView)
        materialView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            materialView.topAnchor.constraint(equalTo: rootView.topAnchor),
            materialView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor, constant: 38),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
        observeLocalLibrary()
    }

    func reload() {
        rebuildNodes()
        outlineView.reloadData()
        for node in nodes {
            outlineView.expandItem(node)
        }
        selectCurrentRoute()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? Node {
            return childrenByNode[node]?.count ?? 0
        }
        return nodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? Node {
            return childrenByNode[node]?[index] ?? Node.group("")
        }
        return nodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        return !(childrenByNode[node]?.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        if case .group = node { return true }
        return false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? Node else { return nil }
        let isGroup: Bool
        if case .group = node {
            isGroup = true
        } else {
            isGroup = false
        }
        let identifier = NSUserInterfaceItemIdentifier(isGroup ? "SidebarGroupCell" : "SidebarCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = identifier
        cell.textField = cell.textField ?? NSTextField(labelWithString: "")
        if !isGroup {
            cell.imageView = cell.imageView ?? NSImageView()
        }
        if cell.textField?.superview == nil, let textField = cell.textField {
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            if let imageView = cell.imageView {
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                cell.addSubview(imageView)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 18),
                    imageView.heightAnchor.constraint(equalToConstant: 18),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
        }
        if let imageView = cell.imageView {
            imageView.image = sidebarImage(for: node)
        }
        cell.textField?.stringValue = title(for: node)
        cell.textField?.font = font(for: node)
        return cell
    }

    private func sidebarImage(for node: Node) -> NSImage? {
        let systemName: String
        switch node {
        case .group:
            return nil
        case .gallery(let section):
            systemName = section.sidebarSystemImage
        case .importLocal:
            systemName = "folder.badge.plus"
        case .localFolder:
            systemName = "folder"
        }
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: node.title)
        image?.isTemplate = true
        return image
    }

    @objc private func selectionDidChange(_ sender: Any?) {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0,
              let node = outlineView.item(atRow: selectedRow) as? Node else { return }
        switch node {
        case .gallery(let section):
            appContext.routeController.select(
                WorkspaceRoute(moduleID: .fourKHDGallery, itemID: section.rawValue)
            )
        case .localFolder(let folder):
            appContext.routeController.select(
                WorkspaceRoute(moduleID: .localLibrary, itemID: folder.id)
            )
        case .importLocal:
            appContext.importRootFolder()
        case .group:
            break
        }
    }

    @objc private func doubleClick(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let node = outlineView.item(atRow: clickedRow) as? Node,
              case .importLocal = node else { return }
        appContext.importRootFolder()
    }

    private func rebuildNodes() {
        childrenByNode = [:]
        let online = Node.group("线上")
        let local = Node.group("本地")
        nodes = [online, local]
        childrenByNode[online] = GallerySection.allCases.map(Node.gallery)
        if appContext.localLibraryStore.roots.isEmpty {
            childrenByNode[local] = [.importLocal]
        } else {
            childrenByNode[local] = appContext.localLibraryStore.roots.map { makeFolderNode($0.tree) }
        }
    }

    private func observeLocalLibrary() {
        guard !isObservingLocalLibrary else { return }
        isObservingLocalLibrary = true
        withObservationTracking {
            _ = appContext.localLibraryStore.roots
            _ = appContext.localLibraryStore.selectedFolderID
            _ = appContext.localLibraryStore.isScanning
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingLocalLibrary = false
                self.reload()
                self.observeLocalLibrary()
            }
        }
    }

    private func makeFolderNode(_ folder: LocalFolderNode) -> Node {
        let node = Node.localFolder(folder)
        childrenByNode[node] = folder.folders.map(makeFolderNode)
        return node
    }

    private func selectCurrentRoute() {
        let route = appContext.routeController.route
        for row in 0 ..< outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? Node else { continue }
            if routeMatches(route, node: node) {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                return
            }
        }
    }

    private func routeMatches(_ route: WorkspaceRoute, node: Node) -> Bool {
        switch (route.moduleID, node) {
        case (.fourKHDGallery, .gallery(let section)):
            route.itemID == section.rawValue
        case (.localLibrary, .localFolder(let folder)):
            route.itemID == folder.id
        default:
            false
        }
    }

    private func title(for node: Node) -> String {
        switch node {
        case .localFolder(let folder):
            "\(folder.title)  \(folder.imageCount)"
        default:
            node.title
        }
    }

    private func font(for node: Node) -> NSFont {
        switch node {
        case .group:
            NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        default:
            NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
    }
}
