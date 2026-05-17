import AppKit

@main
private enum FourKHDApplicationMain {
    private static let appDelegate = FourKHDAppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }
}

final class FourKHDAppDelegate: NSObject, NSApplicationDelegate {
    private var appContext: WorkspaceAppContext?
    private var windowController: WorkspaceWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MainMenuBuilder.install()

        let appContext = WorkspaceAppAssembly.makeAppContext()
        self.appContext = appContext

        let windowController = WorkspaceWindowController(appContext: appContext)
        self.windowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }
}

@MainActor
private final class WorkspaceWindowController: NSWindowController {
    init(appContext: WorkspaceAppContext) {
        let shellController = WorkspaceSplitViewController(appContext: appContext)
        let window = NSWindow(contentViewController: shellController)
        window.title = "4KHD"
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.minSize = NSSize(width: 1080, height: 700)
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .shadow
        window.toolbarStyle = .unified
        super.init(window: window)
        let toolbar = WorkspaceToolbar(appContext: appContext)
        window.toolbar = toolbar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class WorkspaceToolbar: NSToolbar, NSToolbarDelegate, NSSearchFieldDelegate {
    private enum ItemID {
        static let search = NSToolbarItem.Identifier("WorkspaceToolbar.search")
        static let layout = NSToolbarItem.Identifier("WorkspaceToolbar.layout")
        static let refresh = NSToolbarItem.Identifier("WorkspaceToolbar.refresh")
        static let detailPane = NSToolbarItem.Identifier("WorkspaceToolbar.detailPane")
        static let cacheLimit = NSToolbarItem.Identifier("WorkspaceToolbar.cacheLimit")
        static let importFolder = NSToolbarItem.Identifier("WorkspaceToolbar.importFolder")
    }

    private let appContext: WorkspaceAppContext
    private let searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
    private var routeObserverID: UUID?
    private weak var layoutControl: NSSegmentedControl?
    private weak var refreshItem: NSToolbarItem?
    private weak var detailPaneItem: NSToolbarItem?
    private weak var cacheLimitItem: NSToolbarItem?

    init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
        super.init(identifier: "WorkspaceToolbar")
        displayMode = .iconOnly
        allowsUserCustomization = false
        delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        searchField.heightAnchor.constraint(equalToConstant: 28).isActive = true
        searchField.bezelStyle = .roundedBezel
        searchField.isBordered = true
        searchField.drawsBackground = true
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        routeObserverID = appContext.routeController.addObserver { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let routeObserverID {
            Task { @MainActor [appContext] in
                appContext.routeController.removeObserver(id: routeObserverID)
            }
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            ItemID.layout,
            ItemID.refresh,
            ItemID.detailPane,
            ItemID.cacheLimit,
            ItemID.importFolder,
            .flexibleSpace,
            ItemID.search
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ItemID.search:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = searchField
            item.label = "搜索"
            item.paletteLabel = "搜索"
            item.visibilityPriority = .high
            return item
        case ItemID.layout:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let control = NSSegmentedControl(labels: ["列表", "网格"], trackingMode: .selectOne, target: self, action: #selector(layoutChanged(_:)))
            control.segmentStyle = .texturedRounded
            control.setWidth(48, forSegment: 0)
            control.setWidth(48, forSegment: 1)
            control.toolTip = "切换列表/网格"
            item.view = control
            item.label = "布局"
            item.paletteLabel = "布局"
            item.visibilityPriority = .high
            layoutControl = control
            updateLayoutControl()
            return item
        case ItemID.refresh:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(refreshContent(_:))
            item.label = "刷新"
            item.paletteLabel = "刷新"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
            item.toolTip = "刷新当前内容"
            item.visibilityPriority = .high
            refreshItem = item
            updateRefreshItem()
            return item
        case ItemID.detailPane:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.target = self
            item.action = #selector(toggleDetailPane(_:))
            item.label = "详情区"
            item.paletteLabel = "详情区"
            item.visibilityPriority = .high
            detailPaneItem = item
            configureDetailPaneItem(item)
            return item
        case ItemID.cacheLimit:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "缓存容量"
            item.paletteLabel = "缓存容量"
            item.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "缓存容量")
            item.menu = makeCacheLimitMenu()
            item.visibilityPriority = .low
            cacheLimitItem = item
            return item
        case ItemID.importFolder:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "导入目录"
            item.paletteLabel = "导入目录"
            item.toolTip = "导入本地图片文件夹"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "导入目录")
            item.target = self
            item.action = #selector(importFolder(_:))
            item.visibilityPriority = .standard
            return item
        default:
            return nil
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else { return }
        appContext.toolbarContext.setSearchText(searchField.stringValue, for: currentModuleID)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else { return }
        appContext.toolbarContext.submitSearch(for: currentModuleID)
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        appContext.toolbarContext.setSearchText(sender.stringValue, for: currentModuleID)
    }

    @objc private func toggleDetailPane(_ sender: Any?) {
        appContext.detailPaneController.toggle()
        configureDetailPaneItem(detailPaneItem)
    }

    @objc private func layoutChanged(_ sender: NSSegmentedControl) {
        switch currentModuleID {
        case .fourKHDGallery:
            appContext.toolbarContext.setGalleryLayout(sender.selectedSegment == 0 ? .list : .grid)
        case .localLibrary:
            appContext.toolbarContext.setLocalLayout(sender.selectedSegment == 0 ? .list : .grid)
        }
        refresh()
    }

    @objc private func refreshContent(_ sender: Any?) {
        appContext.toolbarContext.refresh(for: currentModuleID)
        refresh()
    }

    @objc private func importFolder(_ sender: Any?) {
        appContext.importRootFolder()
    }

    @objc private func selectCacheLimit(_ sender: NSMenuItem) {
        guard let limit = sender.representedObject as? OnlineCacheLimit else { return }
        UserDefaults.standard.set(limit.rawValue, forKey: OnlineCacheLimit.defaultsKey)
        RemoteImagePipeline.shared.applyCacheLimit(limit)
        (cacheLimitItem as? NSMenuToolbarItem)?.menu = makeCacheLimitMenu()
    }

    private var currentModuleID: WorkspaceModuleID {
        appContext.routeController.route.moduleID
    }

    private func refresh() {
        updateSearchField()
        updateLayoutControl()
        updateRefreshItem()
        configureDetailPaneItem(detailPaneItem)
    }

    private func updateSearchField() {
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        let text: String
        switch snapshot {
        case .gallery(let gallerySnapshot):
            text = gallerySnapshot.searchText
            searchField.placeholderString = "搜索 4KHD"
        case .local(let localSnapshot):
            text = localSnapshot.searchText
            searchField.placeholderString = "搜索本地图片"
        }
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    private func updateLayoutControl() {
        guard let layoutControl else { return }
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        switch snapshot {
        case .gallery(let gallerySnapshot):
            layoutControl.selectedSegment = gallerySnapshot.layout == .list ? 0 : 1
        case .local(let localSnapshot):
            layoutControl.selectedSegment = localSnapshot.layout == .list ? 0 : 1
        }
    }

    private func updateRefreshItem() {
        guard let refreshItem else { return }
        let snapshot = appContext.toolbarContext.snapshot(for: currentModuleID)
        switch snapshot {
        case .gallery(let gallerySnapshot):
            refreshItem.isEnabled = !gallerySnapshot.isRefreshing
            refreshItem.toolTip = gallerySnapshot.isRefreshing ? "正在刷新 4KHD" : "刷新 4KHD"
        case .local(let localSnapshot):
            refreshItem.isEnabled = !localSnapshot.isRefreshing && localSnapshot.hasSelection
            refreshItem.toolTip = localSnapshot.hasSelection ? "刷新本地图片" : "先选择一个本地目录"
        }
    }

    private func configureDetailPaneItem(_ item: NSToolbarItem?) {
        guard let item else { return }
        let isPresented = appContext.detailPaneController.isPresented
        item.image = NSImage(
            systemSymbolName: "sidebar.right",
            accessibilityDescription: isPresented ? "隐藏详情区" : "显示详情区"
        )
        item.toolTip = isPresented ? "隐藏右侧详情区" : "显示右侧详情区"
    }

    private func makeCacheLimitMenu() -> NSMenu {
        let menu = NSMenu(title: "缓存容量")
        let current = OnlineCacheLimit.current
        for limit in OnlineCacheLimit.allCases {
            let item = NSMenuItem(title: limit.title, action: #selector(selectCacheLimit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = limit
            item.state = limit == current ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
}

private enum MainMenuBuilder {
    static func install() {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(windowMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private static func appMenuItem() -> NSMenuItem {
        let appName = ProcessInfo.processInfo.processName
        let item = NSMenuItem()
        let menu = NSMenu(title: appName)
        menu.addItem(
            NSMenuItem(
                title: "Hide \(appName)",
                action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"
            )
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(
            NSMenuItem(
                title: "Show All",
                action: #selector(NSApplication.unhideAllApplications(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit \(appName)",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        item.submenu = menu
        return item
    }

    private static func fileMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")
        menu.addItem(
            NSMenuItem(
                title: "Close",
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )
        item.submenu = menu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        menu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        item.submenu = menu
        return item
    }

    private static func viewMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "View")
        menu.addItem(
            NSMenuItem(
                title: "Toggle Toolbar",
                action: #selector(NSWindow.toggleToolbarShown(_:)),
                keyEquivalent: "t"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Toggle Sidebar",
                action: #selector(WorkspaceSplitViewController.toggleWorkspaceSidebar(_:)),
                keyEquivalent: ""
            )
        )
        item.submenu = menu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")
        menu.addItem(
            NSMenuItem(
                title: "Minimize",
                action: #selector(NSWindow.performMiniaturize(_:)),
                keyEquivalent: "m"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Zoom",
                action: #selector(NSWindow.performZoom(_:)),
                keyEquivalent: ""
            )
        )
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }
}
