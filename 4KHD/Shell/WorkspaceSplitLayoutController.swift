import AppKit

@MainActor
final class WorkspaceSplitLayoutController {
    private unowned let hostView: NSView
    private unowned let splitView: NSSplitView
    private unowned let sidebarItem: NSSplitViewItem
    private unowned let detailItem: NSSplitViewItem
    private let stateStore: WorkspaceWindowStateStore

    init(
        hostView: NSView,
        splitView: NSSplitView,
        sidebarItem: NSSplitViewItem,
        detailItem: NSSplitViewItem,
        stateStore: WorkspaceWindowStateStore
    ) {
        self.hostView = hostView
        self.splitView = splitView
        self.sidebarItem = sidebarItem
        self.detailItem = detailItem
        self.stateStore = stateStore
    }

    func restoreSplitViewWidths(_ widths: [Int], isSidebarHidden: Bool) {
        guard canRestoreSplitViewWidths(widths, isSidebarHidden: isSidebarHidden) else {
            applyDefaultSplitViewWidths(isSidebarHidden: isSidebarHidden)
            return
        }

        let dividerThickness = splitView.dividerThickness
        let sidebarWidth = CGFloat(widths[0])
        let contentWidth = CGFloat(widths[1])

        if isSidebarHidden {
            splitView.setPosition(0, ofDividerAt: 0)
            splitView.setPosition(contentWidth, ofDividerAt: 1)
        } else {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            splitView.setPosition(sidebarWidth + dividerThickness + contentWidth, ofDividerAt: 1)
        }

        sidebarItem.isCollapsed = isSidebarHidden
    }

    func applyDefaultSplitViewWidths(isSidebarHidden: Bool = false) {
        let dividerThickness = splitView.dividerThickness
        let windowWidth = hostView.window?.frame.width ?? hostView.bounds.width
        let sidebarWidth = isSidebarHidden ? 0 : WorkspaceSplitLayoutMetrics.defaultSidebarWidth
        let dividerTotal = isSidebarHidden ? dividerThickness : dividerThickness * 2
        let maxContentWidth = max(
            WorkspaceSplitLayoutMetrics.minimumContentWidth,
            windowWidth - sidebarWidth - detailItem.minimumThickness - dividerTotal
        )
        let contentWidth = min(WorkspaceSplitLayoutMetrics.defaultContentWidth, maxContentWidth)

        sidebarItem.isCollapsed = isSidebarHidden
        if isSidebarHidden {
            splitView.setPosition(0, ofDividerAt: 0)
            splitView.setPosition(contentWidth, ofDividerAt: 1)
        } else {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            splitView.setPosition(sidebarWidth + dividerThickness + contentWidth, ofDividerAt: 1)
        }
    }

    func restoreDetailWidthForPresentedDetail() {
        if let widths = stateStore.load()?.splitViewWidths ?? stateStore.legacySplitViewWidths(),
           widths.count == 3,
           widths[2] >= Int(detailItem.minimumThickness) {
            restoreDetailWidth(CGFloat(widths[2]))
            return
        }
        applyDefaultSplitViewWidths()
    }

    func currentSplitViewWidths() -> [Int]? {
        guard let window = hostView.window,
              splitView.arrangedSubviews.count == 3 else { return nil }

        let dividerThickness = splitView.dividerThickness
        let isSidebarHidden = sidebarItem.isCollapsed
        let detailWidth = splitView.arrangedSubviews[2].frame.width
        let sidebarWidth: CGFloat
        let contentWidth: CGFloat

        if isSidebarHidden {
            sidebarWidth = 0
            contentWidth = window.frame.width - (detailWidth + dividerThickness)
        } else {
            sidebarWidth = splitView.arrangedSubviews[0].frame.width
            contentWidth = window.frame.width - sidebarWidth - detailWidth - (dividerThickness * 2)
        }

        guard sidebarWidth.isFinite,
              contentWidth.isFinite,
              detailWidth.isFinite,
              contentWidth >= WorkspaceSplitLayoutMetrics.minimumContentWidth,
              detailWidth >= detailItem.minimumThickness else { return nil }

        return [sidebarWidth, contentWidth, detailWidth].map { Int(floor($0)) }
    }

    private func canRestoreSplitViewWidths(_ widths: [Int], isSidebarHidden: Bool) -> Bool {
        guard widths.count == 3 else { return false }

        let sidebarWidth = isSidebarHidden ? 0 : CGFloat(widths[0])
        let contentWidth = CGFloat(widths[1])
        let detailWidth = CGFloat(widths[2])
        let dividerThickness = splitView.dividerThickness
        let dividerTotal = isSidebarHidden ? dividerThickness : dividerThickness * 2
        let windowWidth = hostView.window?.frame.width ?? hostView.bounds.width

        guard sidebarWidth.isFinite,
              contentWidth.isFinite,
              detailWidth.isFinite,
              windowWidth.isFinite else { return false }
        guard sidebarWidth >= 0,
              contentWidth >= WorkspaceSplitLayoutMetrics.minimumContentWidth,
              detailWidth >= detailItem.minimumThickness else { return false }

        return windowWidth >= sidebarWidth + contentWidth + detailItem.minimumThickness + dividerTotal
    }

    private func restoreDetailWidth(_ storedDetailWidth: CGFloat) {
        let dividerThickness = splitView.dividerThickness
        let sidebarWidth = sidebarItem.isCollapsed
            ? 0
            : max(
                splitView.arrangedSubviews.first?.frame.width ?? 0,
                WorkspaceSplitLayoutMetrics.defaultSidebarWidth
            )
        let windowWidth = hostView.window?.frame.width ?? hostView.bounds.width
        let dividerTotal = sidebarItem.isCollapsed ? dividerThickness : dividerThickness * 2
        let maximumDetailWidth = max(
            detailItem.minimumThickness,
            windowWidth - sidebarWidth - WorkspaceSplitLayoutMetrics.minimumContentWidth - dividerTotal
        )
        let detailWidth = min(max(storedDetailWidth, detailItem.minimumThickness), maximumDetailWidth)
        let contentWidth = max(
            WorkspaceSplitLayoutMetrics.minimumContentWidth,
            windowWidth - sidebarWidth - detailWidth - dividerTotal
        )

        if !sidebarItem.isCollapsed {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        }
        splitView.setPosition(sidebarWidth + dividerThickness + contentWidth, ofDividerAt: 1)
    }
}
