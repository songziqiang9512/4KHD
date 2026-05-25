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
    var isApplyingSelection = false
    private var lastAppliedIDs: [LocalImageItem.ID] = []
    private var pendingIDs: [LocalImageItem.ID] = []
    private var isSnapshotScheduled = false
    private var lastLayoutWidth: CGFloat = 0
    private var scrollObserver: NSObjectProtocol?
    private var prefetchWorkItem: DispatchWorkItem?
    private let restoreScrollQueue = WorkspaceCoalescingQueue(
        name: "LocalGrid Restore Scroll",
        interval: 0.08,
        maxInterval: 0.15
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        prefetchWorkItem?.cancel()
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

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.documentView = collectionView
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
            self?.schedulePrefetch()
        }
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
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

    private func makeGridItem(
        collectionView: NSCollectionView,
        indexPath: IndexPath,
        imageID: LocalImageItem.ID
    ) -> NSCollectionViewItem {
        guard let entry = entry(for: imageID),
              let item = collectionView.makeItem(
                withIdentifier: LocalImageGridItemView.reuseID,
                for: indexPath
              ) as? LocalImageGridItemView else {
            return NSCollectionViewItem()
        }

        item.configure(
            image: entry.image,
            metadata: entry.metadata,
            fileExists: entry.metadata?.fileExists ?? true,
            isSelected: entry.image.id == selectedImageID,
            cachedThumbnail: LocalImageCache.shared.cachedImage(for: entry.image.url, maxPixelSize: 512)
        ) { completion in
            guard FileManager.default.fileExists(atPath: entry.image.url.path) else {
                completion(.missingFile)
                return
            }
            Task { @MainActor in
                let image = await LocalImageCache.shared.image(for: entry.image.url, maxPixelSize: 512)
                completion(image.map(LocalImageThumbnailLoadResult.image) ?? .unavailable)
            }
        }
        return item
    }

    private func entry(for imageID: LocalImageItem.ID) -> Entry? {
        entries.first { $0.image.id == imageID }
    }

    private func applySnapshot(ids: [LocalImageItem.ID]) {
        pendingIDs = ids
        guard !isSnapshotScheduled else { return }
        isSnapshotScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSnapshotScheduled = false
            let ids = self.pendingIDs
            guard ids != self.lastAppliedIDs else { return }
            let animate = !self.lastAppliedIDs.isEmpty
                && abs(ids.count - self.lastAppliedIDs.count)
                    <= max(20, self.collectionView.indexPathsForVisibleItems().count + 10)
            var snapshot = NSDiffableDataSourceSnapshot<Section, LocalImageItem.ID>()
            snapshot.appendSections([.main])
            snapshot.appendItems(ids, toSection: .main)
            self.dataSource.apply(snapshot, animatingDifferences: animate) { [weak self] in
                guard let self else { return }
                self.lastAppliedIDs = ids
                self.refreshLayoutAfterGeometryChange()
                self.syncSelection()
            }
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
            collectionView.needsLayout = true
            collectionView.layoutSubtreeIfNeeded()
        }
        CATransaction.commit()
    }

    private func restoreVisibleLayoutIfNeeded() {
        guard !entries.isEmpty else { return }
        forceLayoutForVisibleRegion()
        clampScrollPositionToContent()
        scrollToSelectedItemIfVisibleRegionIsEmpty()
        collectionView.needsLayout = true
        collectionView.layoutSubtreeIfNeeded()
    }

    private func forceLayoutForVisibleRegion() {
        let visible = scrollView.contentView.bounds
        guard visible.isFiniteForScrolling else { return }
        _ = waterfallLayout.layoutAttributesForElements(in: visible)
    }

    private func clampScrollPositionToContent() {
        let visible = scrollView.contentView.bounds
        guard visible.isFiniteForScrolling else { return }
        let contentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height
            ?? collectionView.bounds.height
        guard contentHeight.isFinite, contentHeight >= 0 else { return }
        let minY = -scrollView.contentInsets.top
        let maxY = max(minY, contentHeight - visible.height + scrollView.contentInsets.bottom)
        let y = min(max(minY, visible.origin.y), maxY)
        guard abs(y - visible.origin.y) > 0.5 else { return }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func scrollToSelectedItemIfVisibleRegionIsEmpty() {
        let visible = scrollView.contentView.bounds
        guard visible.isFiniteForScrolling,
              visible.height > 1,
              waterfallLayout.layoutAttributesForElements(in: visible).isEmpty,
              let indexPath = visibleRecoveryIndexPath(),
              let attributes = waterfallLayout.layoutAttributesForItem(at: indexPath) else {
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
           let selectedIndex = entries.firstIndex(where: { $0.image.id == selectedImageID }) {
            return IndexPath(item: selectedIndex, section: 0)
        }
        return entries.isEmpty ? nil : IndexPath(item: 0, section: 0)
    }

    private func syncSelection() {
        guard let selectedImageID,
              let index = entries.firstIndex(where: { $0.image.id == selectedImageID }) else {
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
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? LocalImageGridItemView,
                  indexPath.item < entries.count else { continue }
            item.applySelectionState(entries[indexPath.item].image.id == selectedImageID)
        }
    }

    func scrollItemIntoViewIfNeeded(at indexPath: IndexPath) {
        guard let attributes = waterfallLayout.layoutAttributesForItem(at: indexPath) else { return }
        let frame = attributes.frame
        let visible = scrollView.contentView.bounds
        guard frame.isFiniteForScrolling,
              visible.isFiniteForScrolling,
              collectionView.bounds.isFiniteForScrolling else {
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
        prefetchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.prefetchNearVisibleItems()
        }
        prefetchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func prefetchNearVisibleItems() {
        guard !entries.isEmpty else { return }
        let visibleRect = scrollView.contentView.bounds.insetBy(dx: 0, dy: -scrollView.contentView.bounds.height)
        let visibleIndexes = waterfallLayout
            .layoutAttributesForElements(in: visibleRect)
            .compactMap(\.indexPath?.item)
            .filter { entries.indices.contains($0) }
        guard let first = visibleIndexes.min(), let last = visibleIndexes.max() else { return }

        let lowerBound = max(0, first - 24)
        let upperBound = min(entries.count - 1, last + 48)
        for entry in entries[lowerBound ... upperBound] {
            guard entry.metadata?.fileExists ?? true else { continue }
            let url = entry.image.url
            Task(priority: .utility) {
                _ = await LocalImageCache.shared.image(for: url, maxPixelSize: 512)
            }
        }
    }
}

extension LocalImageGridContainerView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection,
              let indexPath = indexPaths.first,
              indexPath.item < entries.count else { return }
        selectItem(at: indexPath.item, scroll: false)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let item = item as? LocalImageGridItemView, indexPath.item < entries.count else { return }
        item.applySelectionState(entries[indexPath.item].image.id == selectedImageID)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        shouldDeselectItemsAt indexPaths: Set<IndexPath>
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

nonisolated private final class LocalImageGridDiffableDataSource: NSCollectionViewDiffableDataSource<
    LocalImageGridContainerView.Section,
    LocalImageItem.ID
> {
    var pasteboardWriter: ((IndexPath) -> NSPasteboardWriting?)?

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        pasteboardWriter?(indexPath)
    }
}
