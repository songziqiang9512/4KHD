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

        if shouldGroupFavorites,
           let group = rowGroup(containing: item) {
            addFavoriteGroupMenuItems(to: menu, item: item, currentGroup: group)
        }

        return menu
    }

    @objc func toggleFavoriteFromMenu(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? GalleryItem else { return }
        library.toggleFavorite(for: item)
        reloadContent()
    }

    @objc func moveFavoriteFromMenu(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? FavoriteMoveCommand else { return }
        setFavoriteAuthorOverride(command.targetAuthor, for: command.item)
        expandedFavoriteAuthorIDs.insert(command.targetAuthor.lowercased())
        reloadContent()
    }

    @objc func restoreFavoriteGroupingFromMenu(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? GalleryItem else { return }
        removeFavoriteAuthorOverride(for: item)
        reloadContent()
    }

    private func addFavoriteGroupMenuItems(
        to menu: NSMenu,
        item: GalleryItem,
        currentGroup: FavoriteAuthorGroup
    ) {
        let targetGroups = favoriteAuthorGroups.filter { $0.id != currentGroup.id }
        if !targetGroups.isEmpty {
            let moveItem = NSMenuItem(title: "移动到目录", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for target in targetGroups {
                let itemMenu = menuItem(
                    target.author,
                    action: #selector(moveFavoriteFromMenu(_:)),
                    representedObject: FavoriteMoveCommand(item: item, targetAuthor: target.author)
                )
                submenu.addItem(itemMenu)
            }
            menu.setSubmenu(submenu, for: moveItem)
            menu.addItem(moveItem)
        }

        if favoriteAuthorOverrides[item.detailURL.absoluteString] != nil {
            menu.addItem(menuItem(
                "恢复自动分类",
                action: #selector(restoreFavoriteGroupingFromMenu(_:)),
                representedObject: item
            ))
        }
    }

    private func menuItem(_ title: String, action: Selector, representedObject: Any) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        return item
    }

    private func rowGroup(containing item: GalleryItem) -> FavoriteAuthorGroup? {
        favoriteAuthorGroups.first { group in
            group.items.contains { $0.id == item.id }
        }
    }
}

final class FavoriteMoveCommand: NSObject {
    let item: GalleryItem
    let targetAuthor: String

    init(item: GalleryItem, targetAuthor: String) {
        self.item = item
        self.targetAuthor = targetAuthor
    }
}
