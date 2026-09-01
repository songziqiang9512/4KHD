import AppKit

final class LocalImageGridContainerView: NSView {
    enum Section {
        case main
    }

    struct Entry {
        let originalIndex: Int
        let image: LocalImageItem
        let metadata: LocalImageMetadata?
    }

    var onSelect: ((Int) -> Void)?
    var onOpenDetail: (() -> Void)?
    var onQuickLook: ((LocalImageItem) -> Void)?
    var onShowInfo: ((LocalImageItem) -> Void)?
    var onRefresh: (() -> Void)?
    var searchQuery: String?

    private lazy var dataSource = LocalImageGridDiffableDataSource(collectionView: collectionView) {
        [weak self] collectionView, indexPath, imageID -> NSCollectionViewItem? in
        self?.makeGridItem(collectionView: collectionView, indexPath: indexPath, imageID: imageID)
    }

    let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.contentView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    lazy var waterfallLayout: LocalImageGridLayout = {
        let layout = LocalImageGridLayout()
        layout.aspectRatioProvider = { [weak self] indexPath in
            guard let self, indexPath.item < self.entries.count else { return 16.0 / 9.0 }
            return self.entries[indexPath.item].image.aspectRatio
        }
        return layout
    }()

    lazy var collectionView: LocalImageGridCollectionView = {
        let collectionView = LocalImageGridCollectionView()
        collectionView.collectionViewLayout = waterfallLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.delegate = self
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: true)
        collectionView.contextMenuProvider = { [weak self] indexPath in
            self?.makeContextMenu(for: indexPath)
        }
        collectionView.arrowKeyHandler = { [weak self] delta in
            self?.selectAdjacent(delta: delta) ?? false
        }
        collectionView.spaceKeyHandler = { [weak self] in
            self?.quickLookSelected() ?? false
        }
        collectionView.keyboardContext = WorkspaceKeyboardContext(
            stepSelection: collectionView.arrowKeyHandler,
            quickLook: collectionView.spaceKeyHandler
        )
        collectionView.doubleClickHandler = { [weak self] indexPath in
            self?.openDetail(at: indexPath)
        }
        collectionView.cardPressStateHandler = { [weak self] indexPath, isPressed in
            self?.updateCardPressState(at: indexPath, isPressed: isPressed)
        }
        collectionView.register(LocalImageGridItemView.self, forItemWithIdentifier: LocalImageGridItemView.reuseID)
        return collectionView
    }()

    var entries: [Entry] = []
    var selectedImageID: LocalImageItem.ID?
    private var previousSelectedImageID: LocalImageItem.ID?
    var isApplyingSelection = false
    private var lastAppliedIDs: [LocalImageItem.ID] = []
    private var lastLayoutWidth: CGFloat = 0
    private nonisolated(unsafe) var scrollObserver: NSObjectProtocol?
    private nonisolated(unsafe) var prefetchWorkItem: DispatchWorkItem?
    private var prefetchTask: Task<Void, Never>?
    private var lastPrefetchIDs = Set<LocalImageItem.ID>()
    private let restoreScrollQueue = WorkspaceCoalescingQueue(
        name: "LocalGrid Restore Scroll",
        interval: 0.08,
        maxInterval: 0.15
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        prefetchWorkItem?.cancel()
        prefetchTask?.cancel()
    }

    override func layout() {
        super.layout()
        let width = scrollView.contentView.bounds.width > 0 ? scrollView.contentView.bounds.width : bounds.width
        guard width.isFinite, width > 1, width < 100_000 else { return }
        guard abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        collectionView.collectionViewLayout?.invalidateLayout()
        schedulePrefetch()
        restoreScrollQueue.add(id: "scroll") { [weak self] in
            self?.restoreVisibleLayoutIfNeeded()
        }
    }

    func focus() {
        window?.makeFirstResponderUnlessDescendantIsFirstResponder(collectionView)
    }

    func update(
        items: [(originalIndex: Int, image: LocalImageItem)],
        metadataByImageID: [LocalImageItem.ID: LocalImageMetadata],
        selectedImageID: LocalImageItem.ID?,
        minimumColumnCount: Int?,
        maximumColumnCount: Int?,
        preferredCardMinimumWidth: CGFloat
    ) {
        let newEntries = items.map { item in
            Entry(
                originalIndex: item.originalIndex,
                image: item.image,
                metadata: metadataByImageID[item.image.id]
            )
        }
        let ids = newEntries.map(\.image.id)
        let metadataChanged = hasMetadataChanges(newEntries)
        let minimumColumnPreferenceChanged = waterfallLayout.minimumColumnCount != minimumColumnCount
        let columnPreferenceChanged = waterfallLayout.maximumColumnCount != maximumColumnCount
        let cardWidthPreferenceChanged = waterfallLayout.preferredCardMinimumWidth != preferredCardMinimumWidth
        entries = newEntries
        if ids != lastAppliedIDs {
            lastPrefetchIDs.removeAll()
            prefetchTask?.cancel()
            prefetchTask = nil
        }
        previousSelectedImageID = self.selectedImageID
        self.selectedImageID = selectedImageID
        waterfallLayout.minimumColumnCount = minimumColumnCount
        waterfallLayout.maximumColumnCount = maximumColumnCount
        waterfallLayout.preferredCardMinimumWidth = preferredCardMinimumWidth

        if ids != lastAppliedIDs {
            applySnapshot(ids: ids)
        } else if metadataChanged {
            collectionView.reloadItems(at: Set(collectionView.indexPathsForVisibleItems()))
            schedulePrefetch()
        } else if minimumColumnPreferenceChanged || columnPreferenceChanged || cardWidthPreferenceChanged {
            refreshLayoutAfterGeometryChange()
        }

        syncSelection()
    }

    func updateLayoutPreferences(
        minimumColumnCount: Int?,
        maximumColumnCount: Int?,
        preferredCardMinimumWidth: CGFloat
    ) {
        let minimumColumnPreferenceChanged = waterfallLayout.minimumColumnCount != minimumColumnCount
        let maximumColumnPreferenceChanged = waterfallLayout.maximumColumnCount != maximumColumnCount
        let cardWidthPreferenceChanged = waterfallLayout.preferredCardMinimumWidth != preferredCardMinimumWidth
        guard minimumColumnPreferenceChanged || maximumColumnPreferenceChanged || cardWidthPreferenceChanged else {
            return
        }
        waterfallLayout.minimumColumnCount = minimumColumnCount
        waterfallLayout.maximumColumnCount = maximumColumnCount
        waterfallLayout.preferredCardMinimumWidth = preferredCardMinimumWidth
        refreshLayoutAfterGeometryChange()
    }

    @objc private func handlePullToRefresh() {
        onRefresh?()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.documentView = collectionView
        WorkspacePullToRefresh.install(
            on: scrollView,
            target: self,
            action: #selector(handlePullToRefresh)
        )
        dataSource.pasteboardWriter = { [weak self] indexPath in
            guard let self, self.entries.indices.contains(indexPath.item) else { return nil }
            return self.entries[indexPath.item].image.url as NSURL
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.schedulePrefetch()
            }
        }
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func hasMetadataChanges(_ newEntries: [Entry]) -> Bool {
        guard newEntries.count == entries.count else { return true }
        for (oldEntry, newEntry) in zip(entries, newEntries) {
            guard oldEntry.image.id == newEntry.image.id else { return true }
            if oldEntry.metadata?.pixelWidth != newEntry.metadata?.pixelWidth { return true }
            if oldEntry.metadata?.pixelHeight != newEntry.metadata?.pixelHeight { return true }
            if formattedSecondaryMetadata(oldEntry.metadata) != formattedSecondaryMetadata(newEntry.metadata) { return true }
            if oldEntry.metadata?.fileExists != newEntry.metadata?.fileExists { return true }
        }
        return false
    }

    private var thumbnailMaxPixelSize: CGFloat {
        let width = waterfallLayout.resolvedColumnWidth
        guard width > 0 else { return 512 }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let requested = width * scale
        let buckets: [CGFloat] = [512, 768, 1024, 1536]
        return buckets.first { $0 >= requested } ?? 1536
    }

    private func makeGridItem(
        collectionView: NSCollectionView,
        indexPath: IndexPath,
        imageID _: LocalImageItem.ID
    ) -> NSCollectionViewItem {
        guard let entry = entries.indices.contains(indexPath.item) ? entries[indexPath.item] : nil,
              let item = collectionView.makeItem(
                  withIdentifier: LocalImageGridItemView.reuseID,
                  for: indexPath
              ) as? LocalImageGridItemView
        else {
            return NSCollectionViewItem()
        }

        let maxPixelSize = thumbnailMaxPixelSize
        item.configure(
            image: entry.image,
            metadata: entry.metadata,
            fileExists: entry.metadata?.fileExists ?? true,
            isSelected: entry.image.id == selectedImageID,
            cachedThumbnail: LocalImageCache.shared.cachedImage(
                for: entry.image.url,
                maxPixelSize: maxPixelSize,
                fileVersion: Self.fileVersion(for: entry.metadata)
            ),
            searchQuery: searchQuery
        ) { completion in
            let version = Self.fileVersion(for: entry.metadata)
            Task { @MainActor in
                let image = await LocalImageCache.shared.image(
                    for: entry.image.url,
                    maxPixelSize: maxPixelSize,
                    fileVersion: version
                )
                completion(image.map(LocalImageThumbnailLoadResult.image) ?? .unavailable)
            }
        }
        return item
    }

    private func applySnapshot(ids: [LocalImageItem.ID]) {
        guard ids != lastAppliedIDs else { return }
        let animate = !lastAppliedIDs.isEmpty
            && abs(ids.count - lastAppliedIDs.count)
            <= max(20, collectionView.indexPathsForVisibleItems().count + 10)
        let isPureAppend = ids.count >= lastAppliedIDs.count
            && Array(ids.prefix(lastAppliedIDs.count)) == lastAppliedIDs
        if !isPureAppend {
            // 内容替换：强制布局全量重建，避免 append 增量路径把新内容套进旧卡片 frame。
            waterfallLayout.invalidateLayoutForContentReplacement()
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, LocalImageItem.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(ids, toSection: .main)
        // Data source is updated immediately; the completion handler fires
        // after animations (if any) finish.
        dataSource.apply(snapshot, animatingDifferences: animate) { [weak self] in
            guard let self else { return }
            self.lastAppliedIDs = ids
            self.refreshLayoutAfterGeometryChange()
            self.syncSelection()
        }
    }

    private func refreshLayoutAfterGeometryChange() {
        invalidateCollectionLayout()
        schedulePrefetch()
        restoreScrollQueue.add(id: "scroll") { [weak self] in
            self?.restoreVisibleLayoutIfNeeded()
        }
    }

    private func invalidateCollectionLayout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            collectionView.collectionViewLayout?.invalidateLayout()
        }
        CATransaction.commit()
    }

    private func restoreVisibleLayoutIfNeeded() {
        guard !entries.isEmpty else { return }
        forceLayoutForVisibleRegion()
        clampScrollPositionToContent()
        scrollToSelectedItemIfVisibleRegionIsEmpty()
    }

    private func forceLayoutForVisibleRegion() {
        let visible = scrollView.contentView.bounds
        guard visible.isFiniteForScrolling else { return }
        _ = waterfallLayout.layoutAttributesForElements(in: visible)
    }

    private func clampScrollPositionToContent() {
        let visible = scrollView.contentView.bounds
        guard visible.isFiniteForScrolling else { return }
        let minY = -scrollView.contentInsets.top
        guard visible.origin.y < minY - 0.5 else { return }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: minY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func scrollToSelectedItemIfVisibleRegionIsEmpty() {
        let visible = scrollView.contentView.bounds
        guard visible.isFiniteForScrolling,
              visible.height > 1,
              waterfallLayout.layoutAttributesForElements(in: visible).isEmpty,
              let indexPath = visibleRecoveryIndexPath(),
              let attributes = waterfallLayout.layoutAttributesForItem(at: indexPath)
        else {
            return
        }
        let contentHeight = waterfallLayout.collectionViewContentSize.height
        let minY = -scrollView.contentInsets.top
        guard contentHeight.isFinite, contentHeight > visible.height else {
            scrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: minY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }
        let maxY = max(minY, contentHeight - visible.height + scrollView.contentInsets.bottom)
        let targetY = min(max(minY, attributes.frame.minY - 4), maxY)
        guard targetY.isFinite, abs(targetY - visible.origin.y) > 0.5 else { return }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func visibleRecoveryIndexPath() -> IndexPath? {
        if let selectedImageID,
           let selectedIndex = entries.firstIndex(where: { $0.image.id == selectedImageID })
        {
            return IndexPath(item: selectedIndex, section: 0)
        }
        return entries.isEmpty ? nil : IndexPath(item: 0, section: 0)
    }

    private func syncSelection() {
        guard let selectedImageID,
              let index = entries.firstIndex(where: { $0.image.id == selectedImageID })
        else {
            isApplyingSelection = true
            collectionView.selectionIndexPaths = []
            isApplyingSelection = false
            return
        }
        let selection = Set([IndexPath(item: index, section: 0)])
        guard collectionView.selectionIndexPaths != selection else { return }
        isApplyingSelection = true
        collectionView.selectionIndexPaths = selection
        isApplyingSelection = false
        refreshVisibleSelection()
    }

    func refreshVisibleSelection() {
        let previousID = previousSelectedImageID
        let currentID = selectedImageID
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? LocalImageGridItemView,
                  indexPath.item < entries.count else { continue }
            let entryID = entries[indexPath.item].image.id
            let wasSelected = entryID == previousID
            let isSelected = entryID == currentID
            guard wasSelected != isSelected else { continue }
            item.applySelectionState(isSelected)
        }
        previousSelectedImageID = selectedImageID
    }

    func scrollItemIntoViewIfNeeded(at indexPath: IndexPath) {
        guard let attributes = waterfallLayout.layoutAttributesForItem(at: indexPath) else { return }
        let frame = attributes.frame
        let visible = scrollView.contentView.bounds
        guard frame.isFiniteForScrolling,
              visible.isFiniteForScrolling,
              collectionView.bounds.isFiniteForScrolling
        else {
            return
        }
        guard !visible.contains(frame) else { return }
        let minY = -scrollView.contentInsets.top
        let maxY = max(minY, collectionView.bounds.height - visible.height + scrollView.contentInsets.bottom)
        let targetY = frame.minY < visible.minY ? frame.minY - 4 : frame.maxY - visible.height + 4
        let y = min(max(minY, targetY), maxY)
        guard y.isFinite, y < 100_000 else { return }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func selectAdjacent(delta: Int) -> Bool {
        guard !entries.isEmpty else { return false }
        let currentIndex = selectedImageID.flatMap { id in entries.firstIndex { $0.image.id == id } }
            ?? collectionView.selectionIndexPaths.first?.item
            ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), entries.count - 1)
        guard nextIndex != currentIndex else { return true }
        selectItem(at: nextIndex, scroll: true)
        onQuickLookSync()
        return true
    }

    func selectItem(at index: Int, scroll: Bool) {
        guard entries.indices.contains(index) else { return }
        window?.makeFirstResponder(collectionView)
        previousSelectedImageID = selectedImageID
        selectedImageID = entries[index].image.id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
        isApplyingSelection = false
        refreshVisibleSelection()
        if scroll {
            scrollItemIntoViewIfNeeded(at: IndexPath(item: index, section: 0))
        }
        onSelect?(entries[index].originalIndex)
    }

    func quickLookSelected() -> Bool {
        guard let selected = selectedEntry else { return false }
        onQuickLook?(selected.image)
        return true
    }

    private func openDetail(at indexPath: IndexPath) {
        guard entries.indices.contains(indexPath.item) else { return }
        selectItem(at: indexPath.item, scroll: false)
        onOpenDetail?()
    }

    private func onQuickLookSync() {
        guard let selected = selectedEntry else { return }
        LocalQuickLookController.shared.syncVisible(url: selected.image.url)
    }

    var selectedEntry: Entry? {
        guard let selectedImageID else { return nil }
        return entries.first { $0.image.id == selectedImageID }
    }

    func updateCardPressState(at indexPath: IndexPath, isPressed: Bool) {
        (collectionView.item(at: indexPath) as? LocalImageGridItemView)?.applyPressedState(isPressed)
    }

    private func schedulePrefetch() {
        // cancel + 重建 = 滚动防抖：滚动停止后只触发一次，避免滚动中反复预取中间窗口。
        prefetchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.prefetchWorkItem = nil
            self.prefetchNearVisibleItems()
        }
        prefetchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func prefetchNearVisibleItems() {
        guard !entries.isEmpty else { return }
        let visibleRect = scrollView.contentView.bounds
        let visibleIndexes = waterfallLayout
            .layoutAttributesForElements(in: visibleRect)
            .compactMap(\.indexPath?.item)
            .filter { entries.indices.contains($0) }
        guard let first = visibleIndexes.min(), let last = visibleIndexes.max() else { return }

        let lowerBound = max(0, first - 6)
        let upperBound = min(entries.count - 1, last + 12)
        let candidates = entries[lowerBound ... upperBound]
        let nextIDs = Set(candidates.map(\.image.id))
        let urls = candidates.compactMap { entry -> URL? in
            guard !lastPrefetchIDs.contains(entry.image.id) else { return nil }
            guard entry.metadata?.fileExists ?? true else { return nil }
            return entry.image.url
        }
        lastPrefetchIDs = nextIDs
        guard !urls.isEmpty else { return }

        prefetchTask?.cancel()
        let maxPixelSize = thumbnailMaxPixelSize
        prefetchTask = Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var iterator = urls.makeIterator()
                for _ in 0 ..< 4 {
                    guard let url = iterator.next() else { break }
                    group.addTask {
                        _ = await LocalImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
                    }
                }
                while await group.next() != nil {
                    guard !Task.isCancelled, let url = iterator.next() else { continue }
                    group.addTask {
                        _ = await LocalImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
                    }
                }
            }
        }
    }

    private static func fileVersion(for metadata: LocalImageMetadata?) -> LocalImageCache.FileVersion? {
        guard let metadata else { return nil }
        return LocalImageCache.FileVersion(
            fileSize: metadata.fileSize,
            modifiedAt: metadata.modifiedDate
        )
    }
}

extension LocalImageGridContainerView: NSCollectionViewDelegate {
    func collectionView(_: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection,
              let indexPath = indexPaths.first,
              indexPath.item < entries.count else { return }
        selectItem(at: indexPath.item, scroll: false)
    }

    func collectionView(
        _: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let item = item as? LocalImageGridItemView, indexPath.item < entries.count else { return }
        item.applySelectionState(entries[indexPath.item].image.id == selectedImageID)
    }

    func collectionView(
        _: NSCollectionView,
        shouldDeselectItemsAt _: Set<IndexPath>
    ) -> Set<IndexPath> {
        []
    }
}

private extension NSRect {
    var isFiniteForScrolling: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
            && size.width >= 0
            && size.height >= 0
    }
}

private final nonisolated class LocalImageGridDiffableDataSource: NSCollectionViewDiffableDataSource<
    LocalImageGridContainerView.Section,
    LocalImageItem.ID
> {
    var pasteboardWriter: ((IndexPath) -> NSPasteboardWriting?)?

    func collectionView(
        _: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        pasteboardWriter?(indexPath)
    }
}
