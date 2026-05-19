import AppKit

class WorkspaceThumbnailWaterfallLayout: NSCollectionViewLayout {
    var columnSpacing: CGFloat = 8 { didSet { invalidateIfChanged(oldValue, columnSpacing) } }
    var rowSpacing: CGFloat = 10 { didSet { invalidateIfChanged(oldValue, rowSpacing) } }
    var sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12) {
        didSet { invalidateLayout() }
    }
    var minAspectRatio: CGFloat = 0.25 { didSet { invalidateIfChanged(oldValue, minAspectRatio) } }
    var maxAspectRatio: CGFloat = 3.0 { didSet { invalidateIfChanged(oldValue, maxAspectRatio) } }
    var preferredColumnCount: Int? { didSet { if oldValue != preferredColumnCount { invalidateLayout() } } }
    var preferredCardMinimumWidth: CGFloat = 136 {
        didSet { invalidateIfChanged(oldValue, preferredCardMinimumWidth) }
    }
    var aspectRatioProvider: ((IndexPath) -> CGFloat)?

    private var cache: [NSCollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        cache.removeAll(keepingCapacity: true)

        guard collectionView.numberOfSections > 0 else {
            contentHeight = 0
            return
        }

        let availableWidth = max(0, collectionView.bounds.width - sectionInset.left - sectionInset.right)
        let columns = columnCount(for: availableWidth)
        let estimatedWidth = max(60, (availableWidth - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns))
        let hoverGap = estimatedWidth * (WorkspaceThumbnailGridCardAnimation.cardHoverScale - 1)
        let effectiveColumnSpacing = max(columnSpacing, hoverGap)
        let effectiveRowSpacing = max(rowSpacing, hoverGap)
        let columnWidth = max(60, (availableWidth - effectiveColumnSpacing * CGFloat(columns - 1)) / CGFloat(columns))
        var columnHeights = [CGFloat](repeating: sectionInset.top, count: columns)

        for item in 0 ..< collectionView.numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: item, section: 0)
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            let ratio = clampedAspectRatio(for: indexPath)
            let height = columnWidth / ratio
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = CGRect(
                x: sectionInset.left + CGFloat(column) * (columnWidth + effectiveColumnSpacing),
                y: columnHeights[column],
                width: columnWidth,
                height: height
            )
            cache.append(attributes)
            columnHeights[column] += height + effectiveRowSpacing
        }

        contentHeight = max(
            (columnHeights.max() ?? sectionInset.top) + sectionInset.bottom - effectiveRowSpacing,
            sectionInset.top + sectionInset.bottom
        )
    }

    override var collectionViewContentSize: NSSize {
        guard let collectionView else { return .zero }
        return NSSize(width: collectionView.bounds.width, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        cache.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        guard let collectionView else { return false }
        return abs(collectionView.bounds.width - newBounds.width) > 0.5
    }

    private func columnCount(for width: CGFloat) -> Int {
        let safeWidth = max(width, preferredCardMinimumWidth)
        let estimated = Int((safeWidth + columnSpacing) / (preferredCardMinimumWidth + columnSpacing))
        return max(estimated, preferredColumnCount ?? 1, 1)
    }

    private func clampedAspectRatio(for indexPath: IndexPath) -> CGFloat {
        let ratio = aspectRatioProvider?(indexPath) ?? (16.0 / 9.0)
        return max(minAspectRatio, min(maxAspectRatio, ratio))
    }

    private func invalidateIfChanged(_ oldValue: CGFloat, _ newValue: CGFloat) {
        if abs(oldValue - newValue) > 0.001 {
            invalidateLayout()
        }
    }
}
