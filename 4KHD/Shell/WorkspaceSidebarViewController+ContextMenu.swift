import AppKit

extension WorkspaceSidebarViewController {
    func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard let node = nodeForSidebarRow(row) else {
            return nil
        }

        switch node {
        case .importLocal:
            return importMenu()
        case .localFolder(let folder):
            return localFolderMenu(folder)
        case .group, .gallery:
            return nil
        }
    }

    @objc func importLocalFolderFromSidebarMenu(_ sender: Any?) {
        requestLocalImportFromContextMenu()
    }

    @objc func revealLocalFolderFromSidebarMenu(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? LocalFolderNode else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder.url])
    }

    private func importMenu() -> NSMenu {
        let menu = NSMenu(title: "SidebarImportMenu")
        let item = NSMenuItem(
            title: "导入本地目录",
            action: #selector(importLocalFolderFromSidebarMenu(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "导入本地目录")
        menu.addItem(item)
        return menu
    }

    private func localFolderMenu(_ folder: LocalFolderNode) -> NSMenu {
        let menu = NSMenu(title: "SidebarLocalFolderMenu")
        let revealItem = NSMenuItem(
            title: "在 Finder 中显示",
            action: #selector(revealLocalFolderFromSidebarMenu(_:)),
            keyEquivalent: ""
        )
        revealItem.target = self
        revealItem.representedObject = folder
        revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "在 Finder 中显示")
        menu.addItem(revealItem)
        return menu
    }
}
