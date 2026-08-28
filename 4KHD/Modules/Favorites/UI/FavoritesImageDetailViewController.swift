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
    private let onOpenSecondaryMetadata: (FavoriteRecord, FavoriteDetailMetadata) -> Bool
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
    private let playButton = NSButton(title: "播放视频", target: nil, action: nil)
    private let externalActionChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let externalActionButton: NSButton = {
        let button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .inline
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "打开外部资源")
        button.imagePosition = .imageLeading
        return button
    }()
    private let metadataChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let metadataLabel = NSTextField(labelWithString: "")
    private let sourceChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let sourceButton: NSButton = {
        let button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .inline
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "打开来源")
        button.imagePosition = .imageLeading
        return button
    }()
    private let secondaryChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let secondaryButton: NSButton = {
        let button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .inline
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "person.circle", accessibilityDescription: "作者")
        button.imagePosition = .imageLeading
        return button
    }()
    private let desktopButton: NSButton = {
        let image = NSImage(
            systemSymbolName: "photo.on.rectangle",
            accessibilityDescription: "设为桌面壁纸"
        ) ?? NSImage(size: NSSize(width: 16, height: 16))
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.toolTip = "设为桌面壁纸"
        return button
    }()
    private var filmstripHeightConstraint: NSLayoutConstraint?
    private var isObserving = false
    private var isObservingSaveMessage = false
    private var currentRecordIdentity: String?
    private var currentSlotID: FavoritesImageSlot.ID?
    private var currentImageURL: URL?
    private var isDetailReady = false
    private var detailFailed = false
    private var resetTokenSeen = UUID()
    private var hasAppeared = false
    private var isViewActive = false
    private var saveVideoMenuItem: NSMenuItem?
    private var copyVideoSourceMenuItem: NSMenuItem?
    private var pendingDesktopWallpaperRecordIdentity: FavoritesModuleStore.SelectionIdentity?
    private let reloadQueue = WorkspaceCoalescingQueue(name: "FavoritesDetail Reload", interval: 0.05, maxInterval: 0.1)

    init(
        moduleStore: FavoritesModuleStore,
        detailStore: FavoritesDetailStore,
        immersive: ImmersiveController,
        detailPane: WorkspaceDetailPaneController,
        detailInteraction: FavoritesDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController,
        onOpenSecondaryMetadata: @escaping (FavoriteRecord, FavoriteDetailMetadata) -> Bool,
        onOpenRecommendation: @escaping (FavoriteSource, OnlineGalleryRecommendation) -> Void
    ) {
        self.moduleStore = moduleStore
        self.detailStore = detailStore
        self.immersive = immersive
        self.detailPane = detailPane
        self.detailInteraction = detailInteraction
        self.filmstripVisibility = filmstripVisibility
        self.onOpenSecondaryMetadata = onOpenSecondaryMetadata
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
        filmstripView.onReachedEnd = { [weak self] in
            guard let self, !self.detailStore.imageSlots.isEmpty else { return }
            self.detailStore.ensureNextDetailPageLoadedIfApproachingEnd(
                from: self.detailStore.imageSlots.count - 1
            )
        }
        recommendationsView.onOpenRecommendation = { [weak self] recommendation in
            guard let self, let source = self.detailStore.currentSource else { return }
            self.onOpenRecommendation(source, recommendation)
        }
        reloadDetail()
        observeState()
        observeSaveMessage()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        isViewActive = true
        reloadDetail()
        guard !hasAppeared else { return }
        hasAppeared = true
        if let firstResponder = view.window?.firstResponder as? NSText, firstResponder.isEditable {
            return
        }
        view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        isViewActive = false
        detailStore.cancelResolution()
        RemoteImagePipeline.shared.stopDetailPrefetching()
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
        statusChrome.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(retryFailure)))

        playButton.target = self
        playButton.action = #selector(playVideo)
        playButton.bezelStyle = .texturedRounded
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放视频")
        playButton.imagePosition = .imageLeading
        playButton.contentTintColor = .controlAccentColor
        configureVideoMenu()

        externalActionButton.target = self
        externalActionButton.action = #selector(openExternalAction)
        externalActionChrome.addSubview(externalActionButton)

        metadataLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        metadataLabel.textColor = .labelColor
        metadataLabel.alignment = .center
        metadataLabel.maximumNumberOfLines = 3
        metadataLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        metadataChrome.addSubview(metadataLabel)

        sourceButton.target = self
        sourceButton.action = #selector(openMetadataSource)
        sourceChrome.addSubview(sourceButton)

        secondaryButton.target = self
        secondaryButton.action = #selector(openMetadataSecondarySource)
        secondaryChrome.addSubview(secondaryButton)

        previousButton.target = self
        previousButton.action = #selector(previousImage)
        nextButton.target = self
        nextButton.action = #selector(nextImage)
        desktopButton.target = self
        desktopButton.action = #selector(setAsDesktopWallpaper)

        for subview in [
            imageView, recommendationsView, emptyLabel, previousButton, nextButton,
            counterChrome, statusChrome, metadataChrome, sourceChrome, secondaryChrome,
            desktopButton, playButton, externalActionChrome, filmstripView,
        ] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceButton.translatesAutoresizingMaskIntoConstraints = false
        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        externalActionButton.translatesAutoresizingMaskIntoConstraints = false

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

            metadataChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            metadataChrome.bottomAnchor.constraint(equalTo: sourceChrome.topAnchor, constant: -4),
            metadataChrome.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            metadataChrome.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            metadataChrome.widthAnchor.constraint(greaterThanOrEqualTo: metadataLabel.widthAnchor, constant: 20),
            metadataLabel.leadingAnchor.constraint(equalTo: metadataChrome.leadingAnchor, constant: 10),
            metadataLabel.trailingAnchor.constraint(equalTo: metadataChrome.trailingAnchor, constant: -10),
            metadataLabel.centerYAnchor.constraint(equalTo: metadataChrome.centerYAnchor),

            sourceChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sourceChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            sourceChrome.heightAnchor.constraint(equalToConstant: 24),
            sourceButton.leadingAnchor.constraint(equalTo: sourceChrome.leadingAnchor, constant: 8),
            sourceButton.trailingAnchor.constraint(equalTo: sourceChrome.trailingAnchor, constant: -8),
            sourceButton.centerYAnchor.constraint(equalTo: sourceChrome.centerYAnchor),

            secondaryChrome.leadingAnchor.constraint(equalTo: sourceChrome.trailingAnchor, constant: 6),
            secondaryChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            secondaryChrome.heightAnchor.constraint(equalToConstant: 24),
            secondaryButton.leadingAnchor.constraint(equalTo: secondaryChrome.leadingAnchor, constant: 8),
            secondaryButton.trailingAnchor.constraint(equalTo: secondaryChrome.trailingAnchor, constant: -8),
            secondaryButton.centerYAnchor.constraint(equalTo: secondaryChrome.centerYAnchor),

            desktopButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            desktopButton.bottomAnchor.constraint(equalTo: sourceChrome.topAnchor, constant: -6),
            desktopButton.widthAnchor.constraint(equalToConstant: 28),
            desktopButton.heightAnchor.constraint(equalToConstant: 28),

            playButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playButton.bottomAnchor.constraint(equalTo: statusChrome.topAnchor, constant: -6),
            playButton.heightAnchor.constraint(equalToConstant: 28),

            externalActionChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            externalActionChrome.bottomAnchor.constraint(equalTo: counterChrome.topAnchor, constant: -6),
            externalActionChrome.heightAnchor.constraint(equalToConstant: 24),
            externalActionButton.leadingAnchor.constraint(equalTo: externalActionChrome.leadingAnchor, constant: 8),
            externalActionButton.trailingAnchor.constraint(equalTo: externalActionChrome.trailingAnchor, constant: -8),
            externalActionButton.centerYAnchor.constraint(equalTo: externalActionChrome.centerYAnchor),

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
            _ = moduleStore.visibleRecords
            _ = moduleStore.selectedRecordIdentity
            _ = moduleStore.selectedRecord
            _ = detailStore.currentRecord?.id
            _ = detailStore.selectedSlotID
            _ = detailStore.imageSlots
            _ = detailStore.isResolving
            _ = detailStore.errorMessage
            _ = detailStore.recommendations
            _ = detailStore.detailMetadata
            _ = detailStore.videoURL
            _ = detailStore.externalAction
            _ = detailStore.isResolutionComplete
            _ = detailStore.navigationMode
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
    }

    /// 保存状态变化(保存中/成功/失败)只刷新状态标签,不走完整 reload 路径。
    private func observeSaveMessage() {
        guard !isObservingSaveMessage else { return }
        isObservingSaveMessage = true
        withObservationTracking {
            _ = detailInteraction.saveMessage
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingSaveMessage = false
                self.updateSaveStatus()
                self.observeSaveMessage()
            }
        }
    }

    private func updateSaveStatus() {
        statusLabel.stringValue = detailStatusText
        statusChrome.isHidden = statusLabel.stringValue.isEmpty
        statusChrome.toolTip = detailStore.errorMessage == nil ? nil : "点击重试解析"
    }

    private func reloadDetail() {
        moduleStore.reconcileSelection()
        let record = moduleStore.selectedRecord
        hideMetadataPresentation()
        hideVideoPresentation()
        hideExternalActionPresentation()

        // 选中变化时重建 detail 状态。
        if record != detailStore.currentRecord {
            pendingDesktopWallpaperRecordIdentity = nil
            detailInteraction.invalidateSaveOperation()
            detailStore.prepare(record: record)
        }

        guard let record else {
            currentRecordIdentity = nil
            pendingDesktopWallpaperRecordIdentity = nil
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
                } openOriginal: {
                    guard let url = URL(string: record.detailURL) else { return }
                    NSWorkspace.shared.open(url)
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
            statusChrome.toolTip = detailStore.errorMessage == nil ? nil : "点击重试解析"
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
            previousButton.isEnabled = canStepDetailBackward
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

        previousButton.isEnabled = canStepDetailBackward
        nextButton.isEnabled = canStepDetailForward

        let recordIdentity = moduleStore.selectionIdentity(for: record)
        if currentRecordIdentity != recordIdentity {
            currentRecordIdentity = recordIdentity
            currentSlotID = nil
            currentImageURL = nil
            isDetailReady = false
            RemoteImagePipeline.shared.stopDetailPrefetching()
            // 解析期间先显示封面。
            if let coverURL = source?.validatedCoverURL(for: record) {
                imageView.setImageURL(coverURL)
            } else {
                imageView.setImageURL(nil)
            }
        }
        if currentSlotID != selectedSlot.id || currentImageURL != selectedSlot.knownURL {
            let url = selectedSlot.knownURL
            currentSlotID = selectedSlot.id
            currentImageURL = url
            detailInteraction.saveMessage = ""
            if let url {
                imageView.setImageURL(url, preservesCurrentImageUntilLoaded: imageView.imageView.image != nil)
            } else {
                isDetailReady = false
                imageView.setImageURL(nil)
            }
            // 预取相邻图片,翻页更顺滑。
            let start = max(selectedIndex - 2, 0)
            let end = min(selectedIndex + 2, slots.count - 1)
            let adjacentURLs = slots[start ... end].compactMap { $0.knownURL }
            RemoteImagePipeline.shared.prefetchDetailImages(
                adjacentURLs,
                configureURLRequest: source?.imageRequestConfigurator
            )

            // 点中了占位 slot:按需加载其页。
            if selectedSlot.knownURL == nil {
                detailStore.ensurePageLoadedForSlot(at: selectedIndex)
            }
        }

        let metadata = detailStore.detailMetadata
        counterChrome.isHidden = metadata != nil
        counterLabel.stringValue = "\(selectedSlot.displayIndex + 1) / \(slots.count)"
        updateMetadataPresentation(metadata, hasResolvedOriginal: detailStore.resolvedPageCount > 0)
        updateVideoPresentation()
        updateExternalActionPresentation()
        completePendingDesktopWallpaperIfPossible()
        updateSaveStatus()

        let showsFilmstrip = filmstripVisibility.isPresented && !slots.isEmpty && metadata == nil
        updateFilmstripLayout(showsFilmstrip: showsFilmstrip)
        filmstripView.update(
            slots: slots,
            selectedSlotID: selectedSlot.id,
            showsLoadingTile: detailStore.isResolving && !detailStore.isResolutionComplete
        )

        if detailInteraction.resetToken != resetTokenSeen {
            resetTokenSeen = detailInteraction.resetToken
            imageView.resetZoom()
        }
    }

    private func hideMetadataPresentation() {
        metadataChrome.isHidden = true
        sourceChrome.isHidden = true
        secondaryChrome.isHidden = true
        desktopButton.isHidden = true
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

    private func hideVideoPresentation() {
        playButton.isHidden = true
        saveVideoMenuItem?.isEnabled = false
        copyVideoSourceMenuItem?.isEnabled = false
    }

    private func hideExternalActionPresentation() {
        externalActionChrome.isHidden = true
        externalActionButton.title = ""
        externalActionButton.toolTip = nil
    }

    private func updateVideoPresentation() {
        let canPlay = detailStore.canPlayVideo
        playButton.isHidden = !canPlay
        playButton.toolTip = canPlay ? "播放；右键可保存视频或拷贝影片源 URL" : "该图集没有可播放视频"
        saveVideoMenuItem?.isEnabled = detailStore.canSaveVideo
        copyVideoSourceMenuItem?.isEnabled = canPlay
    }

    private func updateExternalActionPresentation() {
        guard let action = detailStore.externalAction else { return }
        externalActionButton.title = action.title
        externalActionButton.toolTip = action.url.absoluteString
        externalActionChrome.isHidden = false
    }

    private func updateMetadataPresentation(
        _ metadata: FavoriteDetailMetadata?,
        hasResolvedOriginal: Bool
    ) {
        guard let metadata else { return }
        metadataLabel.stringValue = [metadata.title, metadata.detailText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        metadataChrome.isHidden = metadataLabel.stringValue.isEmpty

        sourceButton.title = metadata.sourceTitle
        sourceButton.toolTip = metadata.sourceURL.absoluteString
        sourceChrome.isHidden = false

        if let title = metadata.secondaryTitle, let url = metadata.secondaryURL {
            secondaryButton.title = title
            secondaryButton.toolTip = url.absoluteString
            secondaryChrome.isHidden = false
        }

        desktopButton.isHidden = !metadata.supportsDesktopWallpaper
        desktopButton.isEnabled = metadata.supportsDesktopWallpaper
        desktopButton.toolTip = hasResolvedOriginal ? "设为桌面壁纸" : "正在获取原图"
    }

    private var shouldLoadDetailContent: Bool {
        isViewActive && (detailPane.isPresented || immersive.isImmersive)
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
        if let currentRecord = detailStore.currentRecord,
           pendingDesktopWallpaperRecordIdentity == moduleStore.selectionIdentity(for: currentRecord) {
            return "正在获取原图"
        }
        switch detailInteraction.saveMessage {
        case "保存中", "已保存", "保存失败", "下载中", "下载失败", "已设为桌面壁纸":
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

    @objc private func openMetadataSource() {
        guard let url = detailStore.detailMetadata?.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openExternalAction() {
        guard let url = detailStore.externalAction?.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openMetadataSecondarySource() {
        guard let record = detailStore.currentRecord,
              let metadata = detailStore.detailMetadata,
              let url = metadata.secondaryURL else { return }
        if onOpenSecondaryMetadata(record, metadata) { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func setAsDesktopWallpaper() {
        guard detailStore.detailMetadata?.supportsDesktopWallpaper == true,
              let record = detailStore.currentRecord else { return }
        guard detailStore.resolvedPageCount > 0,
              detailStore.hasResolvedSelectedImage,
              let imageURL = currentImageURL else {
            pendingDesktopWallpaperRecordIdentity = moduleStore.selectionIdentity(for: record)
            detailStore.resolve()
            updateSaveStatus()
            return
        }
        pendingDesktopWallpaperRecordIdentity = nil
        let source = detailStore.currentRecord.flatMap(FavoriteSource.source(for:))
        detailInteraction.setAsDesktopWallpaper(
            imageURL: imageURL,
            filename: imageURL.lastPathComponent,
            source: source
        )
    }

    private func completePendingDesktopWallpaperIfPossible() {
        guard let currentRecord = detailStore.currentRecord,
              pendingDesktopWallpaperRecordIdentity == moduleStore.selectionIdentity(for: currentRecord),
              detailStore.detailMetadata?.supportsDesktopWallpaper == true,
              detailStore.resolvedPageCount > 0,
              detailStore.hasResolvedSelectedImage,
              let imageURL = currentImageURL else { return }
        pendingDesktopWallpaperRecordIdentity = nil
        let source = detailStore.currentRecord.flatMap(FavoriteSource.source(for:))
        detailInteraction.setAsDesktopWallpaper(
            imageURL: imageURL,
            filename: imageURL.lastPathComponent,
            source: source
        )
    }

    @objc func saveImage(_: Any?) {
        guard let url = currentImageURL else { return }
        let source = detailStore.currentRecord.flatMap(FavoriteSource.source(for:))
        detailInteraction.save(imageURL: url, filename: url.lastPathComponent, source: source)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 49, detailStore.canPlayVideo {
            playVideo()
            return true
        }
        return WorkspaceKeyboardHandler.keyDown(
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
        _ = stepDetail(-1)
    }

    @objc private func nextImage() {
        _ = stepDetail(1)
    }

    @objc private func playVideo() {
        detailStore.playVideo()
    }

    @objc private func saveVideo() {
        guard detailStore.canSaveVideo else { return }
        detailStore.saveVideoAsMP4()
    }

    @objc private func retryFailure() {
        guard detailStore.errorMessage != nil else { return }
        detailStore.retry()
    }

    @objc private func copyVideoSourceURL() {
        guard detailStore.canPlayVideo, let url = detailStore.videoURL else { return }
        WorkspaceCurrentReference.web(url).writeToPasteboard()
    }

    private func selectAdjacent(delta: Int) -> Bool {
        stepDetail(delta)
    }

    private var canStepDetailBackward: Bool {
        guard let record = detailStore.currentRecord else { return false }
        switch detailStore.navigationMode {
        case .images:
            return detailStore.canStepBackward
        case .sourceRecords:
            return moduleStore.canStepSourceRecord(from: record, delta: -1)
        }
    }

    private var canStepDetailForward: Bool {
        guard let record = detailStore.currentRecord else { return false }
        switch detailStore.navigationMode {
        case .images:
            return detailStore.canStepForward
        case .sourceRecords:
            return moduleStore.canStepSourceRecord(from: record, delta: 1)
        }
    }

    @discardableResult
    private func stepDetail(_ delta: Int) -> Bool {
        guard let record = detailStore.currentRecord, delta != 0 else { return false }
        switch detailStore.navigationMode {
        case .images:
            guard !detailStore.imageSlots.isEmpty else { return false }
            detailStore.stepSelection(delta)
            return true
        case .sourceRecords:
            return moduleStore.stepSourceRecord(from: record, delta: delta)
        }
    }
}
