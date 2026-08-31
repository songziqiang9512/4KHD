import AppKit
import Observation

@MainActor
final class MrdsImageDetailViewController: NSViewController, WorkspaceFocusable {
    private let store: MrdsGalleryStore
    private let immersive: ImmersiveController
    private let detailPane: WorkspaceDetailPaneController
    private let interaction: MrdsDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let onPlayVideo: (MrdsGalleryItem, URL) -> Void
    private let imageView = MrdsZoomableImageView()
    private let recommendationsView = DetailRecommendationsView()
    private let filmstripView = MrdsFilmstripView()
    private let emptyLabel = NSTextField(labelWithString: "选择一个图集")
    private let previousButton = DetailNavigationButton(symbolName: "chevron.left", accessibilityDescription: "上一张")
    private let nextButton = DetailNavigationButton(symbolName: "chevron.right", accessibilityDescription: "下一张")
    private let counterChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let counterLabel = NSTextField(labelWithString: "")
    private let playButton = NSButton(title: "播放视频", target: nil, action: nil)
    private var filmstripHeightConstraint: NSLayoutConstraint?
    private var saveVideoMenuItem: NSMenuItem?
    private var copyVideoSourceMenuItem: NSMenuItem?
    private var currentSlotID: MrdsImageSlot.ID?
    private var currentImageURL: URL?
    private var resetTokenSeen = UUID()
    private var isObserving = false
    private var isViewActive = false
    private let reloadQueue = WorkspaceCoalescingQueue(name: "Mrds Detail Reload", interval: 0.04, maxInterval: 0.1)

