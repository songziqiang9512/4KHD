import AppKit

@MainActor
final class LocalImageFilmstripView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private let materialView = NSVisualEffectView()
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
        let previousSelectedIndex = self.selectedIndex
        let idsChanged = self.images.map(\.id) != images.map(\.id)
        self.images = images
        self.selectedIndex = selectedIndex
        if idsChanged {
            collectionView.reloadData()
        } else if previousSelectedIndex != selectedIndex {
            refreshVisibleSelection()
        }
        let selectionChanged = previousSelectedIndex != selectedIndex
        syncSelection()
        if selectionChanged {
            scrollToSelectedItem()
        }
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
        selectedIndex = indexPath.item
        refreshVisibleSelection()
        onSelect?(indexPath.item)
    }

    private func setupView() {
        wantsLayer = false
        updateAppearance()

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
        collectionView.register(LocalFilmstripItemView.self, forItemWithIdentifier: LocalFilmstripItemView.reuseID)

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView

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
        guard images.indices.contains(selectedIndex) else {
            collectionView.deselectAll(nil)
            return
        }
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        collectionView.selectItems(at: [indexPath], scrollPosition: [])
    }

    private func scrollToSelectedItem() {
        guard images.indices.contains(selectedIndex) else { return }
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        let visibleRect = collectionView.visibleRect
        guard let attrs = collectionView.layoutAttributesForItem(at: indexPath),
              !visibleRect.contains(attrs.frame) else { return }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .left)
    }

    private func refreshVisibleSelection() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? LocalFilmstripItemView else { continue }
            item.applySelection(indexPath.item == selectedIndex)
        }
    }
}

@MainActor
final class LocalFilmstripItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LocalFilmstripItemView")

    private let thumbnailView = NSImageView()
    private let indexChrome = DetailOverlayChromeView(cornerRadius: 7)
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
            indexChrome.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
            indexChrome.widthAnchor.constraint(greaterThanOrEqualTo: indexLabel.widthAnchor, constant: 12),
            indexLabel.leadingAnchor.constraint(equalTo: indexChrome.leadingAnchor, constant: 6),
            indexLabel.trailingAnchor.constraint(equalTo: indexChrome.trailingAnchor, constant: -6),
            indexLabel.centerYAnchor.constraint(equalTo: indexChrome.centerYAnchor)
        ])
    }

    func applySelection(_ selected: Bool) {
        view.layer?.borderWidth = selected ? 2 : 0
        view.layer?.borderColor = selected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
    }
}
