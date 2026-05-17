import AppKit

@MainActor
final class LocalImageFilmstripView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private var images: [LocalImageItem] = []
    private var selectedIndex = 0
    var onSelect: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(images: [LocalImageItem], selectedIndex: Int) {
        let idsChanged = self.images.map(\.id) != images.map(\.id)
        self.images = images
        self.selectedIndex = selectedIndex
        if idsChanged {
            collectionView.reloadData()
        } else {
            collectionView.reloadItems(at: Set(collectionView.indexPathsForVisibleItems()))
        }
        syncSelection()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        images.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        guard indexPath.item < images.count,
              let item = collectionView.makeItem(
                withIdentifier: LocalFilmstripItemView.reuseID,
                for: indexPath
              ) as? LocalFilmstripItemView else {
            return NSCollectionViewItem()
        }
        item.configure(
            image: images[indexPath.item],
            index: indexPath.item,
            isSelected: indexPath.item == selectedIndex
        )
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, images.indices.contains(indexPath.item) else { return }
        onSelect?(indexPath.item)
    }

    private func setupView() {
        wantsLayer = true
        updateAppearance()

        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 72, height: 96)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(LocalFilmstripItemView.self, forItemWithIdentifier: LocalFilmstripItemView.reuseID)

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView

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

    private func syncSelection() {
        guard images.indices.contains(selectedIndex) else {
            collectionView.deselectAll(nil)
            return
        }
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        collectionView.selectItems(at: [indexPath], scrollPosition: .centeredHorizontally)
    }
}

@MainActor
final class LocalFilmstripItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LocalFilmstripItemView")

    private let thumbnailView = NSImageView()
    private let indexLabel = NSTextField(labelWithString: "")
    private var imageTask: Task<Void, Never>?

    override func loadView() {
        view = NSView()
        setupView()
    }

    deinit {
        imageTask?.cancel()
    }

    override var isSelected: Bool {
        didSet {
            applySelection(isSelected)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
    }

    func configure(image: LocalImageItem, index: Int, isSelected: Bool) {
        indexLabel.stringValue = "#\(index + 1)"
        thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        applySelection(isSelected)

        imageTask?.cancel()
        imageTask = Task { [weak self] in
            let loaded = await LocalImageCache.shared.image(for: image.url, maxPixelSize: 220)
            guard !Task.isCancelled else { return }
            self?.thumbnailView.image = loaded ?? NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        }
    }

    private func setupView() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor

        indexLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        indexLabel.textColor = .labelColor
        indexLabel.alignment = .center
        indexLabel.wantsLayer = true
        indexLabel.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82).cgColor
        indexLabel.layer?.cornerRadius = 8

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
            indexLabel.heightAnchor.constraint(equalToConstant: 18),
            indexLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
    }

    private func applySelection(_ selected: Bool) {
        view.layer?.borderWidth = selected ? 2 : 0
        view.layer?.borderColor = selected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
    }
}
