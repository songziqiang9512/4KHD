import AppKit
import Observation

@MainActor
protocol WorkspaceSidebarViewControllerDelegate: AnyObject {
    func sidebarViewController(_ controller: WorkspaceSidebarViewController, didSelect route: WorkspaceRoute)
    func sidebarViewControllerDidRequestLocalImport(_ controller: WorkspaceSidebarViewController)
    func sidebarViewController(
        _ controller: WorkspaceSidebarViewController,
        didChangeExpandedNodeIDs expandedNodeIDs: [String]
    )
    func sidebarViewControllerKeyboardContext(_ controller: WorkspaceSidebarViewController) -> WorkspaceKeyboardContext
}

@MainActor
final class WorkspaceSidebarViewController: NSViewController, NSOutlineViewDelegate {
    private let appContext: WorkspaceAppContext
    private let dataSource = WorkspaceSidebarDataSource()
    private let rootView = NSView()
    private let materialView = NSVisualEffectView()
    private let outlineView = WorkspaceSidebarOutlineView()
    private let scrollView = NSScrollView()
    private var isObservingLocalLibrary = false
    private var expandedNodeIDs: Set<String> = ["group:线上", "group:本地"]
    private var isApplyingExpandedNodeIDs = false
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
        outlineView.dataSource = dataSource
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(selectionDidChange(_:))
        outlineView.doubleAction = #selector(doubleClick(_:))
        outlineView.keyboardContextProvider = { [weak self] in
            guard let self else { return WorkspaceKeyboardContext() }
            return self.delegate?.sidebarViewControllerKeyboardContext(self) ?? WorkspaceKeyboardContext()
        }
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
        dataSource.reload(localRoots: appContext.localLibraryStore.roots)
        outlineView.reloadData()
        applyExpandedNodeIDs()
        selectCurrentRoute()
    }

    func restoreExpandedNodeIDs(_ nodeIDs: [String]) {
        expandedNodeIDs = Set(nodeIDs)
        guard isViewLoaded else { return }
        applyExpandedNodeIDs()
        selectCurrentRoute()
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let node = item as? WorkspaceSidebarNode else { return false }
        if case .group = node { return true }
        return false
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

    private func sidebarImage(for node: WorkspaceSidebarNode) -> NSImage? {
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
              let node = outlineView.item(atRow: selectedRow) as? WorkspaceSidebarNode else { return }
        switch node {
        case .gallery(let section):
            delegate?.sidebarViewController(
                self,
                didSelect:
                WorkspaceRoute(moduleID: .fourKHDGallery, itemID: section.rawValue)
            )
        case .localFolder(let folder):
            delegate?.sidebarViewController(
                self,
                didSelect:
                WorkspaceRoute(moduleID: .localLibrary, itemID: folder.id)
            )
        case .importLocal:
            delegate?.sidebarViewControllerDidRequestLocalImport(self)
        case .group:
            break
        }
    }

    @objc private func doubleClick(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let node = outlineView.item(atRow: clickedRow) as? WorkspaceSidebarNode,
              case .importLocal = node else { return }
        delegate?.sidebarViewControllerDidRequestLocalImport(self)
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

    private func selectCurrentRoute() {
        let route = appContext.routeController.route
        for row in 0 ..< outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? WorkspaceSidebarNode else { continue }
            if routeMatches(route, node: node) {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                return
            }
        }
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
        default:
            false
        }
    }

    private func title(for node: WorkspaceSidebarNode) -> String {
        switch node {
        case .localFolder(let folder):
            "\(folder.title)  \(folder.imageCount)"
        default:
            node.title
        }
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
