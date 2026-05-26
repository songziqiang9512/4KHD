import AppKit
import Nuke

@MainActor
final class MissKonFilmstripView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((Int) -> Void)?

    private let materialView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private var slots: [MissKonImageSlot] = []
    private var selectedSlotID: MissKonImageSlot.ID?
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

    func update(slots: [MissKonImageSlot], selectedSlotID: MissKonImageSlot.ID?) {
        let slotIDsChanged = self.slots.map(\.id) != slots.map(\.id)
        let countChanged = slots.count != self.slots.count
        let previousSelectedID = self.selectedSlotID
        self.slots = slots
        self.selectedSlotID = selectedSlotID
        if countChanged {
            collectionView.reloadData()
        } else if slotIDsChanged {
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

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        slots.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: MissKonFilmstripItemView.reuseID, for: indexPath) as? MissKonFilmstripItemView ?? MissKonFilmstripItemView()
        if slots.indices.contains(indexPath.item) {
            item.configure(slot: slots[indexPath.item], isSelected: slots[indexPath.item].id == selectedSlotID)
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection, let indexPath = indexPaths.first, slots.indices.contains(indexPath.item) else { return }
        selectedSlotID = slots[indexPath.item].id
        refreshVisibleSelection()
        onSelect?(indexPath.item)
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
        collectionView.register(MissKonFilmstripItemView.self, forItemWithIdentifier: MissKonFilmstripItemView.reuseID)

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
        guard let selectedSlotID,
              let index = slots.firstIndex(where: { $0.id == selectedSlotID }) else {
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
            guard let item = collectionView.item(at: indexPath) as? MissKonFilmstripItemView,
                  slots.indices.contains(indexPath.item) else { continue }
            item.applySelection(slots[indexPath.item].id == selectedSlotID)
        }
    }
}

@MainActor
final class MissKonFilmstripItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("MissKonFilmstripItemView")

    private let thumbnailView = MissKonRemoteImageView()
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

    func configure(slot: MissKonImageSlot, isSelected: Bool) {
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
            indexLabel.centerYAnchor.constraint(equalTo: indexChrome.centerYAnchor)
        ])
    }
}
