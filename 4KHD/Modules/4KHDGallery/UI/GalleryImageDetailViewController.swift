import AppKit
import Observation

@MainActor
final class GalleryImageDetailViewController: NSViewController, WorkspaceFocusable {
    private let library: FourKHDGalleryStore
    private let immersive: ImmersiveController
    private let detailPane: WorkspaceDetailPaneController
    private let detailInteraction: GalleryDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let resolver = DetailImageResolver()
    private let imageView = GalleryZoomableImageView()
    private let recommendationsView = DetailRecommendationsView()
    private let filmstripView = GalleryFilmstripView()
    private let emptyLabel = NSTextField(labelWithString: "没有可显示内容")
    private let previousButton = DetailNavigationButton(symbolName: "chevron.left", accessibilityDescription: "上一张")
    private let nextButton = DetailNavigationButton(symbolName: "chevron.right", accessibilityDescription: "下一张")
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
    private var currentImageURL: URL?
    private var detailFailed = false
    private var isDetailReady = false
    private let reloadQueue = WorkspaceCoalescingQueue(
        name: "GalleryDetail Reload",
        interval: 0.05,
        maxInterval: 0.1
    )

    init(
        library: FourKHDGalleryStore,
        immersive: ImmersiveController,
        detailPane: WorkspaceDetailPaneController,
        detailInteraction: GalleryDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController
    ) {
        self.library = library
        self.immersive = immersive
        self.detailPane = detailPane
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
        recommendationsView.onOpenRecommendation = { [weak self] recommendation in
            self?.library.openRecommendation(recommendation)
        }
        reloadDetail()
        observeState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasAppeared else { return }
        hasAppeared = true
        if let firstResponder = view.window?.firstResponder as? NSText,
           firstResponder.isEditable {
            return
        }
        view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
    }
    private var hasAppeared = false

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

        previousButton.target = self
        previousButton.action = #selector(previousImage)
        nextButton.target = self
        nextButton.action = #selector(nextImage)

        for subview in [imageView, recommendationsView, emptyLabel, previousButton, nextButton, counterChrome, statusChrome, filmstripView] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // 初始高度 0:切换模块首帧不占位,reloadDetail 首次调用时再按全局状态(有动画地)展开。
        let filmstripHeightConstraint = filmstripView.heightAnchor.constraint(equalToConstant: 0)
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

            recommendationsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            recommendationsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            recommendationsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            recommendationsView.bottomAnchor.constraint(equalTo: filmstripView.topAnchor),

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
            _ = library.selectedItem?.id
            _ = library.selectedSlot?.id
            _ = library.selectedImageIndex
            _ = library.loadedImageSlots
            _ = library.prefetchPageURL
            _ = library.detailErrorMessage
            _ = library.recommendations
            _ = library.detailContentMode
            _ = library.isFavorite(library.selectedItem ?? placeholderItem)
            _ = immersive.isImmersive
            _ = detailPane.isPresented
            _ = detailInteraction.resetToken
            _ = filmstripVisibility.isPresented
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.reloadQueue.add(id: "reload") { [weak self] in
                    self?.reloadDetail()
                }
                self.observeState()
            }
        }
        observeSaveMessage()
    }

    /// 保存状态变化(保存中/成功/失败)只刷新状态标签,不走完整 reload 路径。
    private func observeSaveMessage() {
        withObservationTracking {
            _ = detailInteraction.saveMessage
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateSaveStatus()
                self.observeSaveMessage()
            }
        }
    }

    private func updateSaveStatus() {
        statusLabel.stringValue = detailStatusText
        statusChrome.isHidden = statusLabel.stringValue.isEmpty
    }

    private func reloadDetail() {
        guard let item = library.selectedItem, let slot = library.selectedSlot else {
            currentItemID = nil
            currentSlotID = nil
            currentImageURL = nil
            resolver.cancel()
            library.cancelOutstandingDetailPageLoads()
            imageView.setImageURL(nil)
            RemoteImagePipeline.shared.stopDetailPrefetching()
            imageView.isHidden = true
            recommendationsView.isHidden = true
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
            resolver.cancel()
            library.cancelOutstandingDetailPageLoads()
            imageView.setImageURL(nil)
            recommendationsView.isHidden = true
            RemoteImagePipeline.shared.stopDetailPrefetching()
            detailFailed = false
            isDetailReady = false
            return
        }

        recommendationsView.update(
            recommendations: library.recommendations,
            requestConfigurator: GalleryRequestFactory.configureImageRequest
        )
        if library.detailContentMode == .recommendations {
            imageView.isHidden = true
            recommendationsView.isHidden = false
            emptyLabel.isHidden = true
            previousButton.isHidden = false
            previousButton.isEnabled = library.canStepDetailBackward
            nextButton.isHidden = false
            nextButton.isEnabled = false
            counterChrome.isHidden = false
            counterLabel.stringValue = "推荐图集"
            statusChrome.isHidden = true
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }

        imageView.isHidden = false
        recommendationsView.isHidden = true
        emptyLabel.isHidden = true
        previousButton.isHidden = false
        nextButton.isHidden = false
        previousButton.isEnabled = library.canStepDetailBackward
        nextButton.isEnabled = library.canStepDetailForward
        counterChrome.isHidden = false

        if currentItemID != item.id {
            currentItemID = item.id
            detailInteraction.saveMessage = ""
            RemoteImagePipeline.shared.stopDetailPrefetching()
        }
        if currentSlotID != slot.id || currentImageURL != slot.knownURL {
            let shouldPreserveCurrentImage = currentSlotID == slot.id && currentImageURL != nil && slot.knownURL != nil
            currentSlotID = slot.id
            currentImageURL = slot.knownURL
            detailFailed = false
            isDetailReady = false
            detailInteraction.saveMessage = ""
            resolver.resolve(pageURL: slot.pageURL)
            imageView.setImageURL(slot.knownURL, preservesCurrentImageUntilLoaded: shouldPreserveCurrentImage)
            RemoteImagePipeline.shared.prefetchDetailImages(library.upcomingKnownImageURLs)
        }

        counterLabel.stringValue = "\(slot.displayIndex) / \(max(item.imageCount, library.loadedImageSlots.count))"
        updateSaveStatus()
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
                updateImageTopConstraint(showsFilmstrip: showsFilmstrip)
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.filmstripView.isHidden = !showsFilmstrip
                }
            }
        } else {
            filmstripHeightConstraint?.constant = showsFilmstrip ? 112 : 0
            updateImageTopConstraint(showsFilmstrip: showsFilmstrip)
            filmstripView.isHidden = !showsFilmstrip
        }
    }

    private func updateImageTopConstraint(showsFilmstrip: Bool) {
        let usesFullBleedTop = immersive.isImmersive && !showsFilmstrip
        imageTopSafeAreaConstraint?.isActive = !usesFullBleedTop
        imageTopFullBleedConstraint?.isActive = usesFullBleedTop
    }

    private var resetTokenSeen = UUID()

    private var detailStatusText: String {
        if detailFailed { return "解析失败" }
        if let errorMessage = library.detailErrorMessage { return errorMessage }
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

    @objc private func previousImage() {
        library.stepImage(-1)
    }

    @objc private func nextImage() {
        library.stepImage(1)
    }

    /// 观察注册时用于 isFavorite 兜底的占位 item:纯值 struct,一次性常量即可。
    private let placeholderItem = GalleryItem(
        id: "",
        section: .latest,
        kind: .gallery,
        title: "",
        rawTitle: "",
        subtitle: "",
        detailURL: URL(string: "https://www.4khd.com/")!,
        coverURL: nil,
        coverAspectRatio: nil,
        imageCount: 0,
        pageCount: 0,
        pageURLs: [],
        sampleImageURLs: []
    )
}
