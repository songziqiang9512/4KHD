import Foundation

enum WorkspaceDownloadsPresenter {
    static let showNotification = Notification.Name("com.songziqiang.4khd.workspaceDownloads.show")

    static func show() {
        NotificationCenter.default.post(name: showNotification, object: nil)
    }
}
