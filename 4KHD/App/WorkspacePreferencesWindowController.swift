import AppKit

@MainActor
final class WorkspacePreferencesWindowController: NSWindowController, NSToolbarDelegate {
    private enum Pane: String, CaseIterable {
        case content = "内容"
        case storage = "存储"

        var identifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier("WorkspacePreferences.\(rawValue)")
        }

        var image: NSImage? {
            switch self {
            case .content:
                NSImage(systemSymbolName: "rectangle.grid.2x2", accessibilityDescription: rawValue)
            case .storage:
                NSImage(systemSymbolName: "internaldrive", accessibilityDescription: rawValue)
            }
        }
    }

    private let contentPaneViewController: WorkspaceContentPreferencesViewController
    private let storageViewController: WorkspaceStoragePreferencesViewController
    private var currentPane: Pane = .content

    init(appContext: WorkspaceAppContext) {
        let contentPaneViewController = WorkspaceContentPreferencesViewController(
            toolbarContext: appContext.toolbarContext
        )
        let storageViewController = WorkspaceStoragePreferencesViewController(
            favoritesStore: appContext.favoritesStore,
            onFavoritesImported: {
                if appContext.galleryStore.section == .favorites {
                    appContext.galleryStore.refreshFavoritesIfNeeded()
                }
                if appContext.missKonStore.section == .favorites {
                    appContext.missKonStore.feed.restoreSectionCache()
                }
                appContext.wallhavenStore.feed.refreshFavoritesIfNeeded()
            }
        )
        self.contentPaneViewController = contentPaneViewController
        self.storageViewController = storageViewController

        let window = NSWindow(contentViewController: contentPaneViewController)
        window.title = "设置"
        window.styleMask = [.titled, .closable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        window.setContentSize(contentPaneViewController.paneContentSize)
        window.center()

        super.init(window: window)
        installToolbar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func refresh() {
        contentPaneViewController.refresh()
        storageViewController.refresh()
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = Pane.allCases.first(where: { $0.identifier == sender.itemIdentifier }) else { return }
        switchToPane(pane)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = Pane.allCases.first(where: { $0.identifier == itemIdentifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: pane.identifier)
        item.label = pane.rawValue
        item.paletteLabel = pane.rawValue
        item.image = pane.image
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map(\.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    private func installToolbar() {
        let toolbar = NSToolbar(identifier: "WorkspacePreferencesToolbar")
        toolbar.delegate = self
        toolbar.autosavesConfiguration = false
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = currentPane.identifier
        window?.showsToolbarButton = false
        window?.toolbar = toolbar
    }

    private func switchToPane(_ pane: Pane) {
        guard pane != currentPane else { return }
        currentPane = pane
        let nextViewController: NSViewController & WorkspacePreferencesPane = {
            switch pane {
            case .content:
                return contentPaneViewController
            case .storage:
                return storageViewController
            }
        }()
        nextViewController.refresh()
        resizeWindow(toFit: nextViewController)
        window?.contentViewController = nextViewController
        window?.toolbar?.selectedItemIdentifier = pane.identifier
        window?.title = pane.rawValue
    }

    private func resizeWindow(toFit viewController: WorkspacePreferencesPane) {
        guard let window else { return }
        var frame = window.frame
        let contentRect = window.contentRect(forFrameRect: frame)
        let deltaHeight = viewController.paneContentSize.height - contentRect.height
        frame.origin.y -= deltaHeight
        frame.size.height += deltaHeight
        frame.size.width += viewController.paneContentSize.width - contentRect.width
        window.setFrame(frame, display: true, animate: true)
    }
}

@MainActor
protocol WorkspacePreferencesPane where Self: NSViewController {
    var paneContentSize: NSSize { get }
    func refresh()
}
