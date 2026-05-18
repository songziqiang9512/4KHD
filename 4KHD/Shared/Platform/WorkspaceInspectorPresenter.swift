import Foundation

enum WorkspaceInspectorPresenter {
    static let showNotification = Notification.Name("com.songziqiang.4khd.workspaceInspector.show")

    static func show() {
        NotificationCenter.default.post(name: showNotification, object: nil)
    }
}
