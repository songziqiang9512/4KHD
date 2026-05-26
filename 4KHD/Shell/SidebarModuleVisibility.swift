import Foundation

enum SidebarModuleVisibility {
    private static let defaultsKey = "com.songziqiang.4khd.showAdvancedModules.v1"

    static let didChangeNotification = Notification.Name("SidebarModuleVisibilityDidChange")

    static var showAdvancedModules: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
