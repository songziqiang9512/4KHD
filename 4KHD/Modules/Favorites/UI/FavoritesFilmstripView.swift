import AppKit
import Nuke

/// 收藏详情的胶片条:与 MissKon 版同款布局与选中行为,缩略图请求头按来源配置。
@MainActor
final class FavoritesFilmstripView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((Int) -> Void)?
    var onReachedEnd: (() -> Void)?
    var requestConfigurator: ((inout URLRequest) -> Void)?

    private let materialView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private var slots: [FavoritesImageSlot] = []
    private var selectedSlotID: FavoritesImageSlot.ID?
    private var showsLoadingTile = false
    private var isApplyingSelection = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(
        slots: [FavoritesImageSlot],
        selectedSlotID: FavoritesImageSlot.ID?,
        showsLoadingTile: Bool = false
    ) {
        // 先比 count 再逐项比较 id,避免每次全量 map 分配数组。
        let countChanged = slots.count != self.slots.count
        var slotIDsChanged = false
        if !countChanged {
            slotIDsChanged = !zip(self.slots, slots).allSatisfy {
                $0.id == $1.id && $0.knownURL == $1.knownURL
            }
        }
        let previousSelectedID = self.selectedSlotID
        let loadingChanged = self.showsLoadingTile != showsLoadingTile
        let itemCountChanged = self.slots.count + (self.showsLoadingTile ? 1 : 0)
            != slots.count + (showsLoadingTile ? 1 : 0)
        self.slots = slots
        self.selectedSlotID = selectedSlotID
        self.showsLoadingTile = showsLoadingTile
        if countChanged || itemCountChanged {
            collectionView.reloadData()
        } else if slotIDsChanged || loadingChanged {
            collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems())
        } else if previousSelectedID != selectedSlotID {
            refreshVisibleSelection()
        }
        let selectionChanged = previousSelectedID != selectedSlotID
        syncSelection()
        if selectionChanged {
            scrollToSelectedItem()
        }
    }

    func numberOfSections(in _: NSCollectionView) -> Int {
        1
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        slots.count + (showsLoadingTile ? 1 : 0)
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        if indexPath.item >= slots.count {
            return collectionView.makeItem(
                withIdentifier: FavoritesFilmstripLoadingItem.reuseID,
                for: indexPath
            )
        }
        let item = collectionView.makeItem(withIdentifier: FavoritesFilmstripItemView.reuseID, for: indexPath) as? FavoritesFilmstripItemView ?? FavoritesFilmstripItemView()
        if slots.indices.contains(indexPath.item) {
            item.configure(
                slot: slots[indexPath.item],
                isSelected: slots[indexPath.item].id == selectedSlotID,
                requestConfigurator: requestConfigurator
            )
        }
        return item
    }

    func collectionView(_: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection, let indexPath = indexPaths.first, slots.indices.contains(indexPath.item) else { return }
        selectedSlotID = slots[indexPath.item].id
        refreshVisibleSelection()
        onSelect?(indexPath.item)
    }

    func collectionView(
        _: NSCollectionView,
        willDisplay _: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        if indexPath.item >= max(slots.count - 4, 0) {
            onReachedEnd?()
        }
    }

    private func setupView() {
        wantsLayer = false
        updateAppearance()

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.documentView = collectionView

        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 72, height: 96)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(FavoritesFilmstripItemView.self, forItemWithIdentifier: FavoritesFilmstripItemView.reuseID)
        collectionView.register(
            FavoritesFilmstripLoadingItem.self,
            forItemWithIdentifier: FavoritesFilmstripLoadingItem.reuseID
        )

        addSubview(materialView)
        addSubview(scrollView)
        materialView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.topAnchor.constraint(equalTo: topAnchor),
            materialView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func updateAppearance() {
        materialView.material = .hudWindow
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        refreshVisibleSelection()
    }

    private func syncSelection() {
        guard let selectedSlotID,
              let index = slots.firstIndex(where: { $0.id == selectedSlotID })
        else {
            isApplyingSelection = true
            collectionView.selectionIndexPaths = []
            isApplyingSelection = false
            return
        }
        isApplyingSelection = true
        collectionView.selectItems(at: [IndexPath(item: index, section: 0)], scrollPosition: [])
        isApplyingSelection = false
    }

    private func scrollToSelectedItem() {
        guard let selectedSlotID,
              let index = slots.firstIndex(where: { $0.id == selectedSlotID }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        let visibleRect = collectionView.visibleRect
        guard let attrs = collectionView.layoutAttributesForItem(at: indexPath),
              !visibleRect.contains(attrs.frame) else { return }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .left)
    }

    private func refreshVisibleSelection() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? FavoritesFilmstripItemView,
                  slots.indices.contains(indexPath.item) else { continue }
            item.applySelection(slots[indexPath.item].id == selectedSlotID)
        }
    }
}

@MainActor
private final class FavoritesFilmstripLoadingItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("FavoritesFilmstripLoadingItem")
    private let progress = NSProgressIndicator()

    override func loadView() {
        view = NSView()
        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)
        view.addSubview(progress)
        progress.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progress.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

@MainActor
final class FavoritesFilmstripItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("FavoritesFilmstripItemView")

    private let thumbnailView = RemoteImageView()
    private let indexChrome = DetailOverlayChromeView(cornerRadius: 7)
    private let indexLabel = NSTextField(labelWithString: "")
    private var imageTask: ImageTask?

    override func loadView() {
        view = NSView()
        setupView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
    }

    func configure(slot: FavoritesImageSlot, isSelected: Bool, requestConfigurator: ((inout URLRequest) -> Void)?) {
        thumbnailView.configureRequest = requestConfigurator
        thumbnailView.setImage(url: slot.knownURL, maxPixelSize: 220)
        indexLabel.stringValue = "\(slot.displayIndex + 1)"
        applySelection(isSelected)
    }

    func applySelection(_ isSelected: Bool) {
        view.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        view.layer?.borderWidth = isSelected ? 2 : 0
    }

    private func setupView() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true

        thumbnailView.mode = .aspectFill
        thumbnailView.cornerRadius = 6

        indexLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        indexLabel.textColor = .labelColor
        indexLabel.alignment = .center
        indexLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        indexChrome.addSubview(indexLabel)

        view.addSubview(thumbnailView)
        view.addSubview(indexChrome)
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        indexChrome.translatesAutoresizingMaskIntoConstraints = false
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            indexChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            indexChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            indexChrome.heightAnchor.constraint(equalToConstant: 18),
            indexChrome.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            indexChrome.widthAnchor.constraint(greaterThanOrEqualTo: indexLabel.widthAnchor, constant: 12),
            indexLabel.leadingAnchor.constraint(equalTo: indexChrome.leadingAnchor, constant: 6),
            indexLabel.trailingAnchor.constraint(equalTo: indexChrome.trailingAnchor, constant: -6),
            indexLabel.centerYAnchor.constraint(equalTo: indexChrome.centerYAnchor),
        ])
    }
}
