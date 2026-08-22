import AppKit
import Nuke

private enum WorkspaceThumbnailPrefetchConstants {
    static let initialLimit = 12
    static let leadingCount = 6
    static let trailingCount = 12
    static let visibleWindowLimit = 18
    static let scheduleDelay: TimeInterval = 0.05
}

@MainActor
final class WorkspaceThumbnailPrefetchController<ID: Hashable> {
    nonisolated(unsafe) private var workItem: DispatchWorkItem?
    private var lastPrefetchIDs = Set<ID>()
    private var lastFirstVisibleIndex: Int?

    deinit {
        workItem?.cancel()
    }

    func reset() {
        workItem?.cancel()
        workItem = nil
        lastPrefetchIDs.removeAll()
        lastFirstVisibleIndex = nil
    }

    func prefetchInitial(
        itemCount: Int,
        itemID: (Int) -> ID?,
        request: (Int) -> ImageRequest?
    ) {
        guard itemCount > 0 else { return }
        prefetch(
            indexes: Array(0..<min(itemCount, WorkspaceThumbnailPrefetchConstants.initialLimit)),
            itemID: itemID,
            request: request
        )
    }

    func schedule(
        scrollView: NSScrollView,
        layout: NSCollectionViewLayout,
        itemCount: Int,
        itemID: @escaping (Int) -> ID?,
        request: @escaping (Int) -> ImageRequest?
    ) {
        guard workItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self, weak scrollView, weak layout] in
            guard let self else { return }
            self.workItem = nil
            guard let scrollView, let layout else { return }
            self.prefetchVisibleWindow(
                scrollView: scrollView,
                layout: layout,
                itemCount: itemCount,
                itemID: itemID,
                request: request
            )
        }
        self.workItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + WorkspaceThumbnailPrefetchConstants.scheduleDelay, execute: workItem)
    }

    private func prefetchVisibleWindow(
        scrollView: NSScrollView,
        layout: NSCollectionViewLayout,
        itemCount: Int,
        itemID: (Int) -> ID?,
        request: (Int) -> ImageRequest?
    ) {
        guard itemCount > 0 else { return }
        let visibleRect = scrollView.contentView.bounds
        guard visibleRect.isFiniteForThumbnailPrefetch, visibleRect.height > 1 else { return }

        let visibleIndexes = layout.layoutAttributesForElements(in: visibleRect)
            .compactMap(\.indexPath?.item)
            .filter { $0 >= 0 && $0 < itemCount }
        guard let first = visibleIndexes.min(), let last = visibleIndexes.max() else { return }

        let previousFirst = lastFirstVisibleIndex
        lastFirstVisibleIndex = first
        let isScrollingUp = previousFirst.map { first < $0 } ?? false

        let leadingStart = max(0, first - WorkspaceThumbnailPrefetchConstants.leadingCount)
        let leading = first > leadingStart ? Array(Array(leadingStart..<first).reversed()) : []
        let trailingEnd = min(itemCount, last + 1 + WorkspaceThumbnailPrefetchConstants.trailingCount)
        let trailing = last + 1 < trailingEnd ? Array((last + 1)..<trailingEnd) : []
        let visible = Array(first...last)
        let indexes = isScrollingUp
            ? leading + trailing + visible
            : trailing + leading + visible

        prefetch(
            indexes: indexes,
            itemID: itemID,
            request: request
        )
    }

    private func prefetch(
        indexes: [Int],
        itemID: (Int) -> ID?,
        request: (Int) -> ImageRequest?
    ) {
        let candidates = indexes.compactMap { index -> (id: ID, index: Int)? in
            guard let id = itemID(index) else { return nil }
            return (id, index)
        }
        let limited = Array(candidates.prefix(WorkspaceThumbnailPrefetchConstants.visibleWindowLimit))
        let nextIDs = Set(limited.map(\.id))
        let delta = limited.filter { !lastPrefetchIDs.contains($0.id) }
        lastPrefetchIDs = nextIDs

        let requests = delta.compactMap { request($0.index) }
        RemoteImagePipeline.shared.prefetchThumbnailImages(with: requests)
    }
}

private extension NSRect {
    var isFiniteForThumbnailPrefetch: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
            && size.width >= 0
            && size.height >= 0
            && size.width < 100_000
            && size.height < 100_000
    }
}
