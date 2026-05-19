import AppKit
import Observation

@MainActor
final class GalleryImageDetailViewController: NSViewController, WorkspaceFocusable {
    private let library: FourKHDGalleryStore
    private let immersive: ImmersiveController
    private let detailInteraction: GalleryDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let resolver = DetailImageResolver()
    private let imageView = GalleryZoomableImageView()
    private let filmstripView = GalleryFilmstripView()
    private let emptyLabel = NSTextField(labelWithString: "没有可显示内容")
    private let counterChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let counterLabel = NSTextField(labelWithString: "")
    private let statusChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let statusLabel = NSTextField(labelWithString: "")
    private var filmstripHeightConstraint: NSLayoutConstraint?
    private var imageTopSafeAreaConstraint: NSLayoutConstraint?
    private var imageTopFullBleedConstraint: NSLayoutConstraint?
    private var isObserving = false
    private var currentItemID: GalleryItem.ID?
    private var currentSlotID: ImageSlot.ID?
    private var detailFailed = false
    private var isDetailReady = false

    init(
        library: FourKHDGalleryStore,
        immersive: ImmersiveController,
        detailInteraction: GalleryDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController
    ) {
        self.library = library
        self.immersive = immersive
        self.detailInteraction = detailInteraction
        self.filmstripVisibility = filmstripVisibility
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = GalleryImageDetailRootView()
        (view as? GalleryImageDetailRootView)?.keyHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        setupView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        resolver.onResolvedPage = { [weak self] page in
            self?.library.registerResolvedPage(page)
        }
        resolver.onFailure = { [weak self] failedPageURL in
            guard let self, failedPageURL == self.library.selectedSlot?.pageURL else { return }
            self.detailFailed = true
            self.isDetailReady = true
            self.imageView.showFailure(
                retry: { [weak self] in self?.retryCurrentPage() },
                openOriginal: { NSWorkspace.shared.open(failedPageURL) }
            )
            self.reloadDetail()
        }
        imageView.onImageDisplayed = { [weak self] in
            self?.detailFailed = false
            self?.isDetailReady = true
            self?.reloadDetail()
        }
        filmstripView.onSelect = { [weak self] index in
            self?.library.selectImage(at: index)
        }
        filmstripView.onReachedEnd = { [weak self] in
            self?.library.ensureNextDetailPageLoaded(reason: .filmstripReachedEnd)
        }
        reloadDetail()
        observeState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
    }

    func focus() {
        view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
    }

    private func setupView() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

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

        for subview in [imageView, emptyLabel, counterChrome, statusChrome, filmstripView] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let filmstripHeightConstraint = filmstripView.heightAnchor.constraint(equalToConstant: 112)
        let imageTopSafeAreaConstraint = imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        let imageTopFullBleedConstraint = imageView.topAnchor.constraint(equalTo: view.topAnchor)
        self.filmstripHeightConstraint = filmstripHeightConstraint
        self.imageTopSafeAreaConstraint = imageTopSafeAreaConstraint
        self.imageTopFullBleedConstraint = imageTopFullBleedConstraint

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageTopSafeAreaConstraint,
            imageView.bottomAnchor.constraint(equalTo: filmstripView.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

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
            _ = library.selectedItem?.id
            _ = library.selectedSlot?.id
            _ = library.selectedImageIndex
            _ = library.loadedImageSlots
            _ = library.prefetchPageURL
            _ = library.isFavorite(library.selectedItem ?? placeholderItem)
            _ = immersive.isImmersive
            _ = detailInteraction.resetToken
            _ = detailInteraction.saveMessage
            _ = filmstripVisibility.isPresented
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.reloadDetail()
                self.observeState()
            }
        }
    }

    private func reloadDetail() {
        guard let item = library.selectedItem, let slot = library.selectedSlot else {
            imageView.isHidden = true
            emptyLabel.isHidden = false
            counterChrome.isHidden = true
            statusChrome.isHidden = true
            filmstripView.isHidden = true
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }

        imageView.isHidden = false
        emptyLabel.isHidden = true
        counterChrome.isHidden = false

        if currentItemID != item.id {
            currentItemID = item.id
            detailInteraction.saveMessage = ""
            RemoteImagePipeline.shared.stopDetailPrefetching()
        }
        if currentSlotID != slot.id {
            currentSlotID = slot.id
            detailFailed = false
            isDetailReady = false
            detailInteraction.saveMessage = ""
            resolver.resolve(pageURL: slot.pageURL)
            imageView.setImageURL(slot.knownURL)
            RemoteImagePipeline.shared.prefetchDetailImages(library.upcomingKnownImageURLs)
        }

        counterLabel.stringValue = "\(slot.displayIndex) / \(max(item.imageCount, library.loadedImageSlots.count))"
        statusLabel.stringValue = detailStatusText
        statusChrome.isHidden = statusLabel.stringValue.isEmpty
        let showsFilmstrip = filmstripVisibility.isPresented
        updateFilmstripLayout(showsFilmstrip: showsFilmstrip)
        filmstripView.update(
            slots: library.loadedImageSlots,
            selectedIndex: library.selectedImageIndex,
            showsLoadingTile: library.prefetchPageURL != nil
        )
        if detailInteraction.resetToken != resetTokenSeen {
            resetTokenSeen = detailInteraction.resetToken
            imageView.resetZoom()
        }
    }

    private func updateFilmstripLayout(showsFilmstrip: Bool) {
        filmstripView.isHidden = !showsFilmstrip
        filmstripHeightConstraint?.constant = showsFilmstrip ? 112 : 0
        updateImageTopConstraint(showsFilmstrip: showsFilmstrip)
    }

    private func updateImageTopConstraint(showsFilmstrip: Bool) {
        let usesFullBleedTop = immersive.isImmersive && !showsFilmstrip
        imageTopSafeAreaConstraint?.isActive = !usesFullBleedTop
        imageTopFullBleedConstraint?.isActive = usesFullBleedTop
    }

    private var resetTokenSeen = UUID()

    private var detailStatusText: String {
        if detailFailed { return "解析失败" }
        switch detailInteraction.saveMessage {
        case "保存中", "已保存", "保存失败":
            return detailInteraction.saveMessage
        default:
            break
        }
        if !isDetailReady { return "解析中" }
        if library.prefetchPageURL != nil { return "预取下一页" }
        return ""
    }

    private func retryCurrentPage() {
        guard let slot = library.selectedSlot else { return }
        detailFailed = false
        isDetailReady = false
        resolver.resolve(pageURL: slot.pageURL, force: true)
        imageView.setImageURL(slot.knownURL)
        reloadDetail()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        WorkspaceKeyboardHandler.keyDown(
            event,
            context: WorkspaceKeyboardContext(
                stepSelection: { [weak self] delta in
                    self?.library.stepImage(delta)
                    return true
                },
                toggleImmersive: { [weak self] in
                    self?.immersive.toggle()
                    return true
                }
            )
        )
    }

    private var placeholderItem: GalleryItem {
        GalleryItem(
            id: "",
            section: .latest,
            kind: .gallery,
            title: "",
            rawTitle: "",
            subtitle: "",
            detailURL: URL(string: "https://www.4khd.com/")!,
            coverURL: nil,
            imageCount: 0,
            pageCount: 0,
            pageURLs: [],
            sampleImageURLs: []
        )
    }
}
