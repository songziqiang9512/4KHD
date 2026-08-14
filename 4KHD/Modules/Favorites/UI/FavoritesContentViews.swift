import AppKit
import Nuke

// MARK: - 列表行

@MainActor
final class FavoritesListRowView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("FavoritesListRowView")

    private let coverView = RemoteImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        setupView()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func configure(record: FavoriteRecord, source: FavoriteSource?, searchQuery: String? = nil) {
        coverView.configureRequest = source?.imageRequestConfigurator
        coverView.setImage(url: record.coverURL.flatMap(URL.init(string:)), maxPixelSize: 180)
        if let query = searchQuery, !query.isEmpty {
            titleLabel.attributedStringValue = highlightedAttributedString(record.title, query: query)
        } else {
            titleLabel.stringValue = record.title
        }
        let sourceTitle = source?.title ?? "未知来源"
        subtitleLabel.stringValue = record.imageCount > 0 ? "\(sourceTitle) · \(record.imageCount) 张图片" : "\(sourceTitle) · 多张图片"
    }

    private func setupView() {
        coverView.cornerRadius = 5
        coverView.mode = .aspectFill

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2

        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let root = NSStackView(views: [coverView, textStack])
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 10

        addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        coverView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coverView.widthAnchor.constraint(equalToConstant: 64),
            coverView.heightAnchor.constraint(equalToConstant: 86),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            root.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
        ])
    }
}

// MARK: - 网格卡片(复用共享缩略图卡片,与 MissKon/4KHD 一致)

@MainActor
final class FavoritesGridItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("FavoritesGridItemView")

    private let cardView = WorkspaceThumbnailGridCardView()
    private var imageTask: ImageTask?
    private var representedID: FavoriteRecord.ID?
    private var currentCoverURL: URL?
    var thumbnailMaxPixelSize: CGFloat = 512

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.addSubview(cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        representedID = nil
        currentCoverURL = nil
        cardView.resetForReuse()
    }

    func configure(
        record: FavoriteRecord,
        source: FavoriteSource?,
        isSelected: Bool,
        searchQuery: String? = nil,
        onAspectRatio: @escaping (CGFloat) -> Void
    ) {
        let coverURL = record.coverURL.flatMap(URL.init(string:))
        let idChanged = representedID != record.id
        let urlChanged = currentCoverURL != coverURL
        representedID = record.id
        cardView.setText(
            title: record.title,
            metadata: record.imageCount > 0 ? "\(record.imageCount) 张图片" : "多张图片",
            highlightQuery: searchQuery
        )
        cardView.applySelectionState(isSelected)
        if idChanged || urlChanged {
            loadCover(record: record, source: source, onAspectRatio: onAspectRatio)
        } else if let coverURL {
            let ratio = GalleryCoverAspectRatio.aspectRatio(from: coverURL)
            if let ratio {
                onAspectRatio(CGFloat(ratio))
            }
        }
    }

    func applySelectionState(_ isSelected: Bool) {
        cardView.applySelectionState(isSelected)
    }

    func syncHoverState(windowLocation: NSPoint?) {
        cardView.syncHoverState(windowLocation: windowLocation)
    }

    func clearHoverState() {
        cardView.clearHoverState()
    }

    private func loadCover(
        record: FavoriteRecord,
        source: FavoriteSource?,
        onAspectRatio: @escaping (CGFloat) -> Void
    ) {
        imageTask?.cancel()
        cardView.setImage(nil)
        let coverURL = record.coverURL.flatMap(URL.init(string:))
        currentCoverURL = coverURL
        guard let coverURL else {
            cardView.setPlaceholder("暂无缩略图", isVisible: true)
            return
        }
        let request = RemoteImagePipeline.shared.request(
            for: coverURL,
            priority: .normal,
            maxPixelSize: thumbnailMaxPixelSize,
            configureURLRequest: source?.imageRequestConfigurator ?? { _ in }
        )
        if let cached = RemoteImagePipeline.shared.cachedImage(with: request) {
            cardView.setImage(cached, animated: false)
            if cached.size.width > 0, cached.size.height > 0 {
                onAspectRatio(cached.size.width / cached.size.height)
            }
            return
        }

        cardView.setPlaceholder("加载中...", isVisible: true)
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.currentCoverURL == coverURL else { return }
                guard let image else {
                    self.cardView.setPlaceholder("加载失败", isVisible: true)
                    return
                }
                self.cardView.setImage(image)
                if image.size.width > 0, image.size.height > 0 {
                    onAspectRatio(image.size.width / image.size.height)
                }
            }
        }
    }
}

// MARK: - 网格集合视图(双击开详情)

final class FavoritesGridCollectionView: WorkspaceCollectionView {
    var arrowKeyHandler: ((Int) -> Bool)?
    var doubleClickHandler: ((IndexPath) -> Void)?

