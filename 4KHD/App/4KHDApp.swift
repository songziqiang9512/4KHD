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
    private var preferencesWindowController: WorkspacePreferencesWindowController?
    private var keyboardShortcutsWindowController: WorkspaceKeyboardShortcutsWindowController?
    private var inspectorWindowController: WorkspaceInspectorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MainMenuBuilder.install()

        let appContext = WorkspaceAppAssembly.makeAppContext()
        self.appContext = appContext
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showInspector(_:)),
            name: WorkspaceInspectorPresenter.showNotification,
            object: nil
        )

        let windowController = WorkspaceWindowController(appContext: appContext)
        self.windowController = windowController
        windowController.showWindow(nil)
        restoreInspectorIfNeeded(appContext: appContext)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.saveStateToUserDefaults()
        inspectorWindowController?.saveState()
    }

    @objc func showMainWindow(_ sender: Any?) {
        windowController?.showWindow(sender)
        windowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showPreferences(_ sender: Any?) {
        guard let appContext else { return }
        if preferencesWindowController == nil {
            preferencesWindowController = WorkspacePreferencesWindowController(
                toolbarContext: appContext.toolbarContext
            )
        }
        preferencesWindowController?.refresh()
        preferencesWindowController?.showWindow(sender)
        preferencesWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showKeyboardShortcutsWindow(_ sender: Any?) {
        if keyboardShortcutsWindowController == nil {
            keyboardShortcutsWindowController = WorkspaceKeyboardShortcutsWindowController()
        }
        keyboardShortcutsWindowController?.showWindow(sender)
        keyboardShortcutsWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showInspector(_ sender: Any?) {
        guard let appContext else { return }
        showInspector(sender, appContext: appContext)
    }

    @objc func openApplicationSupportFolder(_ sender: Any?) {
        AppStorageFolders.open(AppStorageFolders.applicationSupport)
    }

    @objc func openImageCacheFolder(_ sender: Any?) {
        AppStorageFolders.open(AppStorageFolders.imageCache)
    }

    private func restoreInspectorIfNeeded(appContext: WorkspaceAppContext) {
        guard WorkspaceInspectorWindowController.shouldOpenAtStartup else { return }
        showInspector(nil, appContext: appContext)
    }

    private func showInspector(_ sender: Any?, appContext: WorkspaceAppContext) {
        if inspectorWindowController == nil {
            inspectorWindowController = WorkspaceInspectorWindowController(appContext: appContext)
        }
        inspectorWindowController?.showWindow(sender)
        inspectorWindowController?.window?.makeKeyAndOrderFront(sender)
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
        mainMenu.addItem(helpMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private static func appMenuItem() -> NSMenuItem {
        let appName = ProcessInfo.processInfo.processName
        let item = NSMenuItem()
        let menu = NSMenu(title: appName)
        menu.addItem(
            NSMenuItem(
                title: "About \(appName)",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(FourKHDAppDelegate.showPreferences(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = NSApp.delegate as AnyObject?
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        menu.addItem(.separator())
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
                title: "Import Folder...",
                action: #selector(WorkspaceSplitViewController.importLocalFolder(_:)),
                keyEquivalent: "o"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Favorite",
                action: #selector(WorkspaceSplitViewController.toggleCurrentFavorite(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Open Original",
                action: #selector(WorkspaceSplitViewController.openCurrentReference(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Get Info",
                action: #selector(WorkspaceSplitViewController.showCurrentInspector(_:)),
                keyEquivalent: "i"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Save Image...",
                action: #selector(WorkspaceSplitViewController.saveCurrentImage(_:)),
                keyEquivalent: "s"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Quick Look",
                action: #selector(WorkspaceSplitViewController.quickLookCurrentFile(_:)),
                keyEquivalent: "y"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Reveal in Finder",
                action: #selector(WorkspaceSplitViewController.revealCurrentFileInFinder(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Set Desktop Wallpaper",
                action: #selector(WorkspaceSplitViewController.setCurrentFileAsDesktopWallpaper(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Share...",
                action: #selector(WorkspaceSplitViewController.shareCurrentContent(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
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
        menu.addItem(NSMenuItem(
            title: "Copy Link",
            action: #selector(WorkspaceSplitViewController.copyCurrentReference(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Find",
                action: #selector(WorkspaceSplitViewController.moveFocusToSearchField(_:)),
                keyEquivalent: "f"
            )
        )
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
                title: "Refresh",
                action: #selector(WorkspaceSplitViewController.refreshCurrentContent(_:)),
                keyEquivalent: "r"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Actual Size",
                action: #selector(WorkspaceSplitViewController.resetCurrentZoom(_:)),
                keyEquivalent: "0"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Previous Image",
                action: #selector(WorkspaceSplitViewController.selectPreviousImage(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Next Image",
                action: #selector(WorkspaceSplitViewController.selectNextImage(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(layoutMenuItem())
        menu.addItem(localSortMenuItem())
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Toggle Sidebar",
                action: #selector(WorkspaceSplitViewController.toggleWorkspaceSidebar(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Toggle Detail",
                action: #selector(WorkspaceSplitViewController.toggleWorkspaceDetailPane(_:)),
                keyEquivalent: "\\"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Enter Immersive Mode",
                action: #selector(WorkspaceSplitViewController.toggleImmersiveMode(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Focus Sidebar",
                action: #selector(WorkspaceSplitViewController.navigateToSidebar(_:)),
                keyEquivalent: "1"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Focus Content",
                action: #selector(WorkspaceSplitViewController.navigateToContent(_:)),
                keyEquivalent: "2"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Focus Detail",
                action: #selector(WorkspaceSplitViewController.navigateToDetail(_:)),
                keyEquivalent: "3"
            )
        )
        item.submenu = menu
        return item
    }

    private static func layoutMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Layout")
        menu.addItem(NSMenuItem(
            title: "List",
            action: #selector(WorkspaceSplitViewController.setContentListLayout(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Grid",
            action: #selector(WorkspaceSplitViewController.setContentGridLayout(_:)),
            keyEquivalent: ""
        ))
        item.submenu = menu
        return item
    }

    private static func localSortMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Sort Local Images", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Sort Local Images")
        for field in LocalImageSortField.allCases {
            let menuItem = NSMenuItem(
                title: field.title,
                action: #selector(WorkspaceSplitViewController.selectLocalSortFieldFromMenu(_:)),
                keyEquivalent: ""
            )
            menuItem.representedObject = field
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())
        for direction in LocalImageSortDirection.allCases {
            let menuItem = NSMenuItem(
                title: direction.title,
                action: #selector(WorkspaceSplitViewController.selectLocalSortDirectionFromMenu(_:)),
                keyEquivalent: ""
            )
            menuItem.representedObject = direction
            menu.addItem(menuItem)
        }
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
        menu.addItem(.separator())
        let mainWindowItem = NSMenuItem(
            title: "Main Window",
            action: #selector(FourKHDAppDelegate.showMainWindow(_:)),
            keyEquivalent: ""
        )
        mainWindowItem.target = NSApp.delegate as AnyObject?
        menu.addItem(mainWindowItem)
        let inspectorItem = NSMenuItem(
            title: "Inspector",
            action: #selector(FourKHDAppDelegate.showInspector(_:)),
            keyEquivalent: "i"
        )
        inspectorItem.keyEquivalentModifierMask = [.command, .option]
        inspectorItem.target = NSApp.delegate as AnyObject?
        menu.addItem(inspectorItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Bring All to Front",
                action: #selector(NSApplication.arrangeInFront(_:)),
                keyEquivalent: ""
            )
        )
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }

    private static func helpMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Help")
        let keyboardItem = NSMenuItem(
            title: "Keyboard Shortcuts",
            action: #selector(FourKHDAppDelegate.showKeyboardShortcutsWindow(_:)),
            keyEquivalent: "?"
        )
        keyboardItem.target = NSApp.delegate as AnyObject?
        menu.addItem(keyboardItem)
        menu.addItem(.separator())
        let supportFolderItem = NSMenuItem(
            title: "Open Application Support Folder",
            action: #selector(FourKHDAppDelegate.openApplicationSupportFolder(_:)),
            keyEquivalent: ""
        )
        supportFolderItem.target = NSApp.delegate as AnyObject?
        menu.addItem(supportFolderItem)
        let imageCacheItem = NSMenuItem(
            title: "Open Image Cache Folder",
            action: #selector(FourKHDAppDelegate.openImageCacheFolder(_:)),
            keyEquivalent: ""
        )
        imageCacheItem.target = NSApp.delegate as AnyObject?
        menu.addItem(imageCacheItem)
        item.submenu = menu
        NSApp.helpMenu = menu
        return item
    }
}
