import AppKit
import Observation

@MainActor
final class GalleryImageDetailViewController: NSViewController {
    private let library: FourKHDGalleryStore
    private let immersive: ImmersiveController
    private let detailInteraction: GalleryDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let resolver = DetailImageResolver()
    private let imageView = GalleryZoomableImageView()
    private let filmstripView = GalleryFilmstripView()
    private let emptyLabel = NSTextField(labelWithString: "没有可显示内容")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let counterLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let toolStack = NSStackView()
    private var filmstripHeightConstraint: NSLayoutConstraint?
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

    private func setupView() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        emptyLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        setupStepButton(previousButton, imageName: "chevron.left", action: #selector(previousImage))
        setupStepButton(nextButton, imageName: "chevron.right", action: #selector(nextImage))

        counterLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        counterLabel.textColor = .labelColor
        counterLabel.alignment = .center
        counterLabel.wantsLayer = true
        counterLabel.layer?.cornerRadius = 11
        counterLabel.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.78).cgColor

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.alignment = .center
        statusLabel.wantsLayer = true
        statusLabel.layer?.cornerRadius = 11
        statusLabel.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.78).cgColor

        toolStack.orientation = .horizontal
        toolStack.alignment = .centerY
        toolStack.spacing = 6
        for item in makeToolButtons() {
            toolStack.addArrangedSubview(item)
        }

        for subview in [imageView, emptyLabel, previousButton, nextButton, counterLabel, statusLabel, toolStack, filmstripView] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }

        let filmstripHeightConstraint = filmstripView.heightAnchor.constraint(equalToConstant: 112)
        self.filmstripHeightConstraint = filmstripHeightConstraint

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            previousButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            previousButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 36),
            previousButton.heightAnchor.constraint(equalToConstant: 36),

            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            nextButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 36),
            nextButton.heightAnchor.constraint(equalToConstant: 36),

            counterLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            counterLabel.bottomAnchor.constraint(equalTo: filmstripView.topAnchor, constant: -12),
            counterLabel.heightAnchor.constraint(equalToConstant: 24),
            counterLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: filmstripView.topAnchor, constant: -12),
            statusLabel.heightAnchor.constraint(equalToConstant: 24),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 78),

            toolStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            toolStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            filmstripView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filmstripView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filmstripView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            filmstripHeightConstraint
        ])
    }

    private func setupStepButton(_ button: NSButton, imageName: String, action: Selector) {
        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.target = self
        button.action = action
    }

    private func makeToolButtons() -> [NSButton] {
        [
            makeToolButton("bookmark", "收藏", #selector(toggleFavorite)),
            makeToolButton("1.magnifyingglass", "实际大小", #selector(resetZoom)),
            makeToolButton("arrow.up.left.and.arrow.down.right", "沉浸模式", #selector(toggleImmersive)),
            makeToolButton("rectangle.bottomthird.inset.filled", "缩略图", #selector(toggleFilmstrip)),
            makeToolButton("safari", "原网页", #selector(openOriginalPage)),
            makeToolButton("square.and.arrow.down", "保存", #selector(saveImage))
        ]
    }

    private func makeToolButton(_ systemName: String, _ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: systemName, accessibilityDescription: title) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = title
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
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
            previousButton.isHidden = true
            nextButton.isHidden = true
            counterLabel.isHidden = true
            statusLabel.isHidden = true
            filmstripView.isHidden = true
            return
        }

        imageView.isHidden = false
        emptyLabel.isHidden = true
        previousButton.isHidden = false
        nextButton.isHidden = false
        counterLabel.isHidden = false
        previousButton.isEnabled = library.selectedImageIndex > 0
        nextButton.isEnabled = true

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
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
        toolStack.isHidden = !immersive.isImmersive
        let showsFilmstrip = filmstripVisibility.isPresented
        filmstripView.isHidden = !showsFilmstrip
        filmstripHeightConstraint?.constant = showsFilmstrip ? 112 : 0
        filmstripView.update(
            slots: library.loadedImageSlots,
            selectedIndex: library.selectedImageIndex,
            showsLoadingTile: library.prefetchPageURL != nil
        )
        if detailInteraction.resetToken != resetTokenSeen {
            resetTokenSeen = detailInteraction.resetToken
            imageView.resetZoom()
        }
        updateToolButtons(item: item)
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

    private func updateToolButtons(item: GalleryItem) {
        guard toolStack.arrangedSubviews.count >= 6 else { return }
        if let favoriteButton = toolStack.arrangedSubviews[0] as? NSButton {
            let imageName = library.isFavorite(item) ? "bookmark.fill" : "bookmark"
            favoriteButton.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
            favoriteButton.toolTip = library.isFavorite(item) ? "取消收藏" : "收藏"
        }
        if let immersiveButton = toolStack.arrangedSubviews[2] as? NSButton {
            let imageName = immersive.isImmersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            immersiveButton.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        }
        if let filmstripButton = toolStack.arrangedSubviews[3] as? NSButton {
            let imageName = filmstripVisibility.isPresented ? "rectangle.bottomthird.inset.filled" : "rectangle"
            filmstripButton.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        }
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
        let noModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        guard noModifiers else { return false }
        switch event.keyCode {
        case 123, 126:
            library.stepImage(-1)
            return true
        case 124, 125, 49:
            library.stepImage(1)
            return true
        case 3:
            immersive.toggle()
            return true
        default:
            return false
        }
    }

    @objc private func previousImage() {
        library.stepImage(-1)
    }

    @objc private func nextImage() {
        library.stepImage(1)
    }

    @objc private func toggleFavorite() {
        guard let item = library.selectedItem else { return }
        library.toggleFavorite(for: item)
        reloadDetail()
    }

    @objc private func resetZoom() {
        detailInteraction.resetZoom()
    }

    @objc private func toggleImmersive() {
        immersive.toggle()
        reloadDetail()
    }

    @objc private func toggleFilmstrip() {
        filmstripVisibility.toggle()
        reloadDetail()
    }

    @objc private func openOriginalPage() {
        guard let item = library.selectedItem else { return }
        NSWorkspace.shared.open(item.detailURL)
    }

    @objc private func saveImage() {
        guard let item = library.selectedItem, let slot = library.selectedSlot else { return }
        detailInteraction.save(item: item, slot: slot)
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

final class GalleryImageDetailRootView: NSView {
    var keyHandler: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}
