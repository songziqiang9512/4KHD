import AppKit

@MainActor
final class WorkspaceSplitLayoutController {
    private unowned let hostView: NSView
    private unowned let splitView: NSSplitView
    private unowned let sidebarItem: NSSplitViewItem
    private unowned let detailItem: NSSplitViewItem
    private let stateStore: WorkspaceWindowStateStore
    private let widthTolerance: CGFloat = 1

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
        let windowWidth = resolvedWindowWidth()
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
        let storedState = stateStore.load()
        for candidate in [
            preferredWidths,
            storedState?.presentedSplitViewWidths,
            storedState?.splitViewWidths,
            stateStore.legacySplitViewWidths()
        ] {
            guard let widths = candidate,
                  widths.count == 3,
                  widths[2] >= Int(detailItem.minimumThickness) else { continue }
            restoreDetailWidth(CGFloat(widths[2]), storedSidebarWidth: CGFloat(widths[0]))
            return
        }
        applyDefaultSplitViewWidths(isSidebarHidden: sidebarItem.isCollapsed)
    }

    func restoreContentWidthForHiddenSidebar(preferredWidths: [Int]? = nil) {
        let storedState = stateStore.load()
        for candidate in [
            preferredWidths,
            storedState?.presentedSplitViewWidths,
            storedState?.splitViewWidths,
            stateStore.legacySplitViewWidths()
        ] {
            guard let widths = candidate,
                  widths.count == 3,
                  widths[1] >= Int(WorkspaceSplitLayoutMetrics.minimumContentWidth) else { continue }
            restoreSplitViewWidths(widths, isSidebarHidden: true)
            return
        }
        applyDefaultSplitViewWidths(isSidebarHidden: true)
    }

    func currentSidebarWidth() -> Int? {
        guard !isSidebarVisuallyHidden,
              splitView.arrangedSubviews.count == 3 else { return nil }
        let width = splitView.arrangedSubviews[0].frame.width
        guard width.isFinite,
              width >= sidebarItem.minimumThickness else { return nil }
        return Int(floor(width))
    }

    func currentSplitViewWidths() -> [Int]? {
        guard splitView.arrangedSubviews.count == 3 else { return nil }

        let isSidebarHidden = isSidebarVisuallyHidden
        let rawSidebarWidth = splitView.arrangedSubviews[0].frame.width
        let rawDetailWidth = splitView.arrangedSubviews[2].frame.width

        guard let detailWidth = width(rawDetailWidth, minimum: detailItem.minimumThickness) else { return nil }

        let sidebarWidth: CGFloat
        if isSidebarHidden {
            sidebarWidth = 0
        } else {
            guard let visibleSidebarWidth = width(rawSidebarWidth, minimum: sidebarItem.minimumThickness) else {
                return nil
            }
            sidebarWidth = visibleSidebarWidth
        }

        let dividerTotal = isSidebarHidden ? splitView.dividerThickness : splitView.dividerThickness * 2
        let contentWidth = resolvedWindowWidth() - sidebarWidth - detailWidth - dividerTotal
        guard let contentWidth = width(contentWidth, minimum: WorkspaceSplitLayoutMetrics.minimumContentWidth) else {
            return nil
        }

        return [sidebarWidth, contentWidth, detailWidth].map { Int(floor($0)) }
    }

    var isSidebarVisuallyHidden: Bool {
        guard splitView.arrangedSubviews.count == 3 else { return sidebarItem.isCollapsed }
        let width = splitView.arrangedSubviews[0].frame.width
        return sidebarItem.isCollapsed || !width.isFinite || width < sidebarItem.minimumThickness - widthTolerance
    }

    func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        guard !isSidebarVisuallyHidden,
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
        let windowWidth = resolvedWindowWidth()

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
        let windowWidth = resolvedWindowWidth()
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

    private func resolvedWindowWidth() -> CGFloat {
        let splitWidth = splitView.bounds.width
        if splitWidth.isFinite, splitWidth > 0 {
            return splitWidth
        }
        let hostWidth = hostView.bounds.width
        if hostWidth.isFinite, hostWidth > 0 {
            return hostWidth
        }
        return WorkspaceSplitLayoutMetrics.defaultSidebarWidth
            + WorkspaceSplitLayoutMetrics.defaultContentWidth
            + detailItem.minimumThickness
            + splitView.dividerThickness * 2
    }

    private func width(_ value: CGFloat, minimum: CGFloat) -> CGFloat? {
        guard value.isFinite,
              value >= minimum - widthTolerance else { return nil }
        return max(value, minimum)
    }
}
