import AppKit

class WorkspaceThumbnailWaterfallLayout: NSCollectionViewLayout {
    var columnSpacing: CGFloat = 8 { didSet { invalidateIfChanged(oldValue, columnSpacing) } }
    var rowSpacing: CGFloat = 10 { didSet { invalidateIfChanged(oldValue, rowSpacing) } }
    var sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12) {
        didSet { invalidateLayout() }
    }
    var minAspectRatio: CGFloat = 0.25 { didSet { invalidateIfChanged(oldValue, minAspectRatio) } }
    var maxAspectRatio: CGFloat = 3.0 { didSet { invalidateIfChanged(oldValue, maxAspectRatio) } }
    var minimumColumnCount: Int? { didSet { if oldValue != minimumColumnCount { invalidateLayout() } } }
    var maximumColumnCount: Int? { didSet { if oldValue != maximumColumnCount { invalidateLayout() } } }
    var preferredCardMinimumWidth: CGFloat = 136 {
        didSet { invalidateIfChanged(oldValue, preferredCardMinimumWidth) }
    }
    var aspectRatioProvider: ((IndexPath) -> CGFloat)?

    private var cache: [NSCollectionViewLayoutAttributes] = []
    private var columnHeights: [CGFloat] = []
    private var nextItemIndex = 0
    private var itemCount = 0
    private var contentHeight: CGFloat = 0
    private var estimatedContentHeight: CGFloat = 0
    private var didLayoutAllItems = false
    private var layoutMetrics: LayoutMetrics?
    private let maximumLayoutWidth: CGFloat = 100_000
    private let maximumLayoutExtent: CGFloat = 100_000_000

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }

        guard collectionView.numberOfSections > 0 else {
            resetLayoutState()
            return
        }

        guard collectionView.bounds.isFiniteForWaterfallLayout else {
            resetLayoutState()
            return
        }
        let boundsWidth = collectionView.bounds.width
        let newItemCount = collectionView.numberOfItems(inSection: 0)

        let inset = safeSectionInset()
        let availableWidth = max(0, boundsWidth - inset.left - inset.right)
        let columns = columnCount(for: availableWidth)
        let safeColumnSpacing = columnSpacing.isFinite && columnSpacing >= 0 ? columnSpacing : 8
        let safeRowSpacing = rowSpacing.isFinite && rowSpacing >= 0 ? rowSpacing : 10
        let columnWidth = max(60, (availableWidth - safeColumnSpacing * CGFloat(columns - 1)) / CGFloat(columns))
        guard columnWidth.isFinite,
              safeColumnSpacing.isFinite,
              safeRowSpacing.isFinite,
              columns > 0 else {
            resetLayoutState()
            return
        }

        let metrics = LayoutMetrics(
            itemCount: newItemCount,
            boundsWidth: boundsWidth,
            columns: columns,
            columnWidth: columnWidth,
            columnSpacing: safeColumnSpacing,
            rowSpacing: safeRowSpacing,
            sectionInset: inset,
            minAspectRatio: minAspectRatio,
            maxAspectRatio: maxAspectRatio
        )
        guard layoutMetrics != metrics else { return }

        if let oldMetrics = layoutMetrics,
           oldMetrics.itemCount == metrics.itemCount,
           oldMetrics.columns == metrics.columns,
           !cache.isEmpty {
            updateCachedFrames(metrics: metrics, oldMetrics: oldMetrics)
            return
        }

        layoutMetrics = metrics
        itemCount = newItemCount
        cache.removeAll(keepingCapacity: true)
        columnHeights = [CGFloat](repeating: inset.top, count: columns)
        nextItemIndex = 0
        didLayoutAllItems = itemCount == 0
        contentHeight = inset.top + inset.bottom
        estimatedContentHeight = estimateContentHeight(metrics: metrics)
    }

    private func updateCachedFrames(metrics: LayoutMetrics, oldMetrics: LayoutMetrics) {
        var heights = [CGFloat](repeating: metrics.sectionInset.top, count: metrics.columns)
        // Sort cached items by indexPath order so they flow left-to-right, top-to-bottom
        // using the standard shortest-column-first waterfall algorithm, regardless of
        // column count changes. This avoids stacking/overlapping that would occur when
        // trying to preserve old column assignments after a column count decrease.
        let sortedCache = cache.sorted { a, b in
            guard let ia = a.indexPath, let ib = b.indexPath else { return false }
            return ia < ib
        }
        for attrs in sortedCache {
            guard let indexPath = attrs.indexPath else { continue }
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let ratio = clampedAspectRatio(for: indexPath)
            let height = metrics.columnWidth / ratio
            let x = metrics.sectionInset.left + CGFloat(column) * (metrics.columnWidth + metrics.columnSpacing)
            let y = heights[column]
            guard x.isFinite, y.isFinite, height.isFinite, height > 0, y < maximumLayoutExtent else { continue }
            attrs.frame = CGRect(x: x, y: y, width: metrics.columnWidth, height: height)
            heights[column] += height + metrics.rowSpacing
        }
        layoutMetrics = metrics
        didLayoutAllItems = true
        contentHeight = max(
            (heights.max() ?? metrics.sectionInset.top) + metrics.sectionInset.bottom - metrics.rowSpacing,
            metrics.sectionInset.top + metrics.sectionInset.bottom
        )
    }

    override var collectionViewContentSize: NSSize {
        guard let collectionView else { return .zero }
        let width = collectionView.bounds.width
        guard width.isFinite, width > 0, width < maximumLayoutWidth else { return .zero }
        let height = didLayoutAllItems ? contentHeight : max(contentHeight, estimatedContentHeight)
        guard height.isFinite, height >= 0, height < maximumLayoutExtent else { return .zero }
        return NSSize(width: width, height: height)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard rect.isFiniteForWaterfallLayout else { return [] }
        generateLayoutIfNeeded(throughY: rect.maxY)
        return cache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < itemCount else { return nil }
        generateLayoutIfNeeded(throughItem: indexPath.item)
        return cache.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        guard let collectionView else { return false }
        guard collectionView.bounds.isFiniteForWaterfallLayout, newBounds.isFiniteForWaterfallLayout else { return true }
        return abs(collectionView.bounds.width - newBounds.width) > 0.5
    }

    private func columnCount(for width: CGFloat) -> Int {
        let safePreferredWidth = preferredCardMinimumWidth.isFinite && preferredCardMinimumWidth > 0
            ? preferredCardMinimumWidth
            : 136
        let safeSpacing = columnSpacing.isFinite && columnSpacing >= 0 ? columnSpacing : 8
        let safeWidth = max(width.isFinite ? width : safePreferredWidth, safePreferredWidth)
        let estimated = Int((safeWidth + safeSpacing) / (safePreferredWidth + safeSpacing))
        let minimum = max(minimumColumnCount ?? 1, 1)
        let maximum = max(maximumColumnCount ?? Int.max, minimum)
        let limited = min(max(estimated, minimum), maximum)
        return max(limited, 1)
    }

    private func clampedAspectRatio(for indexPath: IndexPath) -> CGFloat {
        let ratio = aspectRatioProvider?(indexPath) ?? (16.0 / 9.0)
        let safeRatio = ratio.isFinite && ratio > 0 ? ratio : (16.0 / 9.0)
        let lowerBound = minAspectRatio.isFinite && minAspectRatio > 0 ? minAspectRatio : 0.25
        let upperBound = maxAspectRatio.isFinite && maxAspectRatio >= lowerBound ? maxAspectRatio : 3.0
        return max(lowerBound, min(upperBound, safeRatio))
    }

    private func generateLayoutIfNeeded(throughY targetY: CGFloat) {
        guard let metrics = layoutMetrics, !didLayoutAllItems else { return }
        let safeTargetY = min(max(targetY, 0), maximumLayoutExtent)
        while nextItemIndex < itemCount {
            appendNextItem(metrics: metrics)
            if (columnHeights.min() ?? 0) > safeTargetY {
                break
            }
        }
        updateContentHeight(metrics: metrics)
    }

    private func generateLayoutIfNeeded(throughItem targetItem: Int) {
        guard let metrics = layoutMetrics, !didLayoutAllItems else { return }
        while nextItemIndex <= targetItem && nextItemIndex < itemCount {
            appendNextItem(metrics: metrics)
        }
        updateContentHeight(metrics: metrics)
    }

    private func appendNextItem(metrics: LayoutMetrics) {
        let indexPath = IndexPath(item: nextItemIndex, section: 0)
        nextItemIndex += 1

        let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
        let ratio = clampedAspectRatio(for: indexPath)
        let height = metrics.columnWidth / ratio
        let x = metrics.sectionInset.left + CGFloat(column) * (metrics.columnWidth + metrics.columnSpacing)
        let y = columnHeights[column]
        guard x.isFinite,
              y.isFinite,
              height.isFinite,
              height > 0,
              y < maximumLayoutExtent else {
            return
        }

        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = CGRect(
            x: x,
            y: y,
            width: metrics.columnWidth,
            height: height
        )
        cache.append(attributes)
        columnHeights[column] += height + metrics.rowSpacing
        didLayoutAllItems = nextItemIndex >= itemCount
    }

    private func updateContentHeight(metrics: LayoutMetrics) {
        let resolvedHeight = max(
            (columnHeights.max() ?? metrics.sectionInset.top) + metrics.sectionInset.bottom - metrics.rowSpacing,
            metrics.sectionInset.top + metrics.sectionInset.bottom
        )
        contentHeight = resolvedHeight.isFinite && resolvedHeight >= 0 && resolvedHeight < maximumLayoutExtent
            ? resolvedHeight
            : 0
    }

    private func estimateContentHeight(metrics: LayoutMetrics) -> CGFloat {
        guard metrics.itemCount > 0 else {
            return metrics.sectionInset.top + metrics.sectionInset.bottom
        }
        let rows = ceil(CGFloat(metrics.itemCount) / CGFloat(metrics.columns))
        let sampleCount = min(metrics.itemCount, 80)
        let averageRatio = averageAspectRatio(sampleCount: sampleCount)
        let averageHeight = metrics.columnWidth / averageRatio
        let estimated = metrics.sectionInset.top
            + metrics.sectionInset.bottom
            + rows * averageHeight
            + max(0, rows - 1) * metrics.rowSpacing
        guard estimated.isFinite, estimated >= 0, estimated < maximumLayoutExtent else { return 0 }
        return estimated
    }

    private func averageAspectRatio(sampleCount: Int) -> CGFloat {
        guard sampleCount > 0 else { return 16.0 / 9.0 }
        var total: CGFloat = 0
        for item in 0 ..< sampleCount {
            total += clampedAspectRatio(for: IndexPath(item: item, section: 0))
        }
        return max(total / CGFloat(sampleCount), 0.1)
    }

    private func resetLayoutState() {
        layoutMetrics = nil
        cache.removeAll(keepingCapacity: true)
        columnHeights = []
        nextItemIndex = 0
        itemCount = 0
        contentHeight = 0
        estimatedContentHeight = 0
        didLayoutAllItems = true
    }

    private func invalidateIfChanged(_ oldValue: CGFloat, _ newValue: CGFloat) {
        if oldValue.isFinite != newValue.isFinite || abs(oldValue - newValue) > 0.001 {
            invalidateLayout()
        }
    }

    private func safeSectionInset() -> NSEdgeInsets {
        NSEdgeInsets(
            top: sectionInset.top.isFinite && sectionInset.top >= 0 ? sectionInset.top : 0,
            left: sectionInset.left.isFinite && sectionInset.left >= 0 ? sectionInset.left : 0,
            bottom: sectionInset.bottom.isFinite && sectionInset.bottom >= 0 ? sectionInset.bottom : 0,
            right: sectionInset.right.isFinite && sectionInset.right >= 0 ? sectionInset.right : 0
        )
    }
}

