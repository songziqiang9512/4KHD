import AppKit

final class LocalImageGridContainerView: NSView {
    struct Entry {
        let originalIndex: Int
        let image: LocalImageItem
        let metadata: LocalImageMetadata?
    }

    var onSelect: ((Int) -> Void)?
    var onQuickLook: ((LocalImageItem) -> Void)?
    var onShowInfo: ((LocalImageItem) -> Void)?

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
            return self.aspectRatio(for: self.entries[indexPath.item].metadata)
        }
        return layout
    }()

    lazy var collectionView: LocalImageGridCollectionView = {
        let collectionView = LocalImageGridCollectionView()
        collectionView.collectionViewLayout = waterfallLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
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
    private var lastLayoutWidth: CGFloat = 0
    private var scrollObserver: NSObjectProtocol?
    private var prefetchWorkItem: DispatchWorkItem?

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
        guard abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        collectionView.collectionViewLayout?.invalidateLayout()
        schedulePrefetch()
    }

    func focus() {
        window?.makeFirstResponderUnlessDescendantIsFirstResponder(collectionView)
    }

    func update(
        items: [(originalIndex: Int, image: LocalImageItem)],
        metadataByImageID: [LocalImageItem.ID: LocalImageMetadata],
        selectedImageID: LocalImageItem.ID?,
        preferredColumnCount: Int?,
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
        let columnPreferenceChanged = waterfallLayout.preferredColumnCount != preferredColumnCount
        let cardWidthPreferenceChanged = waterfallLayout.preferredCardMinimumWidth != preferredCardMinimumWidth
        entries = newEntries
        self.selectedImageID = selectedImageID
        waterfallLayout.preferredColumnCount = preferredColumnCount
        waterfallLayout.preferredCardMinimumWidth = preferredCardMinimumWidth

        if ids != lastAppliedIDs {
            lastAppliedIDs = ids
            collectionView.reloadData()
            collectionView.collectionViewLayout?.invalidateLayout()
            schedulePrefetch()
        } else if metadataChanged {
            collectionView.reloadItems(at: Set(collectionView.indexPathsForVisibleItems()))
            collectionView.collectionViewLayout?.invalidateLayout()
            schedulePrefetch()
        } else if columnPreferenceChanged || cardWidthPreferenceChanged {
            collectionView.collectionViewLayout?.invalidateLayout()
            schedulePrefetch()
        }

        syncSelection()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.documentView = collectionView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.collectionView.clearVisibleHoverState()
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
            if oldEntry.metadata?.fileExists != newEntry.metadata?.fileExists { return true }
        }
        return false
    }

    private func aspectRatio(for metadata: LocalImageMetadata?) -> CGFloat {
        guard let width = metadata?.pixelWidth,
              let height = metadata?.pixelHeight,
              width > 0,
              height > 0 else {
            return 16.0 / 9.0
        }
        return CGFloat(width) / CGFloat(height)
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
        guard !visible.contains(frame) else { return }
        let y = frame.minY < visible.minY ? max(0, frame.minY - 4) : frame.maxY - visible.height + 4
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
