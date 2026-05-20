import AppKit

@MainActor
final class WorkspaceSidebarDataSource: NSObject, NSOutlineViewDataSource {
    static let localFolderDragType = NSPasteboard.PasteboardType("com.songziqiang.4khd.local-folder")

    private(set) var nodes: [WorkspaceSidebarNode] = []
    private var childrenByNode: [WorkspaceSidebarNode: [WorkspaceSidebarNode]] = [:]
    private var localRootFolderIDs = Set<LocalFolderNode.ID>()
    var localFolderDropHandler: ((URL) -> Void)?
    var localRootFolderOrderCommitHandler: (([LocalFolderNode.ID]) -> Void)?

    func reload(localRoots: [LocalLibraryRoot]) {
        childrenByNode = [:]
        localRootFolderIDs = Set(localRoots.map(\.tree.id))
        let online = WorkspaceSidebarNode.group("线上")
        let local = WorkspaceSidebarNode.group("本地")
        nodes = [online, local]
        childrenByNode[online] = GallerySection.allCases.map(WorkspaceSidebarNode.gallery)
        if localRoots.isEmpty {
            childrenByNode[local] = [.importLocal]
        } else {
            childrenByNode[local] = localRoots.map { makeFolderNode($0.tree) }
        }
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

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? WorkspaceSidebarNode else {
            return nodes.count
        }
        return children(of: node).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? WorkspaceSidebarNode else {
            return nodes[index]
        }
        return children(of: node)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? WorkspaceSidebarNode else { return false }
        return !children(of: node).isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = item as? WorkspaceSidebarNode,
              case .localFolder(let folder) = node,
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
            return localRootFolderIDs.contains(folderID) ? .move : []
        }
        return localFolderURL(from: info.draggingPasteboard) == nil ? [] : .copy
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        if localRootFolderID(from: info.draggingPasteboard) != nil {
            localRootFolderOrderCommitHandler?(currentLocalRootFolderIDs())
            return true
        }
        guard let url = localFolderURL(from: info.draggingPasteboard) else { return false }
        localFolderDropHandler?(url)
        return true
    }

    func currentLocalRootFolderIDs() -> [LocalFolderNode.ID] {
        children(of: localRootGroup()).compactMap { node in
            guard case .localFolder(let folder) = node,
                  localRootFolderIDs.contains(folder.id) else { return nil }
            return folder.id
        }
    }

    func liveReorderLocalRootFolder(
        id folderID: LocalFolderNode.ID,
        to destination: Int,
        in outlineView: NSOutlineView
    ) -> [LocalFolderNode.ID] {
        let localGroup = localRootGroup()
        guard var localRoots = childrenByNode[localGroup],
              let sourceIndex = localRoots.firstIndex(where: { node in
                  guard case .localFolder(let folder) = node else { return false }
                  return folder.id == folderID && localRootFolderIDs.contains(folder.id)
              }) else {
            return currentLocalRootFolderIDs()
        }
        let insertionIndex = max(0, min(destination, localRoots.count - 1))
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
