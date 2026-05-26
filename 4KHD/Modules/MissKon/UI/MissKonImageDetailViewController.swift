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
    private let previousButton = DetailNavigationButton(symbolName: "chevron.left", accessibilityDescription: "上一张")
    private let nextButton = DetailNavigationButton(symbolName: "chevron.right", accessibilityDescription: "下一张")
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
    private var resetTokenSeen = UUID()
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
        let root = WorkspaceDetailRootView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.keyHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        view = root
        setupView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.onImageDisplayed = { [weak self] in
            self?.isDetailReady = true
            self?.reloadDetail()
        }
        filmstripView.onSelect = { [weak self] index in
            self?.library.detail.selectSlot(at: index)
        }
        reloadDetail()
        observeState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let firstResponder = view.window?.firstResponder as? NSText, firstResponder.isEditable {
            return
        }
        view.window?.makeFirstResponder(view)
    }

    func focus() {
        view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
    }

    private func setupView() {
        emptyLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        counterLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        counterLabel.textColor = .labelColor
        counterLabel.alignment = .center
        counterLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        counterChrome.addSubview(counterLabel)

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.alignment = .center
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusChrome.addSubview(statusLabel)

        previousButton.target = self
        previousButton.action = #selector(previousImage)
        nextButton.target = self
        nextButton.action = #selector(nextImage)

        for subview in [imageView, emptyLabel, previousButton, nextButton, counterChrome, statusChrome, filmstripView] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let filmstripHeightConstraint = filmstripView.heightAnchor.constraint(equalToConstant: 112)
        self.filmstripHeightConstraint = filmstripHeightConstraint

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: filmstripView.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            previousButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            previousButton.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 40),
            previousButton.heightAnchor.constraint(equalToConstant: 40),

            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            nextButton.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 40),
            nextButton.heightAnchor.constraint(equalToConstant: 40),

            counterChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            counterChrome.bottomAnchor.constraint(equalTo: filmstripView.topAnchor, constant: -12),
            counterChrome.heightAnchor.constraint(equalToConstant: 24),
            counterChrome.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            counterChrome.widthAnchor.constraint(greaterThanOrEqualTo: counterLabel.widthAnchor, constant: 16),
            counterLabel.leadingAnchor.constraint(equalTo: counterChrome.leadingAnchor, constant: 8),
            counterLabel.trailingAnchor.constraint(equalTo: counterChrome.trailingAnchor, constant: -8),
            counterLabel.centerYAnchor.constraint(equalTo: counterChrome.centerYAnchor),

            statusChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusChrome.bottomAnchor.constraint(equalTo: filmstripView.topAnchor, constant: -12),
            statusChrome.heightAnchor.constraint(equalToConstant: 24),
            statusChrome.widthAnchor.constraint(greaterThanOrEqualToConstant: 78),
            statusChrome.widthAnchor.constraint(greaterThanOrEqualTo: statusLabel.widthAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: statusChrome.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: statusChrome.trailingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: statusChrome.centerYAnchor),

            filmstripView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filmstripView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filmstripView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            filmstripHeightConstraint
        ])
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = library.currentItem?.id
            _ = library.selectedSlotID
            _ = library.imageSlots
            _ = library.isResolving
            _ = library.errorMessage
            _ = detailInteraction.resetToken
            _ = detailInteraction.saveMessage
            _ = immersive.isImmersive
            _ = detailPane.isPresented
            _ = filmstripVisibility.isPresented
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
        guard let item = library.currentItem else {
            currentItemID = nil
            currentSlotID = nil
            currentImageURL = nil
            imageView.setImageURL(nil)
            imageView.isHidden = true
            emptyLabel.isHidden = false
            previousButton.isHidden = true
            nextButton.isHidden = true
            counterChrome.isHidden = true
            statusChrome.isHidden = true
            filmstripView.isHidden = true
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }

        guard shouldLoadDetailContent else {
            currentSlotID = nil
            currentImageURL = nil
            imageView.setImageURL(nil)
            isDetailReady = false
            return
        }

        let slots = library.imageSlots
        guard !slots.isEmpty else {
            if !library.isResolving, library.errorMessage != nil {
                imageView.isHidden = false
                imageView.showFailure { [weak self] in
                    self?.library.detail.retry()
                }
            } else {
                imageView.isHidden = true
            }
            emptyLabel.isHidden = false
            previousButton.isHidden = true
            nextButton.isHidden = true
            counterChrome.isHidden = true
            statusChrome.isHidden = false
            statusLabel.stringValue = library.isResolving ? "解析中..." : (library.errorMessage ?? "")
            filmstripView.isHidden = true
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }

        imageView.isHidden = false
        emptyLabel.isHidden = true
        previousButton.isHidden = false
        nextButton.isHidden = false
        counterChrome.isHidden = false

        let selectedID = library.selectedSlotID ?? slots.first?.id
        let selectedIndex = selectedID.flatMap { id in slots.firstIndex { $0.id == id } } ?? 0
        let selectedSlot = slots[selectedIndex]

        previousButton.isEnabled = selectedIndex > 0
        nextButton.isEnabled = selectedIndex < slots.count - 1

        if currentItemID != item.id {
            currentItemID = item.id
            detailInteraction.saveMessage = ""
            isDetailReady = false
            RemoteImagePipeline.shared.stopDetailPrefetching()
            // Show cover image immediately while detail resolves
            if let coverURL = item.coverURL {
                imageView.setImageURL(coverURL)
            }
        }
        if currentSlotID != selectedSlot.id || currentImageURL != selectedSlot.knownURL {
            let url = selectedSlot.knownURL ?? library.detail.imageURL(for: selectedSlot)
            currentSlotID = selectedSlot.id
            currentImageURL = url
            detailInteraction.saveMessage = ""
            // Preserve current image (cover or previous detail) while new detail loads
            imageView.setImageURL(url, preservesCurrentImageUntilLoaded: imageView.imageView.image != nil)
            // Prefetch adjacent images for smoother navigation
            let start = max(selectedIndex - 2, 0)
            let end = min(selectedIndex + 2, slots.count - 1)
            let adjacentURLs = slots[start...end].compactMap { $0.knownURL ?? library.detail.imageURL(for: $0) }
            RemoteImagePipeline.shared.prefetchDetailImages(adjacentURLs)
        }

        counterLabel.stringValue = "\(selectedSlot.displayIndex + 1) / \(slots.count)"
        statusLabel.stringValue = detailStatusText
        statusChrome.isHidden = statusLabel.stringValue.isEmpty

        let showsFilmstrip = filmstripVisibility.isPresented && slots.count > 1
        updateFilmstripLayout(showsFilmstrip: showsFilmstrip)
        filmstripView.update(slots: slots, selectedSlotID: selectedSlot.id)

        if detailInteraction.resetToken != resetTokenSeen {
            resetTokenSeen = detailInteraction.resetToken
            imageView.resetZoom()
        }
    }

    private var shouldLoadDetailContent: Bool {
        detailPane.isPresented || immersive.isImmersive
    }

    private func updateFilmstripLayout(showsFilmstrip: Bool) {
        let needsAnimation = filmstripView.isHidden == showsFilmstrip
        if needsAnimation {
            if showsFilmstrip {
                filmstripView.isHidden = false
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                filmstripHeightConstraint?.animator().constant = showsFilmstrip ? 112 : 0
            } completionHandler: { [weak self] in
                self?.filmstripView.isHidden = !showsFilmstrip
            }
        } else {
            filmstripHeightConstraint?.constant = showsFilmstrip ? 112 : 0
            filmstripView.isHidden = !showsFilmstrip
        }
    }

    private var detailStatusText: String {
        if let errorMessage = library.errorMessage { return errorMessage }
        switch detailInteraction.saveMessage {
        case "保存中", "已保存", "保存失败":
            return detailInteraction.saveMessage
        default:
            break
        }
        if !isDetailReady { return "加载中" }
        if library.isResolving { return "解析中" }
        return ""
    }

    @objc func saveImage(_ sender: Any?) {
        guard let url = currentImageURL else { return }
        let filename = url.lastPathComponent
        detailInteraction.save(imageURL: url, filename: filename)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        WorkspaceKeyboardHandler.keyDown(
            event,
            context: WorkspaceKeyboardContext(
                stepSelection: { [weak self] delta in self?.selectAdjacent(delta: delta) ?? false },
                toggleImmersive: { [weak self] in
                    self?.immersive.toggle()
                    return true
                }
            )
        )
    }

    @objc private func previousImage() {
        library.detail.selectSlot(at: max((library.selectedSlotID.flatMap { id in library.imageSlots.firstIndex { $0.id == id } } ?? 0) - 1, 0))
    }

    @objc private func nextImage() {
        let slots = library.imageSlots
        let current = library.selectedSlotID.flatMap { id in slots.firstIndex { $0.id == id } } ?? 0
        library.detail.selectSlot(at: min(current + 1, slots.count - 1))
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
