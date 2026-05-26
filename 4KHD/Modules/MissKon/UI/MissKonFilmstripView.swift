import AppKit
import Nuke

@MainActor
final class MissKonFilmstripView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelectSlot: ((Int) -> Void)?
    var onNeedsMore: (() -> Void)?

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

    func update(slots: [MissKonImageSlot], selectedSlotID: MissKonImageSlot.ID?) {
        self.slots = slots
        self.selectedSlotID = selectedSlotID
        collectionView.reloadData()
        syncSelection()
    }

    func selectSlot(at displayIndex: Int) {
        guard slots.indices.contains(displayIndex) else { return }
        selectedSlotID = slots[displayIndex].id
        let indexPath = IndexPath(item: displayIndex, section: 0)
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [indexPath]
        isApplyingSelection = false
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredHorizontally)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { slots.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: MissKonFilmstripItemView.reuseID, for: indexPath) as? MissKonFilmstripItemView ?? MissKonFilmstripItemView()
        if slots.indices.contains(indexPath.item) {
            let slot = slots[indexPath.item]
            item.configure(slot: slot, isSelected: slot.id == selectedSlotID)
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection, let indexPath = indexPaths.first, slots.indices.contains(indexPath.item) else { return }
        onSelectSlot?(indexPath.item)
    }

    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        guard indexPath.item >= max(slots.count - 5, 0) else { return }
        onNeedsMore?()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor

        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.itemSize = NSSize(width: 56, height: 84)
        layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView
        scrollView.contentView.drawsBackground = false

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MissKonFilmstripItemView.self, forItemWithIdentifier: MissKonFilmstripItemView.reuseID)

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func syncSelection() {
        guard let selectedSlotID,
              let index = slots.firstIndex(where: { $0.id == selectedSlotID }) else {
            isApplyingSelection = true; collectionView.selectionIndexPaths = []; isApplyingSelection = false; return
        }
        isApplyingSelection = true
        collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
        isApplyingSelection = false
    }
}

@MainActor
final class MissKonFilmstripItemView: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("MissKonFilmstripItemView")

    private let thumbnailView = NSImageView()
    private let indexLabel = NSTextField(labelWithString: "")
    private var imageTask: ImageTask?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 7
        view.layer?.masksToBounds = true

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        view.addSubview(thumbnailView)
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        indexLabel.font = .systemFont(ofSize: 10)
        indexLabel.textColor = .white
        indexLabel.alignment = .center
        let chrome = NSView()
        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        chrome.addSubview(indexLabel)
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indexLabel.centerXAnchor.constraint(equalTo: chrome.centerXAnchor),
            indexLabel.centerYAnchor.constraint(equalTo: chrome.centerYAnchor)
        ])
        view.addSubview(chrome)
        chrome.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            chrome.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        thumbnailView.image = nil
    }

    func configure(slot: MissKonImageSlot, isSelected: Bool) {
        indexLabel.stringValue = "\(slot.displayIndex + 1)"
        view.layer?.borderWidth = isSelected ? 2 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor

        guard let url = slot.knownURL else {
            thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            return
        }
        let request = RemoteImagePipeline.shared.request(
            for: url, priority: .low, maxPixelSize: 160,
            configureURLRequest: MissKonRequestFactory.configureImageRequest
        )
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                self?.thumbnailView.image = image
            }
        }
    }
}
