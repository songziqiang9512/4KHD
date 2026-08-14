import AppKit

extension GalleryContentViewController {
    func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard rows.indices.contains(row),
              case .item(let id) = rows[row],
              let item = rowItems[id] else {
            return nil
        }
        return makeContextMenu(for: item)
    }

    func makeContextMenu(for item: GalleryItem) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(menuItem(
            library.isFavorite(item) ? "取消收藏" : "收藏",
            action: #selector(toggleFavoriteFromMenu(_:)),
            representedObject: item
        ))

        menu.addItem(.separator())
        menu.addItem(menuItem(
            "打开原网页",
            action: #selector(openOriginalPageFromMenu(_:)),
            representedObject: item.detailURL,
            symbolName: "arrow.up.right.square"
        ))
        menu.addItem(menuItem(
            "复制链接",
            action: #selector(copyDetailURLFromMenu(_:)),
            representedObject: item.detailURL,
            symbolName: "doc.on.doc"
        ))
        menu.addItem(menuItem(
            "共享...",
            action: #selector(shareDetailURLFromMenu(_:)),
            representedObject: item.detailURL,
            symbolName: "square.and.arrow.up"
        ))

        return menu
    }

    @objc func toggleFavoriteFromMenu(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? GalleryItem else { return }
        Task {
            do {
                try await library.toggleFavorite(for: item)
                reloadContent()
            } catch {
                let alert = makeAppAlert(
                    title: "收藏保存失败",
                    message: error.localizedDescription,
                    style: .warning
                )
                presentAppAlert(alert, in: view.window)
            }
        }
    }

    @objc func openOriginalPageFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func copyDetailURLFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        writeURLToPasteboard(url)
    }

    @objc func shareDetailURLFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        SharingPresenter.show(items: [url], of: view, preferredEdge: .maxX)
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        representedObject: Any,
        symbolName: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        if let symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        }
        return item
    }

    private func writeURLToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        let urlString = url.absoluteString
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .URL)
        pasteboard.setString(urlString, forType: .string)
    }
}
