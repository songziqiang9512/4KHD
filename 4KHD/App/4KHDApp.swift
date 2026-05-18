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

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.saveStateToUserDefaults()
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
                title: "Import Folder...",
                action: #selector(WorkspaceSplitViewController.importLocalFolder(_:)),
                keyEquivalent: "o"
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
                title: "Share...",
                action: #selector(WorkspaceSplitViewController.shareCurrentContent(_:)),
                keyEquivalent: "s"
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
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }
}
