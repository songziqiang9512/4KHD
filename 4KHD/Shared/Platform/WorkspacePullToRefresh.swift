import AppKit

/// Attaches macOS 27 `NSRefreshController` to an `NSScrollView` without requiring
/// the macOS 27 SDK at compile time. No-ops on older systems.
enum WorkspacePullToRefresh {
    static func install(on scrollView: NSScrollView, target: AnyObject, action: Selector) {
        let setter = NSSelectorFromString("setRefreshController:")
        guard scrollView.responds(to: setter),
              let type = NSClassFromString("NSRefreshController") as? NSObject.Type
        else { return }
        if scrollView.value(forKey: "refreshController") != nil { return }
        let controller = type.init()
        controller.setValue(target, forKey: "target")
        setAction(controller, action)
        scrollView.setValue(controller, forKey: "refreshController")
    }

    static func sync(_ scrollView: NSScrollView, isRefreshing: Bool) {
        guard let controller = scrollView.value(forKey: "refreshController") as? NSObject else { return }
        let refreshing = (controller.value(forKey: "isRefreshing") as? Bool) ?? false
        if isRefreshing, !refreshing {
            controller.perform(NSSelectorFromString("beginRefreshing"))
        } else if !isRefreshing, refreshing {
            controller.perform(NSSelectorFromString("endRefreshing"))
        }
    }

    private static func setAction(_ object: NSObject, _ action: Selector) {
        let selector = NSSelectorFromString("setAction:")
        guard object.responds(to: selector), let imp = object.method(for: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Selector) -> Void
        unsafeBitCast(imp, to: Setter.self)(object, selector, action)
    }
}
