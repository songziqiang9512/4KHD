import AppKit

@MainActor
final class WorkspaceSidebarDataSource: NSObject, NSOutlineViewDataSource {
    private(set) var nodes: [WorkspaceSidebarNode] = []
    private var childrenByNode: [WorkspaceSidebarNode: [WorkspaceSidebarNode]] = [:]

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
}
