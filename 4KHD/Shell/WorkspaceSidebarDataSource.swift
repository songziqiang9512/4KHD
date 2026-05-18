import AppKit

@MainActor
final class WorkspaceSidebarDataSource: NSObject, NSOutlineViewDataSource {
    private(set) var nodes: [WorkspaceSidebarNode] = []
    private var childrenByNode: [WorkspaceSidebarNode: [WorkspaceSidebarNode]] = [:]
    var localFolderDropHandler: ((URL) -> Void)?

    func reload(localRoots: [LocalLibraryRoot]) {
        childrenByNode = [:]
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

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        localFolderURL(from: info.draggingPasteboard) == nil ? [] : .copy
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard let url = localFolderURL(from: info.draggingPasteboard) else { return false }
        localFolderDropHandler?(url)
        return true
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
