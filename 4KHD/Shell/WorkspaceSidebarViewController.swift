import AppKit
import Observation

@MainActor
protocol WorkspaceSidebarViewControllerDelegate: AnyObject {
    func sidebarViewController(_ controller: WorkspaceSidebarViewController, didSelect route: WorkspaceRoute)
    func sidebarViewControllerDidRequestLocalImport(_ controller: WorkspaceSidebarViewController)
    func sidebarViewController(
        _ controller: WorkspaceSidebarViewController,
        didRequestImportLocalFolderAt url: URL
    )
    func sidebarViewController(
        _ controller: WorkspaceSidebarViewController,
        didRequestRemoveLocalFolder folder: LocalFolderNode
    )
    func sidebarViewController(
        _ controller: WorkspaceSidebarViewController,
        didChangeExpandedNodeIDs expandedNodeIDs: [String]
    )
    func sidebarViewControllerKeyboardContext(_ controller: WorkspaceSidebarViewController) -> WorkspaceKeyboardContext
}

@MainActor
final class WorkspaceSidebarViewController: NSViewController, NSOutlineViewDelegate, WorkspaceFocusable {
    private let appContext: WorkspaceAppContext
    private let dataSource = WorkspaceSidebarDataSource()
    private let rootView = NSView()
    private let outlineView = WorkspaceSidebarOutlineView()
    private let scrollView = NSScrollView()
    private var isObservingLocalLibrary = false
    private var routeObserverID: UUID?
    private var expandedNodeIDs = Set(WorkspaceWindowState.defaultExpandedSidebarNodeIDs)
    private var isApplyingExpandedNodeIDs = false
    private var liveLocalRootFolderID: LocalFolderNode.ID?
    private var liveLocalRootFolderIDs: [LocalFolderNode.ID]?
    private var lastLiveLocalRootDropDestination: Int?
    private let reloadQueue = WorkspaceCoalescingQueue(
        name: "Workspace Sidebar Reload",
        interval: 0.05,
        maxInterval: 0.25
    )
    weak var delegate: WorkspaceSidebarViewControllerDelegate?

    init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.contentView.drawsBackground = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainColumn"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .default
        outlineView.style = .sourceList
        outlineView.dataSource = dataSource
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(selectionDidChange(_:))
        outlineView.doubleAction = #selector(doubleClick(_:))
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.draggingDestinationFeedbackStyle = .none
        outlineView.keyboardContextProvider = { [weak self] in
            guard let self else { return WorkspaceKeyboardContext() }
            return self.delegate?.sidebarViewControllerKeyboardContext(self) ?? WorkspaceKeyboardContext()
        }
        outlineView.contextMenuProvider = { [weak self] row in
            self?.makeContextMenu(forRow: row)
        }
        outlineView.draggingSessionEndedHandler = { [weak self] operation in
            self?.finishLocalRootFolderDrag(operation: operation)
        }
        outlineView.registerForDraggedTypes([.fileURL, WorkspaceSidebarDataSource.localFolderDragType])
        dataSource.localFolderDropHandler = { [weak self] url in
            guard let self else { return }
            delegate?.sidebarViewController(self, didRequestImportLocalFolderAt: url)
        }
        dataSource.localRootFolderOrderCommitHandler = { [weak self] orderedIDs in
            guard let self else { return }
            appContext.localLibraryStore.reorderRootFolders(ids: orderedIDs)
        }
        scrollView.documentView = outlineView

