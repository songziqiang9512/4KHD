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
    private var downloadsWindowController: WorkspaceDownloadsWindowController?

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showDownloadsWindow(_:)),
            name: WorkspaceDownloadsPresenter.showNotification,
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
        // 中断下载任务与在飞请求;任务不持久化,已下载文件保留。
        appContext?.downloadStore.shutdown()
        // 落盘防抖窗口内的详情页缓存变更，避免退出瞬间丢失。
        DetailPageImageCache.shared.flush()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc func showMainWindow(_ sender: Any?) {
        windowController?.showWindow(sender)
        windowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 转发 undo:/redo: 走响应链。菜单项直接用系统 selector 时,
    /// AppKit 会自动把标题替换成系统语言的 "Undo"/"Redo"。
    @objc func undoFromMenu(_ sender: Any?) {
        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
    }

    @objc func redoFromMenu(_ sender: Any?) {
        NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
    }

    @objc func showPreferences(_ sender: Any?) {
        guard let appContext else { return }
        if preferencesWindowController == nil {
            preferencesWindowController = WorkspacePreferencesWindowController(
                appContext: appContext
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

    @objc func showDownloadsWindow(_ sender: Any?) {
        guard let appContext else { return }
        if downloadsWindowController == nil {
            downloadsWindowController = WorkspaceDownloadsWindowController(
                downloadStore: appContext.downloadStore
            )
        }
        downloadsWindowController?.showWindow(sender)
        downloadsWindowController?.window?.makeKeyAndOrderFront(sender)
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

extension FourKHDAppDelegate: NSMenuItemValidation {
    /// 转发项显式绑定 target 后不再走响应链自动校验;
    /// 手动按响应链是否存在 undo:/redo: 响应者决定启用状态。
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(FourKHDAppDelegate.undoFromMenu(_:)):
            return NSApp.target(forAction: Selector(("undo:")), to: nil, from: nil) != nil
        case #selector(FourKHDAppDelegate.redoFromMenu(_:)):
            return NSApp.target(forAction: Selector(("redo:")), to: nil, from: nil) != nil
        default:
            return true
        }
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
				title: "关于 \(appName)",
				action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
				keyEquivalent: ""
			)
		)
		let updateItem = NSMenuItem(
			title: "检查更新…",
			action: #selector(AppUpdateController.checkForUpdates(_:)),
			keyEquivalent: ""
		)
		updateItem.target = AppUpdateController.shared
		menu.addItem(updateItem)
		menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(FourKHDAppDelegate.showPreferences(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = NSApp.delegate as AnyObject?
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服务")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "隐藏 \(appName)",
                action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"
            )
        )
        let hideOthers = NSMenuItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(
            NSMenuItem(
                title: "全部显示",
                action: #selector(NSApplication.unhideAllApplications(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出 \(appName)",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        item.submenu = menu
        return item
    }

    private static func fileMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "文件")
        menu.addItem(
            NSMenuItem(
                title: "导入目录…",
                action: #selector(WorkspaceSplitViewController.importLocalFolder(_:)),
                keyEquivalent: "o"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "收藏",
                action: #selector(WorkspaceSplitViewController.toggleCurrentFavorite(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "打开原网页",
                action: #selector(WorkspaceSplitViewController.openCurrentReference(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "显示简介",
                action: #selector(WorkspaceSplitViewController.showCurrentInspector(_:)),
                keyEquivalent: "i"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "保存图片…",
                action: #selector(WorkspaceSplitViewController.saveCurrentImage(_:)),
                keyEquivalent: "s"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "快速预览",
                action: #selector(WorkspaceSplitViewController.quickLookCurrentFile(_:)),
                keyEquivalent: "y"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "在 Finder 中显示",
                action: #selector(WorkspaceSplitViewController.revealCurrentFileInFinder(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "设为桌面壁纸",
                action: #selector(WorkspaceSplitViewController.setCurrentFileAsDesktopWallpaper(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "共享…",
                action: #selector(WorkspaceSplitViewController.shareCurrentContent(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "关闭",
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )
        item.submenu = menu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "编辑")
        let undoItem = NSMenuItem(
            title: "撤销",
            action: #selector(FourKHDAppDelegate.undoFromMenu(_:)),
            keyEquivalent: "z"
        )
        undoItem.target = NSApp.delegate as AnyObject?
        menu.addItem(undoItem)
        let redoItem = NSMenuItem(
            title: "重做",
            action: #selector(FourKHDAppDelegate.redoFromMenu(_:)),
            keyEquivalent: "Z"
        )
        redoItem.target = NSApp.delegate as AnyObject?
        menu.addItem(redoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(
            title: "复制链接",
            action: #selector(WorkspaceSplitViewController.copyCurrentReference(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "查找",
                action: #selector(WorkspaceSplitViewController.moveFocusToSearchField(_:)),
                keyEquivalent: "f"
            )
        )
        item.submenu = menu
        return item
    }

    private static func viewMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "显示")
        menu.addItem(
            NSMenuItem(
                title: "切换工具栏",
                action: #selector(NSWindow.toggleToolbarShown(_:)),
                keyEquivalent: "t"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "刷新",
                action: #selector(WorkspaceSplitViewController.refreshCurrentContent(_:)),
                keyEquivalent: "r"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "实际大小",
                action: #selector(WorkspaceSplitViewController.resetCurrentZoom(_:)),
                keyEquivalent: "0"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "上一张图片",
                action: #selector(WorkspaceSplitViewController.selectPreviousImage(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "下一张图片",
                action: #selector(WorkspaceSplitViewController.selectNextImage(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(layoutMenuItem())
        menu.addItem(gridColumnsMenuItem())
        menu.addItem(localSortMenuItem())
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "切换侧边栏",
                action: #selector(WorkspaceSplitViewController.toggleWorkspaceSidebar(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "切换详情区",
                action: #selector(WorkspaceSplitViewController.toggleWorkspaceDetailPane(_:)),
                keyEquivalent: "\\"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "进入大图模式",
                action: #selector(WorkspaceSplitViewController.toggleImmersiveMode(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "聚焦侧边栏",
                action: #selector(WorkspaceSplitViewController.navigateToSidebar(_:)),
                keyEquivalent: "1"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "聚焦内容区",
                action: #selector(WorkspaceSplitViewController.navigateToContent(_:)),
                keyEquivalent: "2"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "聚焦详情区",
                action: #selector(WorkspaceSplitViewController.navigateToDetail(_:)),
                keyEquivalent: "3"
            )
        )
        item.submenu = menu
        return item
    }

    private static func layoutMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "布局", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "布局")
        menu.addItem(NSMenuItem(
            title: "列表",
            action: #selector(WorkspaceSplitViewController.setContentListLayout(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "网格",
            action: #selector(WorkspaceSplitViewController.setContentGridLayout(_:)),
            keyEquivalent: ""
        ))
        item.submenu = menu
        return item
    }

    private static func gridColumnsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "网格列数", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "网格列数")
        menu.addItem(NSMenuItem(
            title: "增加列数",
            action: #selector(WorkspaceSplitViewController.increaseLocalGridColumns(_:)),
            keyEquivalent: "-"
        ))
        menu.addItem(NSMenuItem(
            title: "减少列数",
            action: #selector(WorkspaceSplitViewController.decreaseLocalGridColumns(_:)),
            keyEquivalent: "="
        ))
        item.submenu = menu
        return item
    }

    private static func localSortMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "本地图片排序", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "本地图片排序")
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
        let menu = NSMenu(title: "窗口")
        menu.addItem(
            NSMenuItem(
                title: "最小化",
                action: #selector(NSWindow.performMiniaturize(_:)),
                keyEquivalent: "m"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "缩放",
                action: #selector(NSWindow.performZoom(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        let mainWindowItem = NSMenuItem(
            title: "主窗口",
            action: #selector(FourKHDAppDelegate.showMainWindow(_:)),
            keyEquivalent: ""
        )
        mainWindowItem.target = NSApp.delegate as AnyObject?
        menu.addItem(mainWindowItem)
        let inspectorItem = NSMenuItem(
            title: "信息",
            action: #selector(FourKHDAppDelegate.showInspector(_:)),
            keyEquivalent: "i"
        )
        inspectorItem.keyEquivalentModifierMask = [.command, .option]
        inspectorItem.target = NSApp.delegate as AnyObject?
        menu.addItem(inspectorItem)
        let downloadsItem = NSMenuItem(
            title: "下载",
            action: #selector(FourKHDAppDelegate.showDownloadsWindow(_:)),
            keyEquivalent: "d"
        )
        downloadsItem.keyEquivalentModifierMask = [.command, .option]
        downloadsItem.target = NSApp.delegate as AnyObject?
        menu.addItem(downloadsItem)
        // windowsMenu 会由系统自动注入「全部前置」等标准窗口项(标题跟随系统语言),
        // 不要自行添加 arrangeInFront,避免重复。
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }

    private static func helpMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "帮助")
        let keyboardItem = NSMenuItem(
            title: "键盘快捷键",
            action: #selector(FourKHDAppDelegate.showKeyboardShortcutsWindow(_:)),
            keyEquivalent: "?"
        )
        keyboardItem.target = NSApp.delegate as AnyObject?
        menu.addItem(keyboardItem)
        menu.addItem(.separator())
        let supportFolderItem = NSMenuItem(
            title: "打开应用支持目录",
            action: #selector(FourKHDAppDelegate.openApplicationSupportFolder(_:)),
            keyEquivalent: ""
        )
        supportFolderItem.target = NSApp.delegate as AnyObject?
        menu.addItem(supportFolderItem)
        let imageCacheItem = NSMenuItem(
            title: "打开图片缓存目录",
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