    override func accessibilityLabel() -> String? {
        "收藏 Grid"
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedIndexPath = indexPathForItem(at: point)
        super.mouseDown(with: event)
        if event.clickCount == 2, let clickedIndexPath { doubleClickHandler?(clickedIndexPath) }
    }

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        clearHoverOnVisibleItems()
        super.viewDidEndLiveResize()
    }

    override func clearHoverOnVisibleItems() {
        lastHoveredIndexPath = nil
        for item in visibleItems() {
            (item as? FavoritesGridItemView)?.clearHoverState()
        }
    }

    override func syncHoverOnVisibleItems(windowLocation: NSPoint?) {
        for item in visibleItems() {
            (item as? FavoritesGridItemView)?.syncHoverState(windowLocation: windowLocation)
        }
    }
}

// MARK: - 网格容器(瀑布流,与 MissKon 一致的间距/交互)

@MainActor
final class FavoritesGridContainerView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((FavoriteRecord) -> Void)?
    var onOpenDetail: (() -> Void)?
    var contextMenuProvider: ((FavoriteRecord) -> NSMenu?)?

    private let gridScrollView = NSScrollView()
    var scrollView: NSScrollView {
        gridScrollView
    }

    private let collectionView = FavoritesGridCollectionView()
    private let gridLayout = WorkspaceThumbnailWaterfallLayout()
    private var records: [FavoriteRecord] = []
    private var selectedRecordID: FavoriteRecord.ID?
    private var searchQuery: String?
    private var isApplyingSelection = false
    private var lastAppliedIDs: [FavoriteRecord.ID] = []
    private var lastLayoutWidth: CGFloat = 0
    private var aspectRatiosByRecordID: [FavoriteRecord.ID: CGFloat] = [:]
    private var minimumColumnCount: Int?
    private var maximumColumnCount: Int?
    private var preferredCardMinimumWidth: CGFloat = 136
    private let thumbnailPrefetchController = WorkspaceThumbnailPrefetchController<FavoriteRecord.ID>()
    private let aspectRatioLayoutQueue = WorkspaceCoalescingQueue(
        name: "FavoritesGridAspectRatio", interval: 0.03, maxInterval: 0.1
    )
    private nonisolated(unsafe) var scrollObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }

    override func layout() {
        super.layout()
        updateItemSize()
        scheduleThumbnailPrefetch()
    }

    func focus() {
        window?.makeFirstResponderUnlessDescendantIsFirstResponder(collectionView)
    }

    func firstVisibleRecordID() -> FavoriteRecord.ID? {
        collectionView.indexPathsForVisibleItems()
            .filter { records.indices.contains($0.item) }
            .min { $0.item < $1.item }
            .map { records[$0.item].id }
    }

    func scrollRecordIntoViewIfNeeded(withID recordID: FavoriteRecord.ID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        guard let attributes = gridLayout.layoutAttributesForItem(at: indexPath),
              !gridScrollView.contentView.bounds.contains(attributes.frame) else { return }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
    }

    func update(
        records: [FavoriteRecord],
        selectedRecordID: FavoriteRecord.ID?,
        searchQuery: String?,
        minimumColumnCount: Int? = nil,
        maximumColumnCount: Int? = nil,
        preferredCardMinimumWidth: CGFloat = 136
    ) {
        let previousItemIDs = lastAppliedIDs
        let previousSelectedRecordID = self.selectedRecordID
        let previousSearchQuery = self.searchQuery
        let nextItemIDs = records.map(\.id)
        let contentChanged = nextItemIDs != previousItemIDs
        self.records = records
        self.selectedRecordID = selectedRecordID
        self.searchQuery = searchQuery
        self.minimumColumnCount = minimumColumnCount
        self.maximumColumnCount = maximumColumnCount
        self.preferredCardMinimumWidth = preferredCardMinimumWidth

        let sizeChanged = updateItemSize()
        if sizeChanged || contentChanged {
            lastAppliedIDs = nextItemIDs
            if contentChanged {
                // 内容被替换:已捕获的滚动锚点对新内容无效。
                gridLayout.clearPendingScrollAnchor()
                thumbnailPrefetchController.reset()
            }
            performWithoutAnimation { collectionView.reloadData() }
            if contentChanged {
                prefetchInitialThumbnails()
            }
        } else if previousSearchQuery != searchQuery {
            refreshVisibleItems()
        } else if previousSelectedRecordID != selectedRecordID {
            refreshVisibleSelection()
        }
        syncSelection()
        scheduleThumbnailPrefetch()
    }

    func refreshMetadata(selectedRecordID: FavoriteRecord.ID?, searchQuery: String?) {
        let previousSelectedRecordID = self.selectedRecordID
        let previousSearchQuery = self.searchQuery
        self.selectedRecordID = selectedRecordID
        self.searchQuery = searchQuery
        if previousSearchQuery != searchQuery {
            refreshVisibleItems()
        } else if previousSelectedRecordID != selectedRecordID {
            refreshVisibleSelection()
        }
    }

    private func refreshVisibleItems() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard records.indices.contains(indexPath.item) else { continue }
            guard let cell = collectionView.item(at: indexPath) as? FavoritesGridItemView else { continue }
            let record = records[indexPath.item]
            cell.configure(
                record: record,
                source: FavoriteSource.source(for: record),
                isSelected: record.id == selectedRecordID,
                searchQuery: searchQuery
            ) { [weak self] ratio in
                self?.updateAspectRatio(ratio, for: record.id)
            }
        }
    }

    func numberOfSections(in _: NSCollectionView) -> Int {
        1
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        records.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: FavoritesGridItemView.reuseID, for: indexPath) as? FavoritesGridItemView ?? FavoritesGridItemView()
        item.thumbnailMaxPixelSize = thumbnailMaxPixelSize
        let record = records[indexPath.item]
        item.configure(
            record: record,
            source: FavoriteSource.source(for: record),
            isSelected: record.id == selectedRecordID,
            searchQuery: searchQuery
        ) { [weak self] ratio in
            self?.updateAspectRatio(ratio, for: record.id)
        }
        return item
    }

    func collectionView(_: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection, let indexPath = indexPaths.first, records.indices.contains(indexPath.item) else { return }
        let record = records[indexPath.item]
        selectedRecordID = record.id
        refreshVisibleSelection()
        onSelect?(record)
    }

    func collectionView(_: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard records.indices.contains(indexPath.item) else { return nil }
        return URL(string: records[indexPath.item].detailURL) as NSURL?
    }

    private func setupView() {
        gridScrollView.drawsBackground = false
        gridScrollView.borderType = .noBorder
        gridScrollView.automaticallyAdjustsContentInsets = true
        gridScrollView.hasVerticalScroller = true
        gridScrollView.contentView.drawsBackground = false
        gridScrollView.documentView = collectionView
        gridScrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: gridScrollView.contentView, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateItemSize()
                self?.scheduleThumbnailPrefetch()
            }
        }

        // 与 MissKon/4KHD 网格完全一致的间距。
        gridLayout.columnSpacing = 8
        gridLayout.rowSpacing = 10
        gridLayout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        // 收藏网格没有 loading footer,最后一项是真实卡片,不能按 footer 布局。
        gridLayout.treatsLastItemAsFooter = false
        gridLayout.aspectRatioProvider = { [weak self] indexPath in
            guard let self, self.records.indices.contains(indexPath.item) else { return 16.0 / 9.0 }
            let record = self.records[indexPath.item]
            if let ratio = self.aspectRatiosByRecordID[record.id], ratio.isFinite, ratio > 0 { return ratio }
            if let coverURL = record.coverURL.flatMap(URL.init(string:)),
               let ratio = GalleryCoverAspectRatio.aspectRatio(from: coverURL),
               ratio.isFinite, ratio > 0
            {
                return CGFloat(ratio)
            }
            return 0.74
        }

        collectionView.collectionViewLayout = gridLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: true)
        collectionView.arrowKeyHandler = { [weak self] delta in self?.selectAdjacent(delta: delta) ?? false }
        collectionView.keyboardContext = WorkspaceKeyboardContext(
            stepSelection: { [weak self] delta in self?.selectAdjacent(delta: delta) ?? false },
            onEnter: { [weak self] in
                guard let self, let id = self.selectedRecordID,
                      let indexPath = self.records.firstIndex(where: { $0.id == id }) else { return false }
                self.openDetail(for: IndexPath(item: indexPath, section: 0))
                return true
            }
        )
        collectionView.contextMenuProvider = { [weak self] indexPath in self?.makeContextMenu(for: indexPath) }
        collectionView.doubleClickHandler = { [weak self] indexPath in self?.openDetail(for: indexPath) }
        collectionView.register(FavoritesGridItemView.self, forItemWithIdentifier: FavoritesGridItemView.reuseID)

        addSubview(gridScrollView)
        gridScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gridScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridScrollView.topAnchor.constraint(equalTo: topAnchor),
            gridScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @discardableResult
    private func updateItemSize() -> Bool {
        let visibleWidth = gridScrollView.contentView.bounds.width > 0 ? gridScrollView.contentView.bounds.width : bounds.width
        let widthChanged = abs(visibleWidth - lastLayoutWidth) > 0.5
        let prefChanged = gridLayout.preferredCardMinimumWidth != preferredCardMinimumWidth
            || gridLayout.minimumColumnCount != minimumColumnCount
            || gridLayout.maximumColumnCount != maximumColumnCount
        guard widthChanged || prefChanged else { return false }
        lastLayoutWidth = visibleWidth
        gridLayout.minimumColumnCount = minimumColumnCount
        gridLayout.maximumColumnCount = maximumColumnCount
        gridLayout.preferredCardMinimumWidth = preferredCardMinimumWidth
        performWithoutAnimation { gridLayout.invalidateLayout() }
        return true
    }

    private func updateAspectRatio(_ ratio: CGFloat, for recordID: FavoriteRecord.ID) {
        guard ratio.isFinite, ratio > 0 else { return }
        let clamped = max(gridLayout.minAspectRatio, min(gridLayout.maxAspectRatio, ratio))
        let current = aspectRatiosByRecordID[recordID] ?? 0.74
        let threshold: CGFloat = current < 0.5 ? 0.01 : 0.1
        guard abs(current - clamped) > threshold else { return }
        aspectRatiosByRecordID[recordID] = clamped
        aspectRatioLayoutQueue.add(id: "invalidate") { [weak self] in
            self?.performWithoutAnimation { self?.gridLayout.invalidateCachedFrames() }
        }
    }

    private func prefetchInitialThumbnails() {
        thumbnailPrefetchController.prefetchInitial(
            itemCount: records.count,
            itemID: { [weak self] index in self?.recordID(at: index) },
            request: { [weak self] index in self?.thumbnailRequest(at: index) }
        )
    }

    private func scheduleThumbnailPrefetch() {
        thumbnailPrefetchController.schedule(
            scrollView: gridScrollView,
            layout: gridLayout,
            itemCount: records.count,
            itemID: { [weak self] index in self?.recordID(at: index) },
            request: { [weak self] index in self?.thumbnailRequest(at: index) }
        )
    }

    private func recordID(at index: Int) -> FavoriteRecord.ID? {
        guard records.indices.contains(index) else { return nil }
        return records[index].id
    }

    private var thumbnailMaxPixelSize: CGFloat {
        let width = gridLayout.resolvedColumnWidth
        guard width > 0 else { return 512 }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return min(max(width * scale, 512), 1536)
    }

    private func thumbnailRequest(at index: Int) -> ImageRequest? {
        guard records.indices.contains(index),
              let coverURL = records[index].coverURL.flatMap(URL.init(string:)) else { return nil }
        let source = FavoriteSource.source(for: records[index])
        return RemoteImagePipeline.shared.request(
            for: coverURL,
            priority: .veryLow,
            maxPixelSize: thumbnailMaxPixelSize,
            configureURLRequest: source?.imageRequestConfigurator ?? { _ in }
        )
    }

    private func syncSelection() {
        guard let selectedRecordID, let index = records.firstIndex(where: { $0.id == selectedRecordID }) else {
            isApplyingSelection = true
            collectionView.selectionIndexPaths = []
            isApplyingSelection = false
            return
        }
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
        isApplyingSelection = false
        refreshVisibleSelection()
    }

    private func refreshVisibleSelection() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? FavoritesGridItemView,
                  records.indices.contains(indexPath.item) else { continue }
            let id = records[indexPath.item].id
            item.applySelectionState(id == selectedRecordID)
        }
    }

    private func selectAdjacent(delta: Int) -> Bool {
        guard !records.isEmpty else { return false }
        let current = selectedRecordID.flatMap { id in records.firstIndex { $0.id == id } } ?? 0
        let next = min(max(current + delta, 0), records.count - 1)
        guard next != current else { return true }
        selectedRecordID = records[next].id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [IndexPath(item: next, section: 0)]
        isApplyingSelection = false
        collectionView.scrollToItems(at: [IndexPath(item: next, section: 0)], scrollPosition: .nearestVerticalEdge)
        refreshVisibleSelection()
        onSelect?(records[next])
        return true
    }

    private func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        guard let indexPath, records.indices.contains(indexPath.item) else { return nil }
        let record = records[indexPath.item]
        selectedRecordID = record.id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [indexPath]
        isApplyingSelection = false
        refreshVisibleSelection()
        onSelect?(record)
        return contextMenuProvider?(record)
    }

    private func openDetail(for indexPath: IndexPath) {
        guard records.indices.contains(indexPath.item) else { return }
        let record = records[indexPath.item]
        selectedRecordID = record.id
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [indexPath]
        isApplyingSelection = false
        refreshVisibleSelection()
        onSelect?(record)
        onOpenDetail?()
    }

    private func performWithoutAnimation(_ updates: () -> Void) {
        NSView.performWithoutAnimation(updates)
    }
}
