import AppKit

@MainActor
protocol WorkspaceLiveResizeScrollerHiding: AnyObject {}

extension WorkspaceLiveResizeScrollerHiding where Self: NSView {
    func workspaceWillStartLiveResize() {
        enclosingScrollView?.hasVerticalScroller = false
    }

    func workspaceDidEndLiveResize() {
        enclosingScrollView?.hasVerticalScroller = true
    }
}
