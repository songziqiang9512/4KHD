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
        let b = NSButton(image: NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "设为桌面壁纸")!,
                         target: nil, action: nil)
        b.bezelStyle = .accessoryBarAction
        b.controlSize = .small
        b.toolTip = "设为桌面壁纸"
        return b
    }()
    private var isObserving = false
    private var currentWallpaperID: Wallpaper.ID?
    private var currentImageURL: URL?
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
        reloadDetail()
        observeState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let firstResponder = view.window?.firstResponder as? NSText, firstResponder.isEditable { return }
        view.window?.makeFirstResponder(view)
    }

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
            _ = library.wallpapers.count
            _ = library.resolvedWallpaper?.id
            _ = library.isResolvingDetail
            _ = detailInteraction.resetToken
            _ = detailInteraction.saveMessage
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
    }

    private func reloadDetail() {
        guard shouldLoadDetailContent else {
            currentWallpaperID = nil
            currentImageURL = nil
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

        // Build info text
        let infoParts = [
            displayWallpaper.resolutionText,
            displayWallpaper.formattedFileSize,
            displayWallpaper.fileType?.replacingOccurrences(of: "image/", with: "").uppercased(),
            displayWallpaper.category.map { "Category: \($0)" }
        ].compactMap { $0 }.filter { !$0.isEmpty && $0 != "-" }
        infoLabel.stringValue = infoParts.joined(separator: " · ")

        // Tags line if available
        let tags = displayWallpaper.tags.prefix(8).joined(separator: ", ")
        if !tags.isEmpty {
            infoLabel.stringValue = infoLabel.stringValue + " · \(tags)"
        }

        sourceButton.title = "来源: Wallhaven"
        sourceButton.toolTip = displayWallpaper.sourcePageUrl.absoluteString
        actionLabel.stringValue = detailStatusText
        actionChrome.isHidden = detailStatusText.isEmpty

        // Uploader display
        if let uploader = displayWallpaper.uploader {
            uploaderButton.title = "\(uploader) 的作品"
            uploaderButton.toolTip = "浏览 @\(uploader) 的所有上传作品"
            uploaderChrome.isHidden = false
        } else {
            uploaderChrome.isHidden = true
        }

        // Load image — prefer fullImageUrl from detail; fall back to search data.
        let imageURL = displayWallpaper.fullImageUrl ?? displayWallpaper.previewUrl ?? wallpaper.previewUrl ?? wallpaper.fullImageUrl
        let isIncomplete = wallpaper.width == nil && wallpaper.fullImageUrl == nil
        if currentWallpaperID != wallpaper.id {
            currentWallpaperID = wallpaper.id
            detailInteraction.saveMessage = ""
            if isIncomplete {
                // Favorites-recovered wallpaper: show loading until /w/{id} resolves.
                imageView.setImageURL(nil, preservesCurrentImageUntilLoaded: false)
                imageView.showLoading("加载详情中...")
            } else {
                imageView.setImageURL(imageURL, preservesCurrentImageUntilLoaded: false)
            }
        }
        if !isIncomplete {
            currentImageURL = imageURL
        }

        if detailInteraction.resetToken != resetTokenSeen {
            resetTokenSeen = detailInteraction.resetToken
            imageView.resetZoom()
        }
    }

    private var shouldLoadDetailContent: Bool {
        detailPane.isPresented || immersive.isImmersive
    }

    private var detailStatusText: String {
        if library.isResolvingDetail { return "加载详情中..." }
        switch detailInteraction.saveMessage {
        case "保存中", "已保存", "保存失败":
            return detailInteraction.saveMessage
        default:
            return ""
        }
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
    private let placeholderContainer = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "加载中")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private var retryAction: (() -> Void)?
    private var imageTask: ImageTask?
    private var loadedURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupPlaceholder()
    }

    func setImageURL(_ url: URL?, preservesCurrentImageUntilLoaded: Bool = false) {
        imageTask?.cancel()
        guard loadedURL != url else { return }
        loadedURL = url
        let shouldKeepCurrent = preservesCurrentImageUntilLoaded && imageView.image != nil
        if !shouldKeepCurrent {
            imageView.image = nil
            placeholderLabel.stringValue = "加载中"
            retryButton.isHidden = true
            placeholderContainer.isHidden = false
        }
        guard let url else { return }

        let request = RemoteImagePipeline.shared.request(
            for: url,
            priority: .veryHigh,
            maxPixelSize: 4096,
            configureURLRequest: WallhavenRequestFactory.configureImageRequest
        )
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.loadedURL == url else { return }
                guard let image else {
                    if !shouldKeepCurrent || self.imageView.image == nil {
                        self.placeholderLabel.stringValue = "图片加载失败"
                        self.retryButton.isHidden = true
                        self.placeholderContainer.isHidden = false
                    }
                    return
                }
                self.placeholderContainer.isHidden = true
                self.retryButton.isHidden = true
                self.imageView.image = image
                self.fitImage(resetMagnification: true)
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
}
