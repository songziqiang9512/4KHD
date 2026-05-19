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
        let sidebarWidth = isSidebarHidden ? 0 : max(CGFloat(widths[0]), sidebarItem.minimumThickness)
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
        let windowWidth = splitView.bounds.width > 0 ? splitView.bounds.width : hostView.bounds.width
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

    func restoreDetailWidthForPresentedDetail(preferredWidths: [Int]? = nil) {
        for candidate in [preferredWidths, stateStore.load()?.splitViewWidths, stateStore.legacySplitViewWidths()] {
            guard let widths = candidate,
                  widths.count == 3,
                  widths[2] >= Int(detailItem.minimumThickness) else { continue }
            restoreDetailWidth(CGFloat(widths[2]), storedSidebarWidth: CGFloat(widths[0]))
            return
        }
        applyDefaultSplitViewWidths(isSidebarHidden: sidebarItem.isCollapsed)
    }

    func restoreContentWidthForHiddenSidebar(preferredWidths: [Int]? = nil) {
        for candidate in [preferredWidths, stateStore.load()?.splitViewWidths, stateStore.legacySplitViewWidths()] {
            guard let widths = candidate,
                  widths.count == 3,
                  widths[1] >= Int(WorkspaceSplitLayoutMetrics.minimumContentWidth) else { continue }
            restoreSplitViewWidths(widths, isSidebarHidden: true)
            return
        }
        applyDefaultSplitViewWidths(isSidebarHidden: true)
    }

    func currentSidebarWidth() -> Int? {
        guard !sidebarItem.isCollapsed,
              splitView.arrangedSubviews.count == 3 else { return nil }
        let width = splitView.arrangedSubviews[0].frame.width
        guard width.isFinite,
              width >= sidebarItem.minimumThickness else { return nil }
        return Int(floor(width))
    }

    func currentSplitViewWidths() -> [Int]? {
        guard splitView.arrangedSubviews.count == 3 else { return nil }

        let dividerThickness = splitView.dividerThickness
        let isSidebarHidden = sidebarItem.isCollapsed
        let detailWidth = splitView.arrangedSubviews[2].frame.width
        let sidebarWidth: CGFloat
        let contentWidth: CGFloat

        if isSidebarHidden {
            sidebarWidth = 0
            contentWidth = splitView.bounds.width - (detailWidth + dividerThickness)
        } else {
            sidebarWidth = splitView.arrangedSubviews[0].frame.width
            contentWidth = splitView.bounds.width - sidebarWidth - detailWidth - (dividerThickness * 2)
        }

        guard sidebarWidth.isFinite,
              contentWidth.isFinite,
              detailWidth.isFinite,
              contentWidth >= WorkspaceSplitLayoutMetrics.minimumContentWidth,
              detailWidth >= detailItem.minimumThickness else { return nil }

        return [sidebarWidth, contentWidth, detailWidth].map { Int(floor($0)) }
    }

    func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        guard !sidebarItem.isCollapsed,
              splitView.arrangedSubviews.count == 3 else { return 0 }

        let dividerTotal = splitView.dividerThickness * 2
        let detailWidth = splitView.arrangedSubviews[2].frame.width
        let maximumWidth = max(
            sidebarItem.minimumThickness,
            splitView.bounds.width
                - WorkspaceSplitLayoutMetrics.minimumContentWidth
                - detailWidth
                - dividerTotal
        )
        return min(max(width, sidebarItem.minimumThickness), maximumWidth)
    }

    private func canRestoreSplitViewWidths(_ widths: [Int], isSidebarHidden: Bool) -> Bool {
        guard widths.count == 3 else { return false }

        let sidebarWidth = isSidebarHidden ? 0 : CGFloat(widths[0])
        let contentWidth = CGFloat(widths[1])
        let detailWidth = CGFloat(widths[2])
        let dividerThickness = splitView.dividerThickness
        let dividerTotal = isSidebarHidden ? dividerThickness : dividerThickness * 2
        let windowWidth = splitView.bounds.width > 0 ? splitView.bounds.width : hostView.bounds.width

        guard sidebarWidth.isFinite,
              contentWidth.isFinite,
              detailWidth.isFinite,
              windowWidth.isFinite else { return false }
        guard sidebarWidth >= (isSidebarHidden ? 0 : sidebarItem.minimumThickness),
              contentWidth >= WorkspaceSplitLayoutMetrics.minimumContentWidth,
              detailWidth >= detailItem.minimumThickness else { return false }

        return windowWidth >= sidebarWidth + contentWidth + detailItem.minimumThickness + dividerTotal
    }

    private func restoreDetailWidth(_ storedDetailWidth: CGFloat, storedSidebarWidth: CGFloat?) {
        let dividerThickness = splitView.dividerThickness
        let currentSidebarWidth = splitView.arrangedSubviews.first?.frame.width ?? 0
        let sidebarWidth = sidebarItem.isCollapsed ? 0 : resolvedSidebarWidth(
            currentWidth: currentSidebarWidth,
            storedWidth: storedSidebarWidth
        )
        let windowWidth = splitView.bounds.width > 0 ? splitView.bounds.width : hostView.bounds.width
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

    private func resolvedSidebarWidth(currentWidth: CGFloat, storedWidth: CGFloat?) -> CGFloat {
        if currentWidth.isFinite, currentWidth >= sidebarItem.minimumThickness {
            return currentWidth
        }
        if let storedWidth, storedWidth.isFinite, storedWidth >= sidebarItem.minimumThickness {
            return storedWidth
        }
        return WorkspaceSplitLayoutMetrics.defaultSidebarWidth
    }
}
