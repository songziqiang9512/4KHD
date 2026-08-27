import AppKit
import Nuke
import Observation

@MainActor
final class WallhavenImageDetailViewController: NSViewController, WorkspaceFocusable {
    private let library: WallhavenGalleryStore
    private let immersive: ImmersiveController
    private let detailPane: WorkspaceDetailPaneController
    private let detailInteraction: WallhavenDetailInteractionController
    private let imageView = WallhavenDetailZoomableImageView()
    private let emptyLabel = NSTextField(labelWithString: "请选择一张壁纸")
    private let previousButton = DetailNavigationButton(symbolName: "chevron.left", accessibilityDescription: "上一张")
    private let nextButton = DetailNavigationButton(symbolName: "chevron.right", accessibilityDescription: "下一张")
    private let infoChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let infoLabel = NSTextField(labelWithString: "")
    private let sourceChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let sourceButton: NSButton = {
        let b = NSButton(title: "来源: Wallhaven", target: nil, action: nil)
        b.bezelStyle = .inline
        b.controlSize = .small
        b.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        b.isBordered = false
        b.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "打开来源")
        b.imagePosition = .imageLeading
        return b
    }()
    private let uploaderChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let uploaderButton: NSButton = {
        let b = NSButton(title: "", target: nil, action: nil)
        b.bezelStyle = .inline
        b.controlSize = .small
        b.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        b.isBordered = false
        b.image = NSImage(systemSymbolName: "person.circle", accessibilityDescription: "作者")
        b.imagePosition = .imageLeading
        return b
    }()
    private let actionChrome = DetailOverlayChromeView(cornerRadius: 11)
    private let actionLabel = NSTextField(labelWithString: "")
    private let desktopButton: NSButton = {
        let desktopImage = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "设为桌面壁纸")
                         ?? NSImage(size: NSSize(width: 16, height: 16))
        let b = NSButton(image: desktopImage,
                         target: nil, action: nil)
        b.bezelStyle = .accessoryBarAction
        b.controlSize = .small
        b.toolTip = "设为桌面壁纸"
        return b
    }()
    private var isObserving = false
    private var currentWallpaperID: Wallpaper.ID?
    private var currentImageURL: URL?
    private var loadingOriginalImageURL: URL?
    private var resetTokenSeen = UUID()
    private let reloadQueue = WorkspaceCoalescingQueue(name: "WallhavenDetail Reload", interval: 0.05, maxInterval: 0.1)

    init(
        library: WallhavenGalleryStore,
        immersive: ImmersiveController,
        detailPane: WorkspaceDetailPaneController,
        detailInteraction: WallhavenDetailInteractionController
    ) {
        self.library = library
        self.immersive = immersive
        self.detailPane = detailPane
        self.detailInteraction = detailInteraction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = WorkspaceDetailRootView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.keyHandler = { [weak self] event in self?.handleKeyDown(event) ?? false }
        view = root
        setupView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.onImageLoadCompleted = { [weak self] url, _ in
            guard let self, self.loadingOriginalImageURL == url else { return }
            self.loadingOriginalImageURL = nil
            self.reloadDetail()
        }
        reloadDetail()
        observeState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasAppeared else { return }
        hasAppeared = true
        if let firstResponder = view.window?.firstResponder as? NSText, firstResponder.isEditable { return }
        view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
    }
    private var hasAppeared = false

    func focus() {
        view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
    }

    private func setupView() {
        emptyLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        infoLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        infoLabel.textColor = .labelColor
        infoLabel.alignment = .center
        infoLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        infoLabel.maximumNumberOfLines = 3
        infoChrome.addSubview(infoLabel)

        sourceButton.target = self
        sourceButton.action = #selector(openSourcePage)
        sourceChrome.addSubview(sourceButton)

        uploaderButton.target = self
        uploaderButton.action = #selector(uploaderClicked)
        uploaderChrome.addSubview(uploaderButton)
        uploaderChrome.isHidden = true

        actionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        actionLabel.textColor = .labelColor
        actionLabel.alignment = .center
        actionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionChrome.addSubview(actionLabel)

        previousButton.target = self
        previousButton.action = #selector(previousWallpaper)
        nextButton.target = self
        nextButton.action = #selector(nextWallpaper)
        desktopButton.target = self
        desktopButton.action = #selector(setAsDesktopFromDetail)

        for subview in [imageView, emptyLabel, previousButton, nextButton,
                        infoChrome, uploaderChrome, sourceChrome, actionChrome, desktopButton] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceButton.translatesAutoresizingMaskIntoConstraints = false
        uploaderButton.translatesAutoresizingMaskIntoConstraints = false
        actionLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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

            uploaderChrome.leadingAnchor.constraint(equalTo: sourceChrome.trailingAnchor, constant: 6),
            uploaderChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            uploaderChrome.heightAnchor.constraint(equalToConstant: 24),
            uploaderButton.leadingAnchor.constraint(equalTo: uploaderChrome.leadingAnchor, constant: 8),
            uploaderButton.trailingAnchor.constraint(equalTo: uploaderChrome.trailingAnchor, constant: -8),
            uploaderButton.centerYAnchor.constraint(equalTo: uploaderChrome.centerYAnchor),

            infoChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoChrome.bottomAnchor.constraint(equalTo: sourceChrome.topAnchor, constant: -4),
            infoChrome.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            infoChrome.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            infoChrome.widthAnchor.constraint(greaterThanOrEqualTo: infoLabel.widthAnchor, constant: 20),
            infoLabel.leadingAnchor.constraint(equalTo: infoChrome.leadingAnchor, constant: 10),
            infoLabel.trailingAnchor.constraint(equalTo: infoChrome.trailingAnchor, constant: -10),
            infoLabel.centerYAnchor.constraint(equalTo: infoChrome.centerYAnchor),

            sourceChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sourceChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            sourceChrome.heightAnchor.constraint(equalToConstant: 24),
            sourceButton.leadingAnchor.constraint(equalTo: sourceChrome.leadingAnchor, constant: 8),
            sourceButton.trailingAnchor.constraint(equalTo: sourceChrome.trailingAnchor, constant: -8),
            sourceButton.centerYAnchor.constraint(equalTo: sourceChrome.centerYAnchor),

            actionChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            actionChrome.heightAnchor.constraint(equalToConstant: 24),
            actionChrome.widthAnchor.constraint(greaterThanOrEqualTo: actionLabel.widthAnchor, constant: 16),
            actionLabel.leadingAnchor.constraint(equalTo: actionChrome.leadingAnchor, constant: 8),
            actionLabel.trailingAnchor.constraint(equalTo: actionChrome.trailingAnchor, constant: -8),
            actionLabel.centerYAnchor.constraint(equalTo: actionChrome.centerYAnchor),

            desktopButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            desktopButton.bottomAnchor.constraint(equalTo: sourceChrome.topAnchor, constant: -6),
            desktopButton.widthAnchor.constraint(equalToConstant: 28),
            desktopButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = library.selectedWallpaper?.id
            // 只观察列表长度:加载更多时刷新上/下张按钮状态,列表内容替换
            // (搜索/刷新)会经 selectedWallpaper 重新赋值触发,无需观察整个数组。
            _ = library.wallpapers.count
            _ = library.resolvedWallpaper?.id
            _ = library.isResolvingDetail
            _ = detailInteraction.resetToken
            _ = immersive.isImmersive
            _ = detailPane.isPresented
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

    /// 保存状态变化只刷新状态标签,不走完整 reload 路径。
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
        let statusText = detailStatusText
        actionLabel.stringValue = statusText
        actionChrome.isHidden = statusText.isEmpty
    }

    private func reloadDetail() {
        guard shouldLoadDetailContent else {
            currentWallpaperID = nil
            currentImageURL = nil
            loadingOriginalImageURL = nil
            imageView.setImageURL(nil)
            emptyLabel.isHidden = true
            previousButton.isHidden = true
            nextButton.isHidden = true
            infoChrome.isHidden = true
            uploaderChrome.isHidden = true
            sourceChrome.isHidden = true
            actionChrome.isHidden = true
            desktopButton.isHidden = true
            return
        }

        guard let wallpaper = library.selectedWallpaper else {
            currentWallpaperID = nil
            currentImageURL = nil
            loadingOriginalImageURL = nil
            imageView.setImageURL(nil)
            imageView.isHidden = true
            emptyLabel.isHidden = false
            previousButton.isHidden = true
            nextButton.isHidden = true
            infoChrome.isHidden = true
            uploaderChrome.isHidden = true
            sourceChrome.isHidden = true
            actionChrome.isHidden = true
            desktopButton.isHidden = true
            return
        }

        imageView.isHidden = false
        emptyLabel.isHidden = true
        desktopButton.isHidden = false
        sourceChrome.isHidden = false
        previousButton.isHidden = false
        nextButton.isHidden = false
        infoChrome.isHidden = false
        sourceChrome.isHidden = false
        actionChrome.isHidden = false

        let wallpaperList = library.wallpapers
        let selectedIndex = wallpaperList.firstIndex(where: { $0.id == wallpaper.id }) ?? 0
        previousButton.isEnabled = selectedIndex > 0
        nextButton.isEnabled = selectedIndex < wallpaperList.count - 1

        // Kick off detail resolution on selection change.
        if currentWallpaperID != wallpaper.id {
            library.resolveDetail(for: wallpaper)
        }

        // Use resolved wallpaper if available (has full tags, fullImageUrl from /w/{id}).
        let displayWallpaper = library.resolvedWallpaper?.id == wallpaper.id ? library.resolvedWallpaper! : wallpaper

        infoLabel.stringValue = [displayWallpaper.displayName, displayWallpaper.detailInfoText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        sourceButton.title = "来源: Wallhaven"
        sourceButton.toolTip = displayWallpaper.sourcePageUrl.absoluteString

        // Uploader display
        if let uploader = displayWallpaper.uploader {
            uploaderButton.title = "\(uploader) 的作品"
            uploaderButton.toolTip = "浏览 @\(uploader) 的所有上传作品"
            uploaderChrome.isHidden = false
        } else {
            uploaderChrome.isHidden = true
        }

        // Always show thumbnail first (cached from grid → instant display),
        // then load full-res in background while the thumbnail stays visible.
        let previewURL = displayWallpaper.previewUrl ?? wallpaper.previewUrl
        let coverURL = displayWallpaper.cardCoverUrl ?? wallpaper.cardCoverUrl
        let fullURL = displayWallpaper.fullImageUrl
        let isIncomplete = (displayWallpaper.width == nil && displayWallpaper.fullImageUrl == nil)

        if currentWallpaperID != wallpaper.id {
            currentWallpaperID = wallpaper.id
            loadingOriginalImageURL = nil
            detailInteraction.saveMessage = ""

            // Show the card's own thumbnail/preview first — cached from grid, instant display.
            if let initial = coverURL {
                imageView.setImageURL(initial)
            }

            // If full-res is already available, load it in background (thumbnail stays visible).
            if let full = fullURL, !isIncomplete {
                currentImageURL = full
                setDetailImageURL(full, isOriginal: true, preservesCurrentImageUntilLoaded: imageView.imageView.image != nil)
            } else {
                currentImageURL = previewURL
            }
        } else if currentImageURL != fullURL, let full = fullURL, !isIncomplete {
            // Detail resolution completed: upgrade to full-res in background.
            currentImageURL = full
            setDetailImageURL(full, isOriginal: true, preservesCurrentImageUntilLoaded: true)
        }

        updateSaveStatus()

        if detailInteraction.resetToken != resetTokenSeen {
            resetTokenSeen = detailInteraction.resetToken
            imageView.resetZoom()
        }
    }

    private var shouldLoadDetailContent: Bool {
        detailPane.isPresented || immersive.isImmersive
    }

    private var detailStatusText: String {
        if loadingOriginalImageURL != nil { return "加载原图中..." }
        if library.isResolvingDetail { return "加载详情中..." }
        switch detailInteraction.saveMessage {
        case "保存中", "已保存", "保存失败", "下载中", "下载失败", "已设为桌面壁纸":
            return detailInteraction.saveMessage
        default:
            return ""
        }
    }

    private func setDetailImageURL(
        _ url: URL,
        isOriginal: Bool,
        preservesCurrentImageUntilLoaded: Bool
    ) {
        // 缓存只查一次,结果传给 setImageURL 复用,避免三档缓存重复查询。
        var prechecked = WallhavenDetailZoomableImageView.CachedImageLookup.notChecked
        if isOriginal {
            if let cached = imageView.cachedImage(for: url) {
                prechecked = .found(cached)
            } else {
                prechecked = .miss
                loadingOriginalImageURL = url
            }
        }
        imageView.setImageURL(
            url,
            preservesCurrentImageUntilLoaded: preservesCurrentImageUntilLoaded,
            prechecked: prechecked
        )
    }

    @objc private func previousWallpaper() {
        let wallpaperList = library.wallpapers
        guard let current = library.selectedWallpaper,
              let index = wallpaperList.firstIndex(where: { $0.id == current.id }),
              index > 0 else { return }
        library.select(wallpaperList[index - 1])
    }

    @objc private func nextWallpaper() {
        let wallpaperList = library.wallpapers
        guard let current = library.selectedWallpaper,
              let index = wallpaperList.firstIndex(where: { $0.id == current.id }),
              index < wallpaperList.count - 1 else { return }
        library.select(wallpaperList[index + 1])
    }

    @objc private func uploaderClicked() {
        guard let wallpaper = library.effectiveSelectedWallpaper ?? library.selectedWallpaper,
              let uploader = wallpaper.uploader else { return }
        library.showUploaderWorks(username: uploader)
    }

    @objc private func openSourcePage() {
        guard let wallpaper = library.effectiveSelectedWallpaper ?? library.selectedWallpaper else { return }
        NSWorkspace.shared.open(wallpaper.sourcePageUrl)
    }

    @objc func saveImage(_ sender: Any?) {
        guard let wallpaper = library.effectiveSelectedWallpaper else { return }
        detailInteraction.saveWallpaper(wallpaper)
    }

    @objc private func setAsDesktopFromDetail() {
        guard let wallpaper = library.effectiveSelectedWallpaper else { return }
        guard let fullImageUrl = wallpaper.fullImageUrl else {
            library.resolveDetail(for: wallpaper)
            detailInteraction.saveMessage = "正在获取原图..."
            return
        }
        detailInteraction.saveMessage = "下载中"
        let request = RemoteImagePipeline.shared.request(
            for: fullImageUrl,
            priority: .veryHigh,
            configureURLRequest: WallhavenRequestFactory.configureImageRequest
        )
        _ = RemoteImagePipeline.shared.loadData(with: request) { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let data else {
                    self.detailInteraction.saveMessage = "下载失败"
                    return
                }
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("4KHD-Wallpaper", isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let ext = wallpaper.fileExtensionForSave
                let tempFile = tempDir.appendingPathComponent("wallhaven-\(wallpaper.id).\(ext)")
                do {
                    try data.write(to: tempFile, options: .atomic)
                    LocalDesktopWallpaperSetter.setDesktopWallpaper(tempFile)
                    self.detailInteraction.saveMessage = "已设为桌面壁纸"
                } catch {
                    self.detailInteraction.saveMessage = "下载失败"
                }
            }
        }
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

    private func selectAdjacent(delta: Int) -> Bool {
        let wallpaperList = library.wallpapers
        guard !wallpaperList.isEmpty else { return false }
        guard let current = library.selectedWallpaper,
              let index = wallpaperList.firstIndex(where: { $0.id == current.id }) else { return false }
        let next = min(max(index + delta, 0), wallpaperList.count - 1)
        guard next != index else { return true }
        library.select(wallpaperList[next])
        return true
    }
}

@MainActor
final class WallhavenDetailZoomableImageView: WorkspaceZoomableImageView {
    var onImageLoadCompleted: ((URL, Bool) -> Void)?

    /// 调用方对缓存查询的预检结果:详情 VC 需要先知道缓存是否命中来设置
    /// 「加载原图中」状态,把结果传进来避免 setImageURL 内部重复三档查询。
    enum CachedImageLookup {
        case notChecked
        case found(NSImage)
        case miss
    }

    private let placeholderContainer = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "加载中")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private var retryAction: (() -> Void)?
    private var imageTask: RemoteImageLoadTask?
    private var loadedURL: URL?
    /// 正在网络加载的 URL:同一 URL 的在途请求被再次调用时直接复用,不取消重启。
    private var inFlightURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupPlaceholder()
    }

    func setImageURL(
        _ url: URL?,
        preservesCurrentImageUntilLoaded: Bool = false,
        prechecked: CachedImageLookup = .notChecked
    ) {
        // 同一 URL 的请求仍在途:直接复用,避免封面→原图升级时同 URL 连续调用取消重启。
        if let url, url == inFlightURL { return }
        imageTask?.cancel()
        inFlightURL = nil
        // 同 URL 且已有图才跳过：加载失败（image 为 nil）后重试同一 URL 必须重新发起请求。
        guard loadedURL != url || imageView.image == nil else { return }
        loadedURL = url
        imageView.alphaValue = 1
        guard let url else {
            imageView.image = nil
            placeholderContainer.isHidden = false
            return
        }

        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .veryHigh,
            maxPixelSize: 4096,
            configureURLRequest: WallhavenRequestFactory.configureImageRequest
        )
        // Try full/detail cache first; then fall back to grid/list thumbnail sizes
        // so the existing cover can display immediately when opening detail.
        let cached: NSImage?
        switch prechecked {
        case .notChecked:
            cached = cachedImage(for: url)
        case .found(let image):
            cached = image
        case .miss:
            cached = nil
        }
        if let cached {
            imageView.image = cached
            placeholderContainer.isHidden = true
            fitImage(resetMagnification: true)
            onImageLoadCompleted?(url, true)
            return
        }

        let shouldKeepCurrent = preservesCurrentImageUntilLoaded && imageView.image != nil
        if !shouldKeepCurrent {
            imageView.image = nil
            placeholderLabel.stringValue = "加载中"
            retryButton.isHidden = true
            placeholderContainer.isHidden = false
        }

        inFlightURL = url
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            guard let self, self.loadedURL == url else { return }
            self.inFlightURL = nil
            guard let image else {
                if !shouldKeepCurrent || self.imageView.image == nil {
                    self.placeholderLabel.stringValue = "图片加载失败"
                    self.retryButton.isHidden = true
                    self.placeholderContainer.isHidden = false
                }
                self.onImageLoadCompleted?(url, false)
                return
            }
            self.placeholderContainer.isHidden = true
            self.retryButton.isHidden = true
            self.imageView.alphaValue = 0
            self.imageView.image = image
            self.fitImage(resetMagnification: true)
            self.onImageLoadCompleted?(url, true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.imageView.animator().alphaValue = 1
            }
        }
    }

    func showLoading(_ message: String) {
        placeholderLabel.stringValue = message
        retryButton.isHidden = true
        placeholderContainer.isHidden = false
    }

    func showFailure(retry: @escaping () -> Void) {
        placeholderLabel.stringValue = "解析失败"
        retryButton.isHidden = false
        placeholderContainer.isHidden = false
        retryAction = retry
    }

    @objc private func didTapRetry() {
        retryAction?()
    }

    private func setupPlaceholder() {
        placeholderLabel.font = .systemFont(ofSize: 15, weight: .medium)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.drawsBackground = false

        retryButton.bezelStyle = .rounded
        retryButton.isHidden = true
        retryButton.target = self
        retryButton.action = #selector(didTapRetry)

        let stack = NSStackView(views: [placeholderLabel, retryButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8

        placeholderContainer.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: placeholderContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: placeholderContainer.centerYAnchor)
        ])

        addSubview(placeholderContainer)
        placeholderContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderContainer.topAnchor.constraint(equalTo: topAnchor),
            placeholderContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func cachedImage(for url: URL) -> NSImage? {
        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .veryHigh,
            maxPixelSize: 4096,
            configureURLRequest: WallhavenRequestFactory.configureImageRequest
        )
        if let image = RemoteImagePipeline.shared.cachedImage(with: request) {
            return image
        }
        for maxPixelSize in [CGFloat(512), CGFloat(180)] {
            let thumbnailRequest = RemoteImagePipeline.shared.request(
                for: url,
                priority: .veryHigh,
                maxPixelSize: maxPixelSize,
                configureURLRequest: WallhavenRequestFactory.configureImageRequest
            )
            if let image = RemoteImagePipeline.shared.cachedImage(with: thumbnailRequest) {
                return image
            }
        }
        return nil
    }
}
