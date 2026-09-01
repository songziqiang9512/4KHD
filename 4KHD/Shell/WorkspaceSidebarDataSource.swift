import AppKit

@MainActor
final class WorkspaceSidebarDataSource: NSObject, NSOutlineViewDataSource {
    static let localFolderDragType = NSPasteboard.PasteboardType("com.songziqiang.4khd.local-folder")

    private(set) var nodes: [WorkspaceSidebarNode] = []
    private var childrenByNode: [WorkspaceSidebarNode: [WorkspaceSidebarNode]] = [:]
    private var localRootFolderIDs = Set<LocalFolderNode.ID>()
    private var lastLiveLocalRootDestination: Int?
    var localFolderDropHandler: ((URL) -> Void)?
    var localRootFolderOrderCommitHandler: (([LocalFolderNode.ID]) -> Void)?

    /// Returns all node state identifiers in depth-first order for structural comparison.
    func allStateIdentifiers() -> [String] {
        var result: [String] = []
        for node in nodes {
            appendStateIdentifiers(from: node, into: &result)
        }
        return result
    }

    func allDisplaySignatures() -> [String] {
        var result: [String] = []
        for node in nodes {
            appendDisplaySignatures(from: node, into: &result)
        }
        return result
    }

    func reload(localRoots: [LocalLibraryRoot]) {
        childrenByNode = [:]
        lastLiveLocalRootDestination = nil
        localRootFolderIDs = Set(localRoots.map(\.tree.id))
        let online = WorkspaceSidebarNode.group("4KHD")
        let misskon = WorkspaceSidebarNode.group("MissKon")
        let wallhaven = WorkspaceSidebarNode.group("在线壁纸")
        let knit = WorkspaceSidebarNode.group("爱妹子")
        let mrds = WorkspaceSidebarNode.group("每日大赛")
        let quanji = WorkspaceSidebarNode.group("木瓜视频")
        let porny = WorkspaceSidebarNode.group("91PORNY")
        let tangxin = WorkspaceSidebarNode.group("糖心Vlog")
        let local = WorkspaceSidebarNode.group("本地")

        let showAdvanced = SidebarModuleVisibility.showAdvancedModules
        nodes = [local, wallhaven]
        if showAdvanced {
            nodes.append(online)
            nodes.append(misskon)
            nodes.append(knit)
            nodes.append(mrds)
            nodes.append(quanji)
            nodes.append(porny)
            nodes.append(tangxin)
        }

        childrenByNode[online] = GallerySection.allCases.map(WorkspaceSidebarNode.gallery)
        childrenByNode[misskon] = MissKonSection.allCases.map(WorkspaceSidebarNode.missKon)
        childrenByNode[wallhaven] = WallhavenSection.allCases.map(WorkspaceSidebarNode.wallhaven)
        childrenByNode[knit] = KnitSidebarSection.allCases.map(WorkspaceSidebarNode.knit)
        childrenByNode[mrds] = MrdsSection.allCases.map(WorkspaceSidebarNode.mrds)
        childrenByNode[quanji] = QuanjiSection.allCases.map(WorkspaceSidebarNode.quanji)
        childrenByNode[porny] = PornySection.allCases.map(WorkspaceSidebarNode.porny)
        childrenByNode[tangxin] = TangxinSection.allCases.map(WorkspaceSidebarNode.tangxin)
        // 在线收藏作为「本地」分组的子节点,紧跟在「我的图片」下方。
        var localChildren: [WorkspaceSidebarNode] = [
            .localAllImages(count: localRoots.reduce(0) { $0 + $1.imageCount }),
            .favoritesModule,
        ]
        localChildren.append(contentsOf: localRoots.map { makeFolderNode($0.tree) })
        childrenByNode[local] = localChildren
    }

    func children(of node: WorkspaceSidebarNode) -> [WorkspaceSidebarNode] {
        childrenByNode[node] ?? []
    }

    func expandableNodes() -> [WorkspaceSidebarNode] {
        var result: [WorkspaceSidebarNode] = []
        for node in nodes {
            appendExpandableNodes(from: node, to: &result)
        }
        return result
    }

