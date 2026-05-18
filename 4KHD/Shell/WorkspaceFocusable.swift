import Foundation

@MainActor
protocol WorkspaceFocusable: AnyObject {
    func focus()
}