    init(
        store: MrdsGalleryStore,
        immersive: ImmersiveController,
        detailPane: WorkspaceDetailPaneController,
        interaction: MrdsDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController,
        onPlayVideo: @escaping (MrdsGalleryItem, URL) -> Void
    ) {
        self.store = store
        self.immersive = immersive
        self.detailPane = detailPane
        self.interaction = interaction
        self.filmstripVisibility = filmstripVisibility
        self.onPlayVideo = onPlayVideo
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let root = WorkspaceDetailRootView()
        root.keyHandler = { [weak self] event in self?.handleKeyDown(event) ?? false }
        view = root
        setupView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        filmstripView.onSelect = { [weak self] index in
            self?.store.selectImage(at: index)
        }
        filmstripView.onReachedEnd = { [weak self] in
            self?.store.ensureNextDetailPageLoaded()
        }
        recommendationsView.onOpenRecommendation = { [weak self] recommendation in
            self?.store.openRecommendation(recommendation)
        }
        reloadDetail()
        observeState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        isViewActive = true
        reloadDetail()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        isViewActive = false
        store.cancelDetailResolution()
        RemoteImagePipeline.shared.stopDetailPrefetching()
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

        counterLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        counterLabel.alignment = .center
        counterChrome.addSubview(counterLabel)
        emptyLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(retryFailure)))

        previousButton.target = self
        previousButton.action = #selector(previousImage)
        nextButton.target = self
        nextButton.action = #selector(nextImage)
        playButton.target = self
        playButton.action = #selector(playVideo)
        playButton.bezelStyle = .texturedRounded
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放视频")
        playButton.imagePosition = .imageLeading
        playButton.contentTintColor = .controlAccentColor
        configureVideoMenu()

        for subview in [
            imageView, recommendationsView, emptyLabel, previousButton, nextButton,
            counterChrome, playButton, filmstripView,
        ] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        let filmstripHeightConstraint = filmstripView.heightAnchor.constraint(equalToConstant: 0)
        self.filmstripHeightConstraint = filmstripHeightConstraint

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
            counterChrome.widthAnchor.constraint(greaterThanOrEqualTo: counterLabel.widthAnchor, constant: 16),
            counterLabel.leadingAnchor.constraint(equalTo: counterChrome.leadingAnchor, constant: 8),
            counterLabel.trailingAnchor.constraint(equalTo: counterChrome.trailingAnchor, constant: -8),
            counterLabel.centerYAnchor.constraint(equalTo: counterChrome.centerYAnchor),
            playButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playButton.bottomAnchor.constraint(equalTo: filmstripView.topAnchor, constant: -10),
            playButton.heightAnchor.constraint(equalToConstant: 28),
            filmstripView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filmstripView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filmstripView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            filmstripHeightConstraint,
        ])
    }

    private func configureVideoMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let saveItem = NSMenuItem(
            title: "保存视频为 MP4…",
            action: #selector(saveVideo),
            keyEquivalent: ""
        )
        saveItem.target = self
        saveItem.image = NSImage(systemSymbolName: "video.badge.arrow.down", accessibilityDescription: nil)
        saveItem.isEnabled = false
        menu.addItem(saveItem)
        menu.addItem(.separator())
        let copyItem = NSMenuItem(
            title: "拷贝影片源 URL",
            action: #selector(copyVideoSourceURL),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyItem.isEnabled = false
        menu.addItem(copyItem)
        playButton.menu = menu
        saveVideoMenuItem = saveItem
        copyVideoSourceMenuItem = copyItem
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = store.selectedItemID
            _ = store.selectedSlot?.id
            _ = store.imageSlots
            _ = store.selectedImageIndex
            _ = store.detailErrorMessage
            _ = store.videoURL
            _ = store.detailMetadata
            _ = store.recommendations
            _ = store.detailContentMode
            _ = store.isResolvingDetail
            _ = interaction.resetToken
            _ = detailPane.isPresented
            _ = immersive.isImmersive
            _ = filmstripVisibility.isPresented
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isObserving = false
                reloadQueue.add(id: "reload") { [weak self] in self?.reloadDetail() }
                observeState()
            }
        }
    }

    private func reloadDetail() {
        guard shouldLoadDetailContent else {
            store.cancelDetailResolution()
            RemoteImagePipeline.shared.stopDetailPrefetching()
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }
        store.resolveSelectedDetailIfNeeded()

        guard store.selectedItem != nil else {
            currentSlotID = nil
            currentImageURL = nil
            imageView.setImageURL(nil)
            imageView.isHidden = true
            recommendationsView.isHidden = true
            emptyLabel.stringValue = "选择一个图集"
            emptyLabel.isHidden = false
            emptyLabel.toolTip = nil
            previousButton.isHidden = true
            nextButton.isHidden = true
            counterChrome.isHidden = true
            playButton.isHidden = true
            saveVideoMenuItem?.isEnabled = false
            copyVideoSourceMenuItem?.isEnabled = false
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }

        recommendationsView.update(
            recommendations: store.recommendations,
            requestConfigurator: MrdsRequestFactory.configureImageRequest
        )
        if store.detailContentMode == .recommendations {
            imageView.isHidden = true
            recommendationsView.isHidden = false
            emptyLabel.isHidden = true
            previousButton.isHidden = false
            previousButton.isEnabled = store.canStepDetailBackward
            nextButton.isHidden = false
            nextButton.isEnabled = false
            counterChrome.isHidden = false
            counterLabel.stringValue = "推荐图集"
            playButton.isHidden = true
            saveVideoMenuItem?.isEnabled = false
            copyVideoSourceMenuItem?.isEnabled = false
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }

        guard let slot = store.selectedSlot else {
            let hasVideo = validatedVideoURL != nil
            currentSlotID = nil
            currentImageURL = nil
            imageView.setImageURL(nil)
            imageView.isHidden = true
            recommendationsView.isHidden = true
            emptyLabel.stringValue = store.isResolvingDetail ? "解析中…" : (store.detailErrorMessage ?? "没有可显示内容")
            emptyLabel.isHidden = false
            previousButton.isHidden = true
            nextButton.isHidden = true
            counterChrome.isHidden = true
            emptyLabel.toolTip = store.detailErrorMessage == nil ? nil : "点击重试解析"
            playButton.isHidden = !hasVideo
            saveVideoMenuItem?.isEnabled = hasVideo
            copyVideoSourceMenuItem?.isEnabled = hasVideo
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }

        imageView.isHidden = false
        recommendationsView.isHidden = true
        emptyLabel.isHidden = true
        previousButton.isHidden = false
        nextButton.isHidden = false
        counterChrome.isHidden = false
        previousButton.isEnabled = store.canStepDetailBackward
        nextButton.isEnabled = store.canStepDetailForward
        if currentSlotID != slot.id || currentImageURL != slot.knownURL {
            currentSlotID = slot.id
            currentImageURL = slot.knownURL
            imageView.setImageURL(slot.knownURL, preservesCurrentImageUntilLoaded: true)
            let start = max(store.selectedImageIndex - 2, 0)
            let end = min(store.selectedImageIndex + 2, store.imageSlots.count - 1)
            if start <= end {
                RemoteImagePipeline.shared.prefetchDetailImages(
                    store.imageSlots[start ... end].map(\.knownURL),
                    configureURLRequest: MrdsRequestFactory.configureImageRequest
                )
            }
        }

        let total = max(store.detailMetadata?.totalImages ?? 0, store.imageSlots.count)
        counterLabel.stringValue = "\(slot.displayIndex) / \(max(total, 1))"
        // 下载结果由统一的“下载任务”窗口负责呈现。详情画面中央不再
        // 常驻分类或保存状态，避免遮挡图片并与其他在线模块保持一致。
        emptyLabel.toolTip = nil
        let hasVideo = validatedVideoURL != nil
        playButton.isHidden = !hasVideo
        playButton.toolTip = hasVideo ? "播放；右键可保存视频或拷贝影片源 URL" : "该图集没有可播放视频"
        saveVideoMenuItem?.isEnabled = hasVideo
        copyVideoSourceMenuItem?.isEnabled = hasVideo

        let showsFilmstrip = filmstripVisibility.isPresented
            && (detailPane.isPresented || immersive.isImmersive)
            && !store.imageSlots.isEmpty
        updateFilmstripLayout(showsFilmstrip: showsFilmstrip)
        filmstripView.update(
            slots: store.imageSlots,
            selectedIndex: store.selectedImageIndex,
            showsLoadingTile: store.isResolvingDetail && !store.isDetailResolutionComplete
        )

        if resetTokenSeen != interaction.resetToken {
            resetTokenSeen = interaction.resetToken
            imageView.resetZoom()
        }
    }

    private func updateFilmstripLayout(showsFilmstrip: Bool) {
        let needsAnimation = filmstripView.isHidden == showsFilmstrip
        if needsAnimation {
            if showsFilmstrip { filmstripView.isHidden = false }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                filmstripHeightConstraint?.animator().constant = showsFilmstrip ? 112 : 0
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.filmstripView.isHidden = !showsFilmstrip
                }
            }
        } else {
            filmstripHeightConstraint?.constant = showsFilmstrip ? 112 : 0
            filmstripView.isHidden = !showsFilmstrip
        }
    }

    private var shouldLoadDetailContent: Bool {
        isViewActive && (detailPane.isPresented || immersive.isImmersive)
    }

    private var validatedVideoURL: URL? {
        guard let url = store.videoURL,
              url.pathExtension.lowercased() == "m3u8",
              OnlineSourcePolicy.allows(url, source: .mrds, resource: .media) else { return nil }
        return url
    }

    @objc private func previousImage() {
        store.stepImage(-1)
    }

    @objc private func nextImage() {
        store.stepImage(1)
    }

    @objc private func playVideo() {
        guard store.detailContentMode == .image,
              let item = store.selectedItem,
              let url = validatedVideoURL else { return }
        onPlayVideo(item, url)
    }

    @objc private func saveVideo() {
        guard store.detailContentMode == .image,
              let item = store.selectedItem,
              let url = validatedVideoURL else { return }
        interaction.saveVideo(item: item, sourceURL: url)
    }

    @objc private func copyVideoSourceURL() {
        guard store.detailContentMode == .image,
              let url = validatedVideoURL else { return }
        WorkspaceCurrentReference.web(url).writeToPasteboard()
    }

    @objc private func retryFailure() {
        guard store.detailErrorMessage != nil else { return }
        store.retryLastFailure()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            store.stepImage(-1)
            return true
        case 124:
            store.stepImage(1)
            return true
        case 49 where store.detailContentMode == .image && validatedVideoURL != nil:
            playVideo()
            return true
        default:
            return false
        }
    }
}