    func pathToNode(where predicate: (WorkspaceSidebarNode) -> Bool) -> [WorkspaceSidebarNode]? {
        for node in nodes {
            if let path = pathToNode(from: node, where: predicate) {
                return path
            }
        }
        return nil
    }

    func node(withStateIdentifier stateIdentifier: String) -> WorkspaceSidebarNode? {
        pathToNode { $0.stateIdentifier == stateIdentifier }?.last
    }

    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? WorkspaceSidebarNode else {
            return nodes.count
        }
        return children(of: node).count
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? WorkspaceSidebarNode else {
            return nodes[index]
        }
        return children(of: node)[index]
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? WorkspaceSidebarNode else { return false }
        return !children(of: node).isEmpty
    }

    func outlineView(_: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = item as? WorkspaceSidebarNode,
              case let .localFolder(folder) = node,
              localRootFolderIDs.contains(folder.id) else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(folder.id, forType: Self.localFolderDragType)
        return pasteboardItem
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        if let folderID = localRootFolderID(from: info.draggingPasteboard) {
            guard let destinationIndex = localDropIndex(
                from: outlineView,
                item: item,
                childIndex: index,
                draggingLocation: info.draggingLocation
            ) else { return [] }
            if lastLiveLocalRootDestination != destinationIndex {
                lastLiveLocalRootDestination = destinationIndex
                _ = liveReorderLocalRootFolder(id: folderID, toDropIndex: destinationIndex, in: outlineView)
            }
            return .move
        }
        return localFolderURL(from: info.draggingPasteboard) == nil ? [] : .copy
    }

    func outlineView(
        _: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item _: Any?,
        childIndex _: Int
    ) -> Bool {
        if localRootFolderID(from: info.draggingPasteboard) != nil {
            lastLiveLocalRootDestination = nil
            localRootFolderOrderCommitHandler?(currentLocalRootFolderIDs())
            return true
        }
        guard let url = localFolderURL(from: info.draggingPasteboard) else { return false }
        localFolderDropHandler?(url)
        return true
    }

    func currentLocalRootFolderIDs() -> [LocalFolderNode.ID] {
        children(of: localRootGroup()).compactMap { node in
            guard case let .localFolder(folder) = node,
                  localRootFolderIDs.contains(folder.id) else { return nil }
            return folder.id
        }
    }

    /// 拖拽取消/失败时把实时重排过的根目录顺序恢复为拖拽前的快照。
    func restoreLocalRootFolderOrder(_ ids: [LocalFolderNode.ID], in outlineView: NSOutlineView) {
        let localGroup = localRootGroup()
        guard let localRoots = childrenByNode[localGroup] else { return }
        var folderByID: [LocalFolderNode.ID: WorkspaceSidebarNode] = [:]
        let nonFolderNodes = localRoots.filter { node in
            if case .localFolder = node { return false }
            return true
        }
        for node in localRoots {
            guard case let .localFolder(folder) = node else { continue }
            folderByID[folder.id] = node
        }
        guard folderByID.count == ids.count else { return }
        let restored = ids.compactMap { folderByID[$0] }
        guard restored.count == ids.count else { return }
        // 保留「我的图片」「在线收藏」等非目录节点,只回滚目录部分。
        childrenByNode[localGroup] = nonFolderNodes + restored
        outlineView.reloadItem(localGroup)
    }

    func liveReorderLocalRootFolder(
        id folderID: LocalFolderNode.ID,
        toDropIndex dropIndex: Int,
        in outlineView: NSOutlineView
    ) -> [LocalFolderNode.ID] {
        let localGroup = localRootGroup()
        guard var localRoots = childrenByNode[localGroup],
              let sourceIndex = localRoots.firstIndex(where: { node in
                  guard case let .localFolder(folder) = node else { return false }
                  return folder.id == folderID && localRootFolderIDs.contains(folder.id)
              })
        else {
            return currentLocalRootFolderIDs()
        }
        var insertionIndex = max(1, min(dropIndex, localRoots.count))
        if sourceIndex < insertionIndex {
            insertionIndex -= 1
        }
        insertionIndex = max(1, min(insertionIndex, localRoots.count - 1))
        guard sourceIndex != insertionIndex else {
            return currentLocalRootFolderIDs()
        }

        let movedNode = localRoots.remove(at: sourceIndex)
        localRoots.insert(movedNode, at: max(0, min(insertionIndex, localRoots.count)))
        childrenByNode[localGroup] = localRoots
        outlineView.beginUpdates()
        outlineView.moveItem(at: sourceIndex, inParent: localGroup, to: insertionIndex, inParent: localGroup)
        outlineView.endUpdates()
        return currentLocalRootFolderIDs()
    }

    private func appendStateIdentifiers(from node: WorkspaceSidebarNode, into result: inout [String]) {
        result.append(node.stateIdentifier)
        for child in children(of: node) {
            appendStateIdentifiers(from: child, into: &result)
        }
    }

    private func appendDisplaySignatures(from node: WorkspaceSidebarNode, into result: inout [String]) {
        result.append("\(node.stateIdentifier)|\(node.title)|\(node.count.map(String.init) ?? "")")
        for child in children(of: node) {
            appendDisplaySignatures(from: child, into: &result)
        }
    }

    private func makeFolderNode(_ folder: LocalFolderNode) -> WorkspaceSidebarNode {
        let node = WorkspaceSidebarNode.localFolder(folder)
        childrenByNode[node] = folder.folders.map(makeFolderNode)
        return node
    }

    private func appendExpandableNodes(
        from node: WorkspaceSidebarNode,
        to result: inout [WorkspaceSidebarNode]
    ) {
        let children = children(of: node)
        guard !children.isEmpty else { return }
        result.append(node)
        for child in children {
            appendExpandableNodes(from: child, to: &result)
        }
    }

    private func pathToNode(
        from node: WorkspaceSidebarNode,
        where predicate: (WorkspaceSidebarNode) -> Bool
    ) -> [WorkspaceSidebarNode]? {
        if predicate(node) {
            return [node]
        }
        for child in children(of: node) {
            if let childPath = pathToNode(from: child, where: predicate) {
                return [node] + childPath
            }
        }
        return nil
    }

    private func localRootGroup() -> WorkspaceSidebarNode {
        .group("本地")
    }

    private func localDropIndex(
        from outlineView: NSOutlineView,
        item: Any?,
        childIndex index: Int,
        draggingLocation: NSPoint
    ) -> Int? {
        let localGroup = localRootGroup()
        if let node = item as? WorkspaceSidebarNode,
           node == localGroup
        {
            return max(1, min(index, children(of: localGroup).count))
        }
        if let node = item as? WorkspaceSidebarNode,
           case .localAllImages = node
        {
            return 1
        }
        guard let node = item as? WorkspaceSidebarNode,
              case let .localFolder(folder) = node,
              localRootFolderIDs.contains(folder.id),
              let row = rowForNode(node, in: outlineView)
        else {
            return nil
        }
        let rowRect = outlineView.rect(ofRow: row)
        let location = outlineView.convert(draggingLocation, from: nil)
        let rootIndex = children(of: localGroup).firstIndex(of: node) ?? 0
        return location.y < rowRect.midY ? rootIndex + 1 : rootIndex
    }

    private func rowForNode(_ node: WorkspaceSidebarNode, in outlineView: NSOutlineView) -> Int? {
        let row = outlineView.row(forItem: node)
        return row >= 0 ? row : nil
    }

    private func localRootFolderID(from pasteboard: NSPasteboard) -> LocalFolderNode.ID? {
        pasteboard.string(forType: Self.localFolderDragType)
    }

    private func localFolderURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        for object in objects {
            let url: URL
            if let fileURL = object as? URL {
                url = fileURL
            } else if let fileURL = object as? NSURL {
                url = fileURL as URL
            } else {
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            return url
        }
        return nil
    }
}
