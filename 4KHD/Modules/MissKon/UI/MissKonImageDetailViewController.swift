import AppKit
import Observation

@MainActor
final class MissKonImageDetailViewController: NSViewController, WorkspaceFocusable {
    private let library: MissKonGalleryStore
    private let immersive: ImmersiveController
    private let detailPane: WorkspaceDetailPaneController
    private let detailInteraction: MissKonDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let imageView = MissKonZoomableImageView()
    private let filmstripView = MissKonFilmstripView()
    private let emptyLabel = NSTextField(labelWithString: "没有可显示内容")
    private let counterChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let counterLabel = NSTextField(labelWithString: "")
    private let statusChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let statusLabel = NSTextField(labelWithString: "")
    private var filmstripHeightConstraint: NSLayoutConstraint?
    private var isObserving = false
    private var currentItemID: MissKonItem.ID?
    private var currentSlotID: MissKonImageSlot.ID?
    private var currentImageURL: URL?
    private var isDetailReady = false
    private let reloadQueue = WorkspaceCoalescingQueue(name: "MissKonDetail Reload", interval: 0.05, maxInterval: 0.1)

    init(
        library: MissKonGalleryStore,
        immersive: ImmersiveController,
        detailPane: WorkspaceDetailPaneController,
        detailInteraction: MissKonDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController
    ) {
        self.library = library
        self.immersive = immersive
        self.detailPane = detailPane
        self.detailInteraction = detailInteraction
        self.filmstripVisibility = filmstripVisibility
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor

        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        setupChrome()
        setupFilmstrip()

        for subview in [imageView, emptyLabel, filmstripView, counterChrome, statusChrome] {
            root.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }

        filmstripHeightConstraint = filmstripView.heightAnchor.constraint(equalToConstant: 112)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: root.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: filmstripView.topAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            filmstripView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            filmstripView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            filmstripView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            filmstripHeightConstraint!,
            counterChrome.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            counterChrome.bottomAnchor.constraint(equalTo: filmstripView.topAnchor, constant: -12),
            statusChrome.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            statusChrome.bottomAnchor.constraint(equalTo: filmstripView.topAnchor, constant: -12)
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeState()
    }

    func focus() {
        view.window?.makeFirstResponder(imageView)
    }

    private func setupChrome() {
        counterLabel.font = .systemFont(ofSize: 11, weight: .medium)
        counterLabel.textColor = .white
        counterChrome.addSubview(counterLabel)
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            counterLabel.leadingAnchor.constraint(equalTo: counterChrome.leadingAnchor, constant: 10),
            counterLabel.trailingAnchor.constraint(equalTo: counterChrome.trailingAnchor, constant: -10),
            counterLabel.centerYAnchor.constraint(equalTo: counterChrome.centerYAnchor)
        ])

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .white
        statusChrome.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: statusChrome.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusChrome.trailingAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: statusChrome.centerYAnchor)
        ])
        statusChrome.isHidden = true
    }

    private func setupFilmstrip() {
        filmstripView.onSelectSlot = { [weak self] index in
            self?.library.detail.selectSlot(at: index)
        }
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = library.imageSlots
            _ = library.selectedSlotID
            _ = library.currentItem?.id
            _ = library.isResolving
            _ = library.errorMessage
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.reloadQueue.add(id: "reload") { [weak self] in self?.reloadDetail() }
                self.observeState()
            }
        }
    }

    private func reloadDetail() {
        let slots = library.imageSlots
        guard !slots.isEmpty else {
            imageView.isHidden = true
            emptyLabel.isHidden = false
            filmstripView.isHidden = true
            counterChrome.isHidden = true
            return
        }
        imageView.isHidden = false
        emptyLabel.isHidden = true

        let selectedID = library.selectedSlotID ?? slots.first?.id
        let selectedSlot = selectedID.flatMap { id in slots.first { $0.id == id } } ?? slots.first!

        if currentSlotID != selectedSlot.id {
            currentSlotID = selectedSlot.id
            if let url = library.detail.imageURL(for: selectedSlot) {
                currentImageURL = url
                imageView.loadImage(from: url)
            }
        }

        counterLabel.stringValue = "\(selectedSlot.displayIndex + 1) / \(slots.count)"

        if let error = library.errorMessage {
            statusLabel.stringValue = error
            statusChrome.isHidden = false
        } else if library.isResolving {
            statusLabel.stringValue = "解析中..."
            statusChrome.isHidden = false
        } else {
            statusChrome.isHidden = true
        }

        filmstripView.update(slots: slots, selectedSlotID: selectedSlot.id)

        let filmstripVisible = slots.count > 1
        filmstripView.isHidden = !filmstripVisible
        filmstripHeightConstraint?.constant = filmstripVisible ? 112 : 0

        counterChrome.isHidden = slots.isEmpty
    }

    @objc func saveImage(_ sender: Any?) {
        guard let url = currentImageURL else { return }
        detailInteraction.save(imageURL: url)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let handled = WorkspaceKeyboardHandler.keyDown(event, context: WorkspaceKeyboardContext(
            stepSelection: { [weak self] delta in self?.selectAdjacent(delta: delta) ?? false }
        ))
        return handled
    }

    private func selectAdjacent(delta: Int) -> Bool {
        let slots = library.imageSlots
        guard !slots.isEmpty else { return false }
        let current = library.selectedSlotID.flatMap { id in slots.firstIndex { $0.id == id } } ?? 0
        let next = min(max(current + delta, 0), slots.count - 1)
        guard next != current else { return true }
        library.detail.selectSlot(at: next)
        return true
    }
}
