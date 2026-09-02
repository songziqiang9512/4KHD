import AppKit

class WorkspaceThumbnailWaterfallLayout: NSCollectionViewLayout {
    var columnSpacing: CGFloat = 8 { didSet { invalidateIfChanged(oldValue, columnSpacing) } }
    var rowSpacing: CGFloat = 10 { didSet { invalidateIfChanged(oldValue, rowSpacing) } }
    var sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12) {
        didSet { invalidateLayout() }
    }
    var minAspectRatio: CGFloat = 0.25 { didSet { invalidateIfChanged(oldValue, minAspectRatio) } }
    var maxAspectRatio: CGFloat = 3.0 { didSet { invalidateIfChanged(oldValue, maxAspectRatio) } }
    /// 最后一个 item 是否按 footer(横跨整行、固定高度)布局。
    /// 带 loading footer 的网格(Gallery/MissKon)为 true;无 footer 的网格(收藏)为 false。
    var treatsLastItemAsFooter: Bool = true {
        didSet {
            guard oldValue != treatsLastItemAsFooter else { return }
            cacheInvalidatedByRatioChange = true
            invalidateLayout()
        }
    }
    var minimumColumnCount: Int? { didSet { if oldValue != minimumColumnCount { invalidateLayout() } } }
    var maximumColumnCount: Int? { didSet { if oldValue != maximumColumnCount { invalidateLayout() } } }
    var preferredCardMinimumWidth: CGFloat = 136 {
        didSet { invalidateIfChanged(oldValue, preferredCardMinimumWidth) }
    }
    var aspectRatioProvider: ((IndexPath) -> CGFloat)?
    /// 最近一次 prepare 得到的卡片列宽；宿主用它计算缩略图解码尺寸。
    private(set) var resolvedColumnWidth: CGFloat = 0

    /// 卡片宽高比更新后由宿主调用：强制按新比例重排已生成的卡片。
    /// `invalidateLayout()` 不够——`prepare()` 在 LayoutMetrics 未变时会直接返回。
    func invalidateCachedFrames() {
        cacheInvalidatedByRatioChange = true
        invalidateLayout()
    }

    /// 内容整体替换（reloadData 前）时由宿主调用：强制下次 prepare 全量重建。
    /// 内容替换若新 itemCount ≥ 旧 itemCount，append-only 增量路径会把新内容
    /// 套进旧卡片的 frame（同数量时 prepare 甚至会直接返回复用旧缓存），
    /// 必须在 prepare 消费标记后走全量生成。
    func invalidateLayoutForContentReplacement() {
        invalidatedExternally = true
        invalidateLayout()
    }

    private var cache: [NSCollectionViewLayoutAttributes] = []
    /// cache 按 frame.minY 排序的副本，滚动热路径复用；cache 内容或 frame 变化时失效。
    private var cacheSortedByMinY: [NSCollectionViewLayoutAttributes]?
    private var columnHeights: [CGFloat] = []
    private var nextItemIndex = 0
    private var itemCount = 0
    private var contentHeight: CGFloat = 0
    private var estimatedContentHeight: CGFloat = 0
    private var didLayoutAllItems = false
    private var cacheInvalidatedByRatioChange = false
    /// 宿主在 reloadData 前显式置位：下次 prepare 丢弃增量路径，全量重建。
    private var invalidatedExternally = false
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
        // 内容替换标记：丢弃旧 metrics，强制走全量重建
        // （append-only 增量与 updateCachedFrames 都会因 oldMetrics 缺失而跳过）。
        if invalidatedExternally {
            invalidatedExternally = false
            layoutMetrics = nil
        }

        // 宽高比更新时 LayoutMetrics 可能完全不变，但仍需按新比例重排已生成卡片。
        if cacheInvalidatedByRatioChange {
            cacheInvalidatedByRatioChange = false
            if let oldMetrics = layoutMetrics,
               oldMetrics.itemCount == metrics.itemCount,
               oldMetrics.columns == metrics.columns,
               !cache.isEmpty {
                updateCachedFrames(metrics: metrics, oldMetrics: oldMetrics)
                return
            }
        }

        // 加载更多(append-only)场景：几何参数未变、仅 itemCount 增加时保留已生成部分，
        // 从断点继续生成，避免每次触底加载都全量清空重排。
        // footer 网格（treatsLastItemAsFooter）不参与：旧 footer 的 34px 通栏 frame
        // 在 itemCount 增长后应重新按普通卡片布局，增量追加会把它残留为细条带。
        if !cacheInvalidatedByRatioChange,
           !treatsLastItemAsFooter,
           let oldMetrics = layoutMetrics,
           metrics.itemCount > oldMetrics.itemCount,
           isAppendOnlyUpdate(metrics, from: oldMetrics) {
            layoutMetrics = metrics
            itemCount = newItemCount
            estimatedContentHeight = estimateContentHeight(metrics: metrics)
            didLayoutAllItems = false
            updateContentHeight(metrics: metrics)
            return
        }

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
        cacheSortedByMinY = nil
        columnHeights = [CGFloat](repeating: inset.top, count: columns)
        nextItemIndex = 0
        didLayoutAllItems = itemCount == 0
        contentHeight = inset.top + inset.bottom
        estimatedContentHeight = estimateContentHeight(metrics: metrics)
        resolvedColumnWidth = metrics.columnWidth
    }

    private func updateCachedFrames(metrics: LayoutMetrics, oldMetrics: LayoutMetrics) {
        // 全量重排会改动 frame，排序副本必须失效。
        cacheSortedByMinY = nil
        var heights = [CGFloat](repeating: metrics.sectionInset.top, count: metrics.columns)
        let isFooterAtIndex = { (indexPath: IndexPath?) -> Bool in
            guard let indexPath else { return false }
            return self.treatsLastItemAsFooter && self.itemCount > 0 && indexPath.item == self.itemCount - 1
        }
        // cache 按 item 序追加，天然有序，无需再排序。
        for attrs in cache {
            guard let indexPath = attrs.indexPath else { continue }
            if isFooterAtIndex(indexPath) {
                let availableWidth = CGFloat(metrics.columns) * metrics.columnWidth
                    + CGFloat(metrics.columns - 1) * metrics.columnSpacing
                let maxY = heights.max() ?? metrics.sectionInset.top
                let x = metrics.sectionInset.left
                let y = maxY + metrics.rowSpacing
                let height: CGFloat = 34
                attrs.frame = CGRect(x: x, y: y, width: availableWidth, height: height)
                for i in heights.indices { heights[i] = y + height + metrics.rowSpacing }
            } else {
                let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
                let ratio = clampedAspectRatio(for: indexPath)
                let height = metrics.columnWidth / ratio
                let x = metrics.sectionInset.left + CGFloat(column) * (metrics.columnWidth + metrics.columnSpacing)
                let y = heights[column]
                guard x.isFinite, y.isFinite, height.isFinite, height > 0, y < maximumLayoutExtent else { continue }
                attrs.frame = CGRect(x: x, y: y, width: metrics.columnWidth, height: height)
                heights[column] += height + metrics.rowSpacing
            }
        }
        layoutMetrics = metrics
        // 同步列高：还有未生成的卡片时，后续 appendNextItem 必须基于重排后的列高继续。
        columnHeights = heights
        didLayoutAllItems = nextItemIndex >= itemCount
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
        guard !cache.isEmpty else { return [] }
        // 按 minY 排序后线性扫描，minY 超过 rect 上界即可提前停止，
        // 避免滚动热路径每帧对全量 cache 做 filter。
        let sorted = sortedCacheByMinY()
        var result: [NSCollectionViewLayoutAttributes] = []
        result.reserveCapacity(16)
        for attributes in sorted {
            let minY = attributes.frame.minY
            guard minY <= rect.maxY else { break }
            if attributes.frame.intersects(rect) {
                result.append(attributes)
            }
        }
        return result
    }

    /// cache 的 minY 排序副本，缓存到 cache 内容或 frame 变化为止。
    private func sortedCacheByMinY() -> [NSCollectionViewLayoutAttributes] {
        if let cacheSortedByMinY { return cacheSortedByMinY }
        let sorted = cache.sorted { $0.frame.minY < $1.frame.minY }
        cacheSortedByMinY = sorted
        return sorted
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < itemCount else { return nil }
        generateLayoutIfNeeded(throughItem: indexPath.item)
        // cache 按 item 序追加，下标即定位；仅在异常跳项时回退线性查找。
        if indexPath.item < cache.count, cache[indexPath.item].indexPath == indexPath {
            return cache[indexPath.item]
        }
        return cache.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        guard let collectionView else { return false }
        guard collectionView.bounds.isFiniteForWaterfallLayout, newBounds.isFiniteForWaterfallLayout else {
            return true
        }
        let widthChanged = abs(collectionView.bounds.width - newBounds.width) > 0.5
        return widthChanged
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
        let isFooter = treatsLastItemAsFooter && itemCount > 0 && nextItemIndex == itemCount - 1
        nextItemIndex += 1

        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat

        if isFooter {
            // Footer spans full content width, centered across all columns.
            let availableWidth = CGFloat(metrics.columns) * metrics.columnWidth
                + CGFloat(metrics.columns - 1) * metrics.columnSpacing
            let maxY = columnHeights.max() ?? metrics.sectionInset.top
            x = metrics.sectionInset.left
            y = maxY + metrics.rowSpacing
            width = availableWidth
            height = 34 // Standard footer height.
            // Align all columns to footer bottom.
            for i in columnHeights.indices {
                columnHeights[i] = y + height + metrics.rowSpacing
            }
        } else {
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            let ratio = clampedAspectRatio(for: indexPath)
            width = metrics.columnWidth
            height = metrics.columnWidth / ratio
            x = metrics.sectionInset.left + CGFloat(column) * (metrics.columnWidth + metrics.columnSpacing)
            y = columnHeights[column]
            columnHeights[column] += height + metrics.rowSpacing
        }
        guard x.isFinite, y.isFinite, height.isFinite, height > 0, y < maximumLayoutExtent else { return }

        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = CGRect(x: x, y: y, width: width, height: height)
        cache.append(attributes)
        cacheSortedByMinY = nil
        didLayoutAllItems = nextItemIndex >= itemCount
    }

    /// append-only 更新判断：除 itemCount 外，其余几何参数均未变化时，
    /// 已生成卡片可以直接保留继续追加。
    private func isAppendOnlyUpdate(_ metrics: LayoutMetrics, from old: LayoutMetrics) -> Bool {
        old.columns == metrics.columns
            && old.boundsWidth.isApproximatelyEqual(to: metrics.boundsWidth)
            && old.columnWidth.isApproximatelyEqual(to: metrics.columnWidth)
            && old.columnSpacing.isApproximatelyEqual(to: metrics.columnSpacing)
            && old.rowSpacing.isApproximatelyEqual(to: metrics.rowSpacing)
            && old.sectionInset.isApproximatelyEqual(to: metrics.sectionInset)
            && old.minAspectRatio.isApproximatelyEqual(to: metrics.minAspectRatio)
            && old.maxAspectRatio.isApproximatelyEqual(to: metrics.maxAspectRatio)
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
        let sampleCount = min(metrics.itemCount, 200)
        let averageRatio = averageAspectRatio(sampleCount: sampleCount, totalCount: metrics.itemCount)
        let averageHeight = metrics.columnWidth / averageRatio
        let estimated = metrics.sectionInset.top
            + metrics.sectionInset.bottom
            + rows * averageHeight
            + max(0, rows - 1) * metrics.rowSpacing
        guard estimated.isFinite, estimated >= 0, estimated < maximumLayoutExtent else { return 0 }
        return estimated
    }

    private func averageAspectRatio(sampleCount: Int, totalCount: Int) -> CGFloat {
        guard sampleCount > 0 else { return 16.0 / 9.0 }
        let step = max(1, totalCount / sampleCount)
        var total: CGFloat = 0
        var sampled = 0
        for item in stride(from: 0, to: totalCount, by: step) {
            total += clampedAspectRatio(for: IndexPath(item: item, section: 0))
            sampled += 1
            if sampled >= sampleCount { break }
        }
        return max(total / CGFloat(sampled), 0.1)
    }

    private func resetLayoutState() {
        layoutMetrics = nil
        cache.removeAll(keepingCapacity: true)
        cacheSortedByMinY = nil
        columnHeights = []
        nextItemIndex = 0
        itemCount = 0
        contentHeight = 0
        estimatedContentHeight = 0
        didLayoutAllItems = true
        resolvedColumnWidth = 0
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
