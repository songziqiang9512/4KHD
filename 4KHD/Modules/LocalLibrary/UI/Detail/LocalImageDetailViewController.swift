import AppKit
import Observation

@MainActor
final class LocalImageDetailViewController: NSViewController {
    private let localLibrary: LocalLibraryStore
    private let immersive: ImmersiveController
    private let detailInteraction: LocalDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let zoomableImageView = LocalZoomableImageView()
    private let filmstripView = LocalImageFilmstripView()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let toolStack = NSStackView()
    private let filmstripButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "没有可显示图片")
    private var filmstripHeightConstraint: NSLayoutConstraint?
    private var metadataByImageID: [LocalImageItem.ID: LocalImageMetadata] = [:]
    private var metadataTask: Task<Void, Never>?
    private var observedFolderID: LocalFolderNode.ID?
    private var isObserving = false
    private var currentImageID: LocalImageItem.ID?

    init(
        localLibrary: LocalLibraryStore,
        immersive: ImmersiveController,
        detailInteraction: LocalDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController
    ) {
        self.localLibrary = localLibrary
        self.immersive = immersive
        self.detailInteraction = detailInteraction
        self.filmstripVisibility = filmstripVisibility
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        metadataTask?.cancel()
    }

    override func loadView() {
        view = LocalImageDetailRootView()
        setupView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadDetail()
        observeState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.hasBareKeyModifiers else { return false }
        switch event.keyCode {
        case 123:
            localLibrary.stepImage(-1)
            return true
        case 124:
            localLibrary.stepImage(1)
            return true
        case 49:
            quickLookSelected()
            return true
        case 3:
            immersive.toggle()
            return true
        default:
            return false
        }
    }

    private func setupView() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        zoomableImageView.onDisplayed = { [weak self] in
            self?.updateFilmstripVisibility()
        }

        filmstripView.onSelect = { [weak self] index in
            self?.localLibrary.selectImage(at: index)
        }

        configureStepButton(previousButton, symbolName: "chevron.left", action: #selector(previousImage))
        configureStepButton(nextButton, symbolName: "chevron.right", action: #selector(nextImage))
        configureToolStack()

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        statusLabel.textColor = .labelColor
        statusLabel.alignment = .center
        statusLabel.wantsLayer = true
        statusLabel.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82).cgColor
        statusLabel.layer?.cornerRadius = 12
        statusLabel.isHidden = true

        emptyLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        for subview in [zoomableImageView, filmstripView, previousButton, nextButton, toolStack, statusLabel, emptyLabel] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }

        let filmstripHeight = filmstripView.heightAnchor.constraint(equalToConstant: 116)
        filmstripHeightConstraint = filmstripHeight
        NSLayoutConstraint.activate([
            zoomableImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomableImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            zoomableImageView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomableImageView.bottomAnchor.constraint(equalTo: filmstripView.topAnchor),

            filmstripView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filmstripView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filmstripView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            filmstripHeight,

            previousButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            previousButton.centerYAnchor.constraint(equalTo: zoomableImageView.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 42),
            previousButton.heightAnchor.constraint(equalToConstant: 42),

            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            nextButton.centerYAnchor.constraint(equalTo: zoomableImageView.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 42),
            nextButton.heightAnchor.constraint(equalToConstant: 42),

            toolStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            toolStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: filmstripView.topAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureToolStack() {
        toolStack.orientation = .horizontal
        toolStack.alignment = .centerY
        toolStack.spacing = 8
        toolStack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        toolStack.wantsLayer = true
        toolStack.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.72).cgColor
        toolStack.layer?.cornerRadius = 16

        let tools: [(String, String, Selector)] = [
            ("1.magnifyingglass", "实际大小", #selector(resetZoom)),
            ("arrow.up.left.and.arrow.down.right", "大图模式", #selector(toggleImmersive)),
            ("folder", "在 Finder 中显示", #selector(revealInFinder)),
            ("eye", "快速预览", #selector(quickLookImage)),
            ("info.circle", "详细信息", #selector(toggleInfo)),
            ("square.and.arrow.down", "保存副本", #selector(saveImage))
        ]
        for tool in tools {
            toolStack.addArrangedSubview(makeToolButton(symbolName: tool.0, toolTip: tool.1, action: tool.2))
        }

        filmstripButton.image = NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled", accessibilityDescription: "缩略图")
        filmstripButton.imagePosition = .imageOnly
        filmstripButton.bezelStyle = .texturedRounded
        filmstripButton.isBordered = true
        filmstripButton.target = self
        filmstripButton.action = #selector(toggleFilmstrip)
        filmstripButton.toolTip = "显示/隐藏缩略图"
        toolStack.addArrangedSubview(filmstripButton)
    }

    private func makeToolButton(symbolName: String, toolTip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    private func configureStepButton(_ button: NSButton, symbolName: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.bezelStyle = .circular
        button.isBordered = true
        button.target = self
        button.action = action
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = localLibrary.selectedFolderID
            _ = localLibrary.selectedImageIndex
            _ = localLibrary.roots
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
        guard let folder = localLibrary.selectedFolder, let image = localLibrary.selectedImage else {
            currentImageID = nil
            zoomableImageView.setImageURL(nil)
            emptyLabel.isHidden = false
            previousButton.isHidden = true
            nextButton.isHidden = true
            filmstripView.isHidden = true
            statusLabel.isHidden = true
            return
        }

        emptyLabel.isHidden = true
        previousButton.isHidden = false
        nextButton.isHidden = false
        previousButton.isEnabled = localLibrary.selectedImageIndex > 0
        nextButton.isEnabled = localLibrary.selectedImageIndex < localLibrary.selectedImages.count - 1

        if currentImageID != image.id {
            currentImageID = image.id
            detailInteraction.saveMessage = ""
            zoomableImageView.setImageURL(image.url)
            LocalQuickLookController.shared.syncVisible(url: image.url)
        } else {
            zoomableImageView.setImageURL(image.url)
        }

        loadMetadataIfNeeded(folder: folder)
        filmstripView.update(images: localLibrary.selectedImages, selectedIndex: localLibrary.selectedImageIndex)
        toolStack.isHidden = !immersive.isImmersive
        updateFilmstripVisibility()
        updateSaveStatus()
    }

    private func updateFilmstripVisibility() {
        let shouldShow = filmstripVisibility.isPresented && !localLibrary.selectedImages.isEmpty
        filmstripView.isHidden = !shouldShow
        filmstripHeightConstraint?.constant = shouldShow ? 116 : 0
        filmstripButton.image = NSImage(
            systemSymbolName: shouldShow ? "rectangle.bottomthird.inset.filled" : "rectangle",
            accessibilityDescription: shouldShow ? "隐藏缩略图" : "显示缩略图"
        )
    }

    private func updateSaveStatus() {
        let message = detailInteraction.saveMessage
        statusLabel.stringValue = message
        statusLabel.isHidden = message.isEmpty
    }

    private func loadMetadataIfNeeded(folder: LocalFolderNode) {
        guard observedFolderID != folder.id else { return }
        observedFolderID = folder.id
        metadataTask?.cancel()
        metadataTask = Task { [weak self] in
            let metadata = await LocalImageMetadataService.loadMetadata(for: folder.images)
            guard !Task.isCancelled else { return }
            self?.metadataByImageID = metadata
        }
    }

    private func quickLookSelected() {
        guard let image = localLibrary.selectedImage else { return }
        LocalQuickLookController.shared.open(url: image.url)
    }

    private func showInfo(for image: LocalImageItem) {
        let metadata = metadataByImageID[image.id]
        let alert = NSAlert()
        alert.messageText = image.title
        alert.informativeText = [
            formattedResolution(metadata),
            formattedSecondaryMetadata(metadata),
            image.url.path
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        alert.addButton(withTitle: "关闭")
        alert.runModal()
    }

    @objc private func previousImage() {
        localLibrary.stepImage(-1)
    }

    @objc private func nextImage() {
        localLibrary.stepImage(1)
    }

    @objc func resetZoom() {
        zoomableImageView.resetZoom()
    }

    @objc func toggleImmersive() {
        immersive.toggle()
    }

    @objc func toggleFilmstrip() {
        filmstripVisibility.toggle()
    }

    @objc func revealInFinder() {
        guard let image = localLibrary.selectedImage else { return }
        NSWorkspace.shared.activateFileViewerSelecting([image.url])
    }

    @objc func quickLookImage() {
        quickLookSelected()
    }

    @objc func toggleInfo() {
        guard let image = localLibrary.selectedImage else { return }
        showInfo(for: image)
    }

    @objc func saveImage() {
        guard let image = localLibrary.selectedImage else { return }
        detailInteraction.save(image: image)
        updateSaveStatus()
    }
}

@MainActor
private final class LocalImageDetailRootView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let controller = nextResponder as? LocalImageDetailViewController,
           controller.handleKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}