        rootView.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
        observeLocalLibrary()
        routeObserverID = appContext.routeController.addObserver { [weak self] _ in
            self?.selectCurrentRoute()
        }
    }

    deinit {
        if let routeObserverID {
            Task { @MainActor [appContext] in
                appContext.routeController.removeObserver(id: routeObserverID)
            }
        }
    }

    func reload() {
        let oldIdentifiers = dataSource.allStateIdentifiers()
        dataSource.reload(localRoots: appContext.localLibraryStore.roots)
        let newIdentifiers = dataSource.allStateIdentifiers()
        guard oldIdentifiers != newIdentifiers else { return }
        outlineView.reloadData()
        applyExpandedNodeIDs()
        selectCurrentRoute()
    }

    func focus() {
        outlineView.window?.makeFirstResponderUnlessDescendantIsFirstResponder(outlineView)
    }

    func restoreExpandedNodeIDs(_ nodeIDs: [String]) {
        expandedNodeIDs = Set(nodeIDs)
        guard isViewLoaded else { return }
        applyExpandedNodeIDs()
        selectCurrentRoute()
    }

    func nodeForSidebarRow(_ row: Int) -> WorkspaceSidebarNode? {
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? WorkspaceSidebarNode
    }

    func requestLocalImportFromContextMenu() {
        delegate?.sidebarViewControllerDidRequestLocalImport(self)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let node = item as? WorkspaceSidebarNode else { return false }
        if case .group = node { return true }
        return false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet
    ) -> IndexSet {
        for index in proposedSelectionIndexes {
            guard let node = outlineView.item(atRow: index) as? WorkspaceSidebarNode else { continue }
            if isGroupNode(node) {
                return outlineView.selectedRowIndexes
            }
        }
        return proposedSelectionIndexes
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? WorkspaceSidebarNode else { return true }
        return !isGroupNode(node)
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        guard let node = item as? WorkspaceSidebarNode,
              !isGroupNode(node) else {
            return nil
        }
        let identifier = NSUserInterfaceItemIdentifier("WorkspaceSidebarRowView")
        let rowView = outlineView.makeView(withIdentifier: identifier, owner: self) as? WorkspaceSidebarRowView
            ?? WorkspaceSidebarRowView()
        rowView.identifier = identifier
        return rowView
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItems draggedItems: [Any]
    ) {
        guard let node = draggedItems.first as? WorkspaceSidebarNode,
              case .localFolder(let folder) = node,
              appContext.localLibraryStore.roots.contains(where: { $0.tree.id == folder.id }) else { return }
        liveLocalRootFolderID = folder.id
        liveLocalRootFolderIDs = dataSource.currentLocalRootFolderIDs()
        lastLiveLocalRootDropDestination = nil
        session.animatesToStartingPositionsOnCancelOrFail = false
        let row = outlineView.row(forItem: node)
        if row >= 0,
           let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? WorkspaceSidebarRowView {
            rowView.suppressSelectionDuringDrag = true
            rowView.needsDisplay = true
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateLocalRootDraggingPresentation()
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingImageForRowsWith dragRows: IndexSet,
        tableColumns: [NSTableColumn],
        event: NSEvent,
        offset dragImageOffset: NSPointPointer
    ) -> NSImage {
        guard let row = dragRows.first,
              let rowView = outlineView.rowView(atRow: row, makeIfNecessary: true) as? WorkspaceSidebarRowView else {
            return NSImage(size: .zero)
        }

        let previousAlpha = rowView.alphaValue
        let previousSuppression = rowView.suppressSelectionDuringDrag
        rowView.alphaValue = 1
        rowView.suppressSelectionDuringDrag = true
        rowView.needsDisplay = true

        let size = rowView.bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        if let rep = rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds) {
            rowView.cacheDisplay(in: rowView.bounds, to: rep)
            image.addRepresentation(rep)
        }
        image.unlockFocus()

        rowView.alphaValue = previousAlpha
        rowView.suppressSelectionDuringDrag = previousSuppression
        rowView.needsDisplay = true
        dragImageOffset.pointee = NSPoint(x: 0, y: 0)
        return image
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        saveExpandedNodeIDsFromOutlineView()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        saveExpandedNodeIDsFromOutlineView()
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? WorkspaceSidebarNode else { return nil }
        let isGroup: Bool
        if case .group = node {
            isGroup = true
        } else {
            isGroup = false
        }
        if isGroup {
            let identifier = NSUserInterfaceItemIdentifier("SidebarGroupCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? NSTableCellView()
            cell.identifier = identifier
            cell.textField = cell.textField ?? NSTextField(labelWithString: "")
            if cell.textField?.superview == nil, let textField = cell.textField {
                textField.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(textField)
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            cell.textField?.stringValue = node.title
            cell.textField?.font = font(for: node)
            return cell
        }

        let identifier = NSUserInterfaceItemIdentifier("SidebarLeafCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? WorkspaceSidebarCellView
            ?? WorkspaceSidebarCellView()
        cell.identifier = identifier
        cell.configure(
            title: node.title,
            image: sidebarImage(for: node),
            count: node.count
        )
        return cell
    }

    private func sidebarImage(for node: WorkspaceSidebarNode) -> NSImage? {
        let systemName: String
        switch node {
        case .group:
            return nil
        case .gallery(let section):
            systemName = section.sidebarSystemImage
        case .localAllImages:
            systemName = "photo.on.rectangle.angled"
        case .localFolder:
            systemName = "folder"
        }
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: node.title)
        image?.isTemplate = true
        return image
    }

    private func isGroupNode(_ node: WorkspaceSidebarNode) -> Bool {
        if case .group = node {
            return true
        }
        return false
    }

    @objc private func selectionDidChange(_ sender: Any?) {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0,
              let node = outlineView.item(atRow: selectedRow) as? WorkspaceSidebarNode else { return }
        let selectedRoute: WorkspaceRoute?
        switch node {
        case .gallery(let section):
            selectedRoute = WorkspaceRoute(moduleID: .fourKHDGallery, itemID: section.rawValue)
        case .localFolder(let folder):
            selectedRoute = WorkspaceRoute(moduleID: .localLibrary, itemID: folder.id)
        case .localAllImages:
            selectedRoute = WorkspaceRoute(moduleID: .localLibrary, itemID: LocalLibraryStore.allImagesFolderID)
        case .group:
            selectedRoute = nil
        }
        guard let selectedRoute,
              appContext.routeController.route != selectedRoute else {
            return
        }
        delegate?.sidebarViewController(self, didSelect: selectedRoute)
    }

    @objc private func doubleClick(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let node = outlineView.item(atRow: clickedRow) as? WorkspaceSidebarNode,
              case .localAllImages = node else { return }
        delegate?.sidebarViewController(self, didSelect: WorkspaceRoute(
            moduleID: .localLibrary,
            itemID: LocalLibraryStore.allImagesFolderID
        ))
    }

    private func observeLocalLibrary() {
        guard !isObservingLocalLibrary else { return }
        isObservingLocalLibrary = true
        withObservationTracking {
            _ = appContext.localLibraryStore.roots
            _ = appContext.localLibraryStore.isScanning
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingLocalLibrary = false
                self.scheduleReload()
                self.observeLocalLibrary()
            }
        }
    }

    private func finishLocalRootFolderDrag(operation: NSDragOperation) {
        if operation == .move {
            appContext.localLibraryStore.reorderRootFolders(ids: dataSource.currentLocalRootFolderIDs())
        }
        liveLocalRootFolderID = nil
        liveLocalRootFolderIDs = nil
        lastLiveLocalRootDropDestination = nil
        updateLocalRootDraggingPresentation()
    }

    private func updateLocalRootDraggingPresentation() {
        guard outlineView.numberOfRows > 0 else { return }
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? WorkspaceSidebarNode,
                  case .localFolder(let folder) = node,
                  let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? WorkspaceSidebarRowView else {
                continue
            }
            let dragging = liveLocalRootFolderID == folder.id
            rowView.alphaValue = 1
            rowView.suppressSelectionDuringDrag = dragging
            rowView.needsDisplay = true
            outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)?.alphaValue = dragging ? 0 : 1
        }
    }

    private func scheduleReload() {
        reloadQueue.add(id: "reload") { [weak self] in
            self?.reload()
        }
    }

    private func selectCurrentRoute() {
        let route = appContext.routeController.route
        guard let path = dataSource.pathToNode(where: { routeMatches(route, node: $0) }),
              let selectedNode = path.last else {
            if outlineView.selectedRow >= 0 {
                outlineView.deselectAll(nil)
            }
            return
        }
        let row = outlineView.row(forItem: selectedNode)
        guard row >= 0 else {
            if outlineView.selectedRow >= 0 {
                outlineView.deselectAll(nil)
            }
            return
        }
        guard outlineView.selectedRow != row else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    private func applyExpandedNodeIDs() {
        isApplyingExpandedNodeIDs = true
        defer { isApplyingExpandedNodeIDs = false }
        for node in dataSource.expandableNodes() {
            if expandedNodeIDs.contains(node.stateIdentifier) {
                outlineView.expandItem(node)
            } else {
                outlineView.collapseItem(node)
            }
        }
    }

    private func saveExpandedNodeIDsFromOutlineView() {
        guard !isApplyingExpandedNodeIDs else { return }
        let expandedIDs = dataSource.expandableNodes()
            .filter { outlineView.isItemExpanded($0) }
            .map(\.stateIdentifier)
        expandedNodeIDs = Set(expandedIDs)
        delegate?.sidebarViewController(self, didChangeExpandedNodeIDs: expandedIDs)
    }

    private func routeMatches(_ route: WorkspaceRoute, node: WorkspaceSidebarNode) -> Bool {
        switch (route.moduleID, node) {
        case (.fourKHDGallery, .gallery(let section)):
            route.itemID == section.rawValue
        case (.localLibrary, .localFolder(let folder)):
            route.itemID == folder.id
        case (.localLibrary, .localAllImages):
            route.itemID == LocalLibraryStore.allImagesFolderID
        default:
            false
        }
    }

    private func title(for node: WorkspaceSidebarNode) -> String {
        node.title
    }

    private func font(for node: WorkspaceSidebarNode) -> NSFont {
        switch node {
        case .group:
            NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        default:
            NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
    }
}
