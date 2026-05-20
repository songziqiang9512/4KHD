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
    private var contentHeight: CGFloat = 0
    private let maximumLayoutWidth: CGFloat = 100_000

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        cache.removeAll(keepingCapacity: true)

        guard collectionView.numberOfSections > 0 else {
            contentHeight = 0
            return
        }

        guard collectionView.bounds.isFiniteForWaterfallLayout else {
            contentHeight = 0
            return
        }
        let boundsWidth = collectionView.bounds.width

        let inset = safeSectionInset()
        let availableWidth = max(0, boundsWidth - inset.left - inset.right)
        let columns = columnCount(for: availableWidth)
        let estimatedWidth = max(60, (availableWidth - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns))
        let hoverGap = estimatedWidth * (WorkspaceThumbnailGridCardAnimation.cardHoverScale - 1)
        let effectiveColumnSpacing = max(columnSpacing, hoverGap)
        let effectiveRowSpacing = max(rowSpacing, hoverGap)
        let columnWidth = max(60, (availableWidth - effectiveColumnSpacing * CGFloat(columns - 1)) / CGFloat(columns))
        guard columnWidth.isFinite,
              effectiveColumnSpacing.isFinite,
              effectiveRowSpacing.isFinite,
              columns > 0 else {
            contentHeight = 0
            return
        }
        var columnHeights = [CGFloat](repeating: inset.top, count: columns)

        for item in 0 ..< collectionView.numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: item, section: 0)
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            let ratio = clampedAspectRatio(for: indexPath)
            let height = columnWidth / ratio
            let x = inset.left + CGFloat(column) * (columnWidth + effectiveColumnSpacing)
            let y = columnHeights[column]
            guard x.isFinite,
                  y.isFinite,
                  height.isFinite,
                  height > 0,
                  y < maximumLayoutWidth else {
                continue
            }
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = CGRect(
                x: x,
                y: y,
                width: columnWidth,
                height: height
            )
            cache.append(attributes)
            columnHeights[column] += height + effectiveRowSpacing
        }

        let resolvedHeight = max(
            (columnHeights.max() ?? inset.top) + inset.bottom - effectiveRowSpacing,
            inset.top + inset.bottom
        )
        contentHeight = resolvedHeight.isFinite && resolvedHeight >= 0 && resolvedHeight < maximumLayoutWidth
            ? resolvedHeight
            : 0
    }

    override var collectionViewContentSize: NSSize {
        guard let collectionView else { return .zero }
        let width = collectionView.bounds.width
        guard width.isFinite, width > 0, width < maximumLayoutWidth, contentHeight.isFinite else { return .zero }
        return NSSize(width: width, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard rect.isFiniteForWaterfallLayout else { return [] }
        return cache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        cache.first { $0.indexPath == indexPath }
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
