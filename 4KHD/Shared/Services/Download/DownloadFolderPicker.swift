import AppKit

enum DownloadFolderPicker {
    private static let lastDirectoryKey = "com.songziqiang.4khd.albumDownloadFolder.v1"

    /// 选择图集保存根目录;记住上次选择,下次打开时定位到同一目录。
    @MainActor
    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "图集将保存到该目录下以图集名命名的文件夹中"
        if let last = UserDefaults.standard.string(forKey: lastDirectoryKey) {
            panel.directoryURL = URL(fileURLWithPath: last, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: lastDirectoryKey)
        return url
    }
}