private extension NSRect {
    var isFiniteForWaterfallLayout: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height >= 0
            && size.width < 100_000
            && size.height < 100_000
    }
}

private struct LayoutMetrics: Equatable {
    let itemCount: Int
    let boundsWidth: CGFloat
    let columns: Int
    let columnWidth: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let sectionInset: NSEdgeInsets
    let minAspectRatio: CGFloat
    let maxAspectRatio: CGFloat
}

private func == (lhs: LayoutMetrics, rhs: LayoutMetrics) -> Bool {
    lhs.itemCount == rhs.itemCount
        && lhs.columns == rhs.columns
        && lhs.boundsWidth.isApproximatelyEqual(to: rhs.boundsWidth)
        && lhs.columnWidth.isApproximatelyEqual(to: rhs.columnWidth)
        && lhs.columnSpacing.isApproximatelyEqual(to: rhs.columnSpacing)
        && lhs.rowSpacing.isApproximatelyEqual(to: rhs.rowSpacing)
        && lhs.sectionInset.isApproximatelyEqual(to: rhs.sectionInset)
        && lhs.minAspectRatio.isApproximatelyEqual(to: rhs.minAspectRatio)
        && lhs.maxAspectRatio.isApproximatelyEqual(to: rhs.maxAspectRatio)
}

private extension CGFloat {
    func isApproximatelyEqual(to other: CGFloat) -> Bool {
        abs(self - other) < 0.001
    }
}

private extension NSEdgeInsets {
    func isApproximatelyEqual(to other: NSEdgeInsets) -> Bool {
        top.isApproximatelyEqual(to: other.top)
            && left.isApproximatelyEqual(to: other.left)
            && bottom.isApproximatelyEqual(to: other.bottom)
            && right.isApproximatelyEqual(to: other.right)
    }
}
