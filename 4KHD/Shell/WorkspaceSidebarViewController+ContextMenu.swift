import AppKit

extension WorkspaceSidebarViewController {
    func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard let node = nodeForSidebarRow(row) else {
            return nil
        }

        switch node {
        case let .localFolder(folder):
            return localFolderMenu(folder)
        case .group, .gallery, .missKon, .wallhaven, .knit, .mrds, .quanji, .porny, .localAllImages, .favoritesModule:
            return nil
        }
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

    @objc func removeLocalFolderFromSidebarMenu(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? LocalFolderNode else { return }
        let alert = makeAppAlert(
            title: "从本地库移除目录？",
            message: "这只会从侧边栏和本地库索引中移除该目录，不会删除磁盘上的文件。",
            style: .warning,
            buttons: ["移除", "取消"]
        )
        presentAppAlert(alert, in: view.window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            delegate?.sidebarViewController(self, didRequestRemoveLocalFolder: folder)
        }
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
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: "从本地库移除...",
            symbolName: "trash",
            action: #selector(removeLocalFolderFromSidebarMenu(_:)),
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
