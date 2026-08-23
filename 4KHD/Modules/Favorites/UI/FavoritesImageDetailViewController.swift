import AppKit
import Observation

/// 收藏详情区:与 MissKon/4KHD 详情一致的大图查看区——
/// 缩放、上/下张、计数、状态、胶片条、沉浸模式、键盘导航。
@MainActor
final class FavoritesImageDetailViewController: NSViewController, WorkspaceFocusable {
    private let moduleStore: FavoritesModuleStore
    private let detailStore: FavoritesDetailStore
    private let immersive: ImmersiveController
    private let detailPane: WorkspaceDetailPaneController
    private let detailInteraction: FavoritesDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let onOpenRecommendation: (FavoriteSource, OnlineGalleryRecommendation) -> Void
    private let imageView = FavoritesZoomableImageView()
    private let recommendationsView = DetailRecommendationsView()
    private let filmstripView = FavoritesFilmstripView()
    private let emptyLabel = NSTextField(labelWithString: "没有可显示内容")
    private let previousButton = DetailNavigationButton(symbolName: "chevron.left", accessibilityDescription: "上一张")
    private let nextButton = DetailNavigationButton(symbolName: "chevron.right", accessibilityDescription: "下一张")
    private let counterChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let counterLabel = NSTextField(labelWithString: "")
    private let statusChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let statusLabel = NSTextField(labelWithString: "")
    private var filmstripHeightConstraint: NSLayoutConstraint?
    private var isObserving = false
    private var currentRecordIdentity: String?
    private var currentSlotID: FavoritesImageSlot.ID?
    private var currentImageURL: URL?
    private var isDetailReady = false
    private var detailFailed = false
    private var resetTokenSeen = UUID()
    private var hasAppeared = false
    private let reloadQueue = WorkspaceCoalescingQueue(name: "FavoritesDetail Reload", interval: 0.05, maxInterval: 0.1)

