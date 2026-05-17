import AppKit

@MainActor
final class GalleryFilmstripView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((Int) -> Void)?
    var onReachedEnd: (() -> Void)?

    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private var slots: [ImageSlot] = []
    private var selectedIndex = 0
    private var showsLoadingTile = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(slots: [ImageSlot], selectedIndex: Int, showsLoadingTile: Bool) {
        self.slots = slots
        self.selectedIndex = selectedIndex
        self.showsLoadingTile = showsLoadingTile
        collectionView.reloadData()
        collectionView.selectionIndexPaths = slots.indices.contains(selectedIndex)
            ? [IndexPath(item: selectedIndex, section: 0)]
            : []
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        slots.count + (showsLoadingTile ? 1 : 0)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        if indexPath.item >= slots.count {
            let item = collectionView.makeItem(
                withIdentifier: GalleryFilmstripLoadingItem.reuseID,
                for: indexPath
            ) as? GalleryFilmstripLoadingItem ?? GalleryFilmstripLoadingItem()
            return item
        }
        let item = collectionView.makeItem(
            withIdentifier: GalleryFilmstripItemView.reuseID,
            for: indexPath
        ) as? GalleryFilmstripItemView ?? GalleryFilmstripItemView()
        item.configure(slot: slots[indexPath.item], isSelected: indexPath.item == selectedIndex)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, slots.indices.contains(indexPath.item) else { return }
        selectedIndex = indexPath.item
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
        wantsLayer = true
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
        collectionView.register(GalleryFilmstripItemView.self, forItemWithIdentifier: GalleryFilmstripItemView.reuseID)
        collectionView.register(GalleryFilmstripLoadingItem.self, forItemWithIdentifier: GalleryFilmstripLoadingItem.reuseID)

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
    }
}

@MainActor
final class GalleryFilmstripItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("GalleryFilmstripItemView")

    private let thumbnailView = GalleryRemoteImageView()
    private let indexLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        setupView()
    }

    func configure(slot: ImageSlot, isSelected: Bool) {
        thumbnailView.setImage(url: slot.knownURL, maxPixelSize: 220)
        indexLabel.stringValue = "#\(slot.displayIndex)"
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
        indexLabel.wantsLayer = true
        indexLabel.layer?.cornerRadius = 7
        indexLabel.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.78).cgColor

        view.addSubview(thumbnailView)
        view.addSubview(indexLabel)
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            indexLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            indexLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            indexLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            indexLabel.heightAnchor.constraint(equalToConstant: 18)
        ])
    }
}

@MainActor
final class GalleryFilmstripLoadingItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("GalleryFilmstripLoadingItem")

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
