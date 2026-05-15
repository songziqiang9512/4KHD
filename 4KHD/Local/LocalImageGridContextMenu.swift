import AppKit

extension LocalImageGridContainerView {
    func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        if let indexPath, indexPath.item < entries.count {
            selectItem(at: indexPath.item, scroll: false)
        }
        guard selectedEntry != nil else { return nil }

        let menu = NSMenu(title: "LocalImageGridMenu")
        menu.autoenablesItems = false
        menu.addItem(makeMenuItem(title: "设置为桌面壁纸", symbolName: "photo.fill", action: #selector(setDesktopWallpaper)))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "快速预览", symbolName: "eye", action: #selector(contextQuickLook)))
        menu.addItem(makeMenuItem(title: "详细信息", symbolName: "info.circle", action: #selector(showInfo)))
        menu.addItem(makeMenuItem(title: "在 Finder 中显示", symbolName: "folder", action: #selector(revealInFinder)))
        menu.addItem(makeMenuItem(title: "复制路径", symbolName: "doc.on.doc", action: #selector(copyPath)))
        menu.addItem(makeMenuItem(title: "打开文件", symbolName: "arrow.up.right.square", action: #selector(openFile)))
        return menu
    }

    private func makeMenuItem(title: String, symbolName: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        return item
    }

    @objc private func setDesktopWallpaper() {
        guard let image = selectedEntry?.image else { return }
        LocalDesktopWallpaperSetter.setDesktopWallpaper(image.url)
    }

    @objc private func contextQuickLook() {
        _ = quickLookSelected()
    }

    @objc private func showInfo() {
        guard let image = selectedEntry?.image else { return }
        onShowInfo?(image)
    }

    @objc private func revealInFinder() {
        guard let image = selectedEntry?.image else { return }
        NSWorkspace.shared.activateFileViewerSelecting([image.url])
    }

    @objc private func copyPath() {
        guard let image = selectedEntry?.image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(image.url.path, forType: .string)
    }

    @objc private func openFile() {
        guard let image = selectedEntry?.image else { return }
        NSWorkspace.shared.open(image.url)
    }
}