    init(
        moduleStore: FavoritesModuleStore,
        detailStore: FavoritesDetailStore,
        immersive: ImmersiveController,
        detailPane: WorkspaceDetailPaneController,
        detailInteraction: FavoritesDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController,
        onOpenRecommendation: @escaping (FavoriteSource, OnlineGalleryRecommendation) -> Void
    ) {
        self.moduleStore = moduleStore
        self.detailStore = detailStore
        self.immersive = immersive
        self.detailPane = detailPane
        self.detailInteraction = detailInteraction
        self.filmstripVisibility = filmstripVisibility
        self.onOpenRecommendation = onOpenRecommendation
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        nil
    }

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
            self?.detailFailed = false
            self?.reloadDetail()
        }
        filmstripView.onSelect = { [weak self] index in
            self?.detailStore.selectSlot(at: index)
        }
        recommendationsView.onOpenRecommendation = { [weak self] recommendation in
            guard let self, let source = self.detailStore.currentSource else { return }
            self.onOpenRecommendation(source, recommendation)
        }
        reloadDetail()
        observeState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasAppeared else { return }
        hasAppeared = true
        if let firstResponder = view.window?.firstResponder as? NSText, firstResponder.isEditable {
            return
        }
        view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
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

        for subview in [imageView, recommendationsView, emptyLabel, previousButton, nextButton, counterChrome, statusChrome, filmstripView] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // 初始高度 0:切换模块首帧不占位,reloadDetail 首次调用时再按全局状态(有动画地)展开。
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
            filmstripHeightConstraint,
        ])
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = moduleStore.selectedRecordID
            _ = detailStore.currentRecord?.id
            _ = detailStore.selectedSlotID
            _ = detailStore.imageSlots
            _ = detailStore.isResolving
            _ = detailStore.errorMessage
            _ = detailStore.recommendations
            _ = detailStore.contentMode
            _ = detailInteraction.resetToken
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
        let record = moduleStore.selectedRecord

        // 选中变化时重建 detail 状态。
        if record != detailStore.currentRecord {
            detailStore.prepare(record: record)
        }

        guard let record else {
            currentRecordIdentity = nil
            currentSlotID = nil
            currentImageURL = nil
            detailFailed = false
            imageView.setImageURL(nil)
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

        let source = FavoriteSource.source(for: record)
        imageView.requestConfigurator = source?.imageRequestConfigurator
        filmstripView.requestConfigurator = source?.imageRequestConfigurator

        // 打开详情后开始/恢复解析(resolve 幂等:在途任务、已全部解析、失败时均 no-op)。
        // 面板关闭会取消后续页预取,重开面板时由此恢复解析链。
        if shouldLoadDetailContent,
           detailStore.errorMessage == nil {
            detailStore.resolve()
        }

        guard shouldLoadDetailContent else {
            currentSlotID = nil
            currentImageURL = nil
            detailFailed = false
            imageView.setImageURL(nil)
            recommendationsView.isHidden = true
            RemoteImagePipeline.shared.stopDetailPrefetching()
            detailStore.cancelResolution()
            isDetailReady = false
            return
        }

        let slots = detailStore.imageSlots
        let resolutionFailed = detailStore.errorMessage != nil
            && detailStore.resolvedPageCount == 0
            && !detailStore.isResolving

        if slots.isEmpty || resolutionFailed {
            recommendationsView.isHidden = true
            if resolutionFailed {
                detailFailed = true
                imageView.isHidden = false
                imageView.showFailure { [weak self] in
                    self?.detailStore.retry()
                }
                emptyLabel.isHidden = true
            } else {
                imageView.isHidden = true
                emptyLabel.isHidden = false
            }
            previousButton.isHidden = true
            nextButton.isHidden = true
            counterChrome.isHidden = true
            statusChrome.isHidden = false
            statusLabel.stringValue = detailStore.isResolving ? "解析中..." : (detailStore.errorMessage ?? "")
            filmstripView.isHidden = true
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }

        recommendationsView.update(
            recommendations: detailStore.recommendations,
            requestConfigurator: source?.imageRequestConfigurator
        )
        if detailStore.contentMode == .recommendations {
            RemoteImagePipeline.shared.stopDetailPrefetching()
            imageView.isHidden = true
            recommendationsView.isHidden = false
            emptyLabel.isHidden = true
            previousButton.isHidden = false
            previousButton.isEnabled = detailStore.canStepBackward
            nextButton.isHidden = false
            nextButton.isEnabled = false
            counterChrome.isHidden = false
            counterLabel.stringValue = "推荐图集"
            statusChrome.isHidden = true
            updateFilmstripLayout(showsFilmstrip: false)
            return
        }

        detailFailed = false
        imageView.isHidden = false
        recommendationsView.isHidden = true
        emptyLabel.isHidden = true
        previousButton.isHidden = false
        nextButton.isHidden = false
        counterChrome.isHidden = false

        let selectedID = detailStore.selectedSlotID ?? slots.first?.id
        let selectedIndex = selectedID.flatMap { id in slots.firstIndex { $0.id == id } } ?? 0
        let selectedSlot = slots[selectedIndex]

        previousButton.isEnabled = detailStore.canStepBackward
        nextButton.isEnabled = detailStore.canStepForward

        let recordIdentity = "\(source?.rawValue ?? "unknown")|\(record.id)|\(record.detailURL)"
        if currentRecordIdentity != recordIdentity {
            currentRecordIdentity = recordIdentity
            currentSlotID = nil
            currentImageURL = nil
            detailInteraction.saveMessage = ""
            isDetailReady = false
            RemoteImagePipeline.shared.stopDetailPrefetching()
            // 解析期间先显示封面。
            if let coverURL = record.coverURL.flatMap(URL.init(string:)) {
                imageView.setImageURL(coverURL)
            }
        }
        if currentSlotID != selectedSlot.id || currentImageURL != selectedSlot.knownURL {
            let url = selectedSlot.knownURL
            currentSlotID = selectedSlot.id
            currentImageURL = url
            detailInteraction.saveMessage = ""
            if let url {
                imageView.setImageURL(url, preservesCurrentImageUntilLoaded: imageView.imageView.image != nil)
            }
            // 预取相邻图片,翻页更顺滑。
            let start = max(selectedIndex - 2, 0)
            let end = min(selectedIndex + 2, slots.count - 1)
            let adjacentURLs = slots[start ... end].compactMap { $0.knownURL }
            RemoteImagePipeline.shared.prefetchDetailImages(adjacentURLs)

            // 点中了占位 slot:按需加载其页。
            if selectedSlot.knownURL == nil {
                detailStore.ensurePageLoadedForSlot(at: selectedIndex)
            }
        }

        counterLabel.stringValue = "\(selectedSlot.displayIndex + 1) / \(slots.count)"
        updateSaveStatus()

        let showsFilmstrip = filmstripVisibility.isPresented && !slots.isEmpty
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
                Task { @MainActor [weak self] in
                    self?.filmstripView.isHidden = !showsFilmstrip
                }
            }
        } else {
            filmstripHeightConstraint?.constant = showsFilmstrip ? 112 : 0
            filmstripView.isHidden = !showsFilmstrip
        }
    }

    private var detailStatusText: String {
        if detailFailed { return "解析失败" }
        if let errorMessage = detailStore.errorMessage { return errorMessage }
        switch detailInteraction.saveMessage {
        case "保存中", "已保存", "保存失败":
            return detailInteraction.saveMessage
        default:
            break
        }
        if detailStore.isResolving {
            let pages = detailStore.resolvedPageCount
            let images = detailStore.resolvedImageCount
            if pages > 0 { return "解析中 (\(pages) 页, \(images) 张)" }
            return "解析中"
        }
        if !isDetailReady { return "解析中" }
        return ""
    }

    @objc func saveImage(_: Any?) {
        guard let url = currentImageURL else { return }
        let source = detailStore.currentRecord.flatMap(FavoriteSource.source(for:))
        detailInteraction.save(imageURL: url, filename: url.lastPathComponent, source: source)
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
        detailStore.stepSelection(-1)
    }

    @objc private func nextImage() {
        detailStore.stepSelection(1)
    }

    private func selectAdjacent(delta: Int) -> Bool {
        guard !detailStore.imageSlots.isEmpty else { return false }
        detailStore.stepSelection(delta)
        return true
    }
}
