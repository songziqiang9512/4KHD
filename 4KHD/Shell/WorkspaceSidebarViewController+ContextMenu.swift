import AppKit

extension WorkspaceSidebarViewController {
    func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard let node = nodeForSidebarRow(row) else {
            return importMenu()
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

    @objc func openLocalFolderFromSidebarMenu(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? LocalFolderNode else { return }
        NSWorkspace.shared.open(folder.url)
    }

    @objc func copyLocalFolderPathFromSidebarMenu(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? LocalFolderNode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(folder.url.path, forType: .string)
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
        menu.addItem(menuItem(
            title: "打开目录",
            symbolName: "folder",
            action: #selector(openLocalFolderFromSidebarMenu(_:)),
            representedObject: folder
        ))
        menu.addItem(menuItem(
            title: "在 Finder 中显示",
            symbolName: "folder",
            action: #selector(revealLocalFolderFromSidebarMenu(_:)),
            representedObject: folder
        ))
        menu.addItem(menuItem(
            title: "复制路径",
            symbolName: "doc.on.doc",
            action: #selector(copyLocalFolderPathFromSidebarMenu(_:)),
            representedObject: folder
        ))
        return menu
    }

    private func menuItem(
        title: String,
        symbolName: String,
        action: Selector,
        representedObject: Any
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        return item
    }
}
