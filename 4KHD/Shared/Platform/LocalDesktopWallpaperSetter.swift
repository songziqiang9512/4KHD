import AppKit

enum LocalDesktopWallpaperSetter {
    static func setDesktopWallpaper(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            presentFailure(message: "原始图片文件当前不可用。")
            return
        }

        do {
            let screen = NSScreen.main ?? NSScreen.screens.first
            guard let screen else {
                presentFailure(message: "没有找到可用的显示器。")
                return
            }
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        } catch {
            presentFailure(message: error.localizedDescription)
        }
    }

    private static func presentFailure(message: String) {
        let alert = makeAppAlert(
            title: "设置桌面壁纸失败",
            message: message,
            style: .warning
        )
        presentAppAlert(alert)
    }
}
