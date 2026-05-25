import AppKit

@MainActor
protocol WorkspaceLiveResizeScrollerHiding: AnyObject {}

extension WorkspaceLiveResizeScrollerHiding where Self: NSView {
    func workspaceWillStartLiveResize() {
        // No-op: toggling hasVerticalScroller during resize causes a ~15px content-area
        // width change at the end of every resize, making all subviews jump. The enclosing
        // scroll views already have autohidesScrollers enabled by default.
    }

    func workspaceDidEndLiveResize() {
        // No-op: see above.
    }
}
