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
