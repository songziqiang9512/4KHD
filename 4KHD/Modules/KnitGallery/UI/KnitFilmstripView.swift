import AppKit

@MainActor
final class KnitFilmstripView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((Int) -> Void)?
    var onReachedEnd: (() -> Void)?

    private let materialView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private var slots: [KnitImageSlot] = []
    private var selectedIndex = 0
    private var showsLoadingTile = false
    private var isApplyingSelection = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(slots: [KnitImageSlot], selectedIndex: Int, showsLoadingTile: Bool) {
        let previousSelectedIndex = self.selectedIndex
        let contentChanged = self.slots.count != slots.count
            || !zip(self.slots, slots).allSatisfy { $0.id == $1.id && $0.knownURL == $1.knownURL }
        let loadingChanged = self.showsLoadingTile != showsLoadingTile
        let countChanged = slots.count + (showsLoadingTile ? 1 : 0)
            != self.slots.count + (self.showsLoadingTile ? 1 : 0)
        self.slots = slots
        self.selectedIndex = selectedIndex
        self.showsLoadingTile = showsLoadingTile

        if countChanged {
            collectionView.reloadData()
        } else if contentChanged || loadingChanged {
            collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems())
        } else if previousSelectedIndex != selectedIndex {
            refreshVisibleSelection()
        }
        syncSelection()
        if previousSelectedIndex != selectedIndex {
            scrollToSelectedItem()
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        slots.count + (showsLoadingTile ? 1 : 0)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        if indexPath.item >= slots.count {
            return collectionView.makeItem(withIdentifier: KnitFilmstripLoadingItem.reuseID, for: indexPath)
        }
        let item = collectionView.makeItem(
            withIdentifier: KnitFilmstripItemView.reuseID,
            for: indexPath
        ) as? KnitFilmstripItemView ?? KnitFilmstripItemView()
        item.configure(slot: slots[indexPath.item], isSelected: indexPath.item == selectedIndex)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection,
              let indexPath = indexPaths.first,
              slots.indices.contains(indexPath.item) else { return }
        selectedIndex = indexPath.item
        refreshVisibleSelection()
        onSelect?(indexPath.item)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        if indexPath.item >= max(slots.count - 4, 0) {
            onReachedEnd?()
        }
    }

    private func setupView() {
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
        collectionView.register(KnitFilmstripItemView.self, forItemWithIdentifier: KnitFilmstripItemView.reuseID)
        collectionView.register(KnitFilmstripLoadingItem.self, forItemWithIdentifier: KnitFilmstripLoadingItem.reuseID)

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
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateAppearance() {
        materialView.material = .hudWindow
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        refreshVisibleSelection()
    }

    private func syncSelection() {
        guard slots.indices.contains(selectedIndex) else {
            isApplyingSelection = true
            collectionView.selectionIndexPaths = []
            isApplyingSelection = false
            return
        }
        isApplyingSelection = true
        collectionView.selectItems(at: [IndexPath(item: selectedIndex, section: 0)], scrollPosition: [])
        isApplyingSelection = false
    }

    private func scrollToSelectedItem() {
        guard slots.indices.contains(selectedIndex) else { return }
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath),
              !collectionView.visibleRect.contains(attributes.frame) else { return }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .left)
    }

    private func refreshVisibleSelection() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? KnitFilmstripItemView else { continue }
            item.applySelection(indexPath.item == selectedIndex)
        }
    }
}

@MainActor
private final class KnitFilmstripItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("KnitFilmstripItemView")

    private let thumbnailView = RemoteImageView()
    private let indexChrome = DetailOverlayChromeView(cornerRadius: 7)
    private let indexLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        setupView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.cancelPendingLoad()
    }

    func configure(slot: KnitImageSlot, isSelected: Bool) {
        thumbnailView.configureRequest = KnitRequestFactory.configureImageRequest
        thumbnailView.setImage(url: slot.knownURL, maxPixelSize: 220)
        indexLabel.stringValue = "#\(slot.displayIndex)"
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
        indexLabel.alignment = .center
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
            indexChrome.widthAnchor.constraint(greaterThanOrEqualTo: indexLabel.widthAnchor, constant: 12),
            indexLabel.leadingAnchor.constraint(equalTo: indexChrome.leadingAnchor, constant: 6),
            indexLabel.trailingAnchor.constraint(equalTo: indexChrome.trailingAnchor, constant: -6),
            indexLabel.centerYAnchor.constraint(equalTo: indexChrome.centerYAnchor)
        ])
    }
}

@MainActor
private final class KnitFilmstripLoadingItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("KnitFilmstripLoadingItem")
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
            progress.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
