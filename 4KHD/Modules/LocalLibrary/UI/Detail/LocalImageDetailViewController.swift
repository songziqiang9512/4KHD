import AppKit
import Observation

@MainActor
final class LocalImageDetailViewController: NSViewController, WorkspaceFocusable {
    private let localLibrary: LocalLibraryStore
    private let immersive: ImmersiveController
    private let detailInteraction: LocalDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let zoomableImageView = LocalZoomableImageView()
    private let filmstripView = LocalImageFilmstripView()
    private let statusChrome = DetailOverlayChromeView(cornerRadius: 12)
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "没有可显示图片")
    private var filmstripHeightConstraint: NSLayoutConstraint?
    private var imageTopSafeAreaConstraint: NSLayoutConstraint?
    private var imageTopFullBleedConstraint: NSLayoutConstraint?
    private var metadataByImageID: [LocalImageItem.ID: LocalImageMetadata] = [:]
    private var metadataTask: Task<Void, Never>?
    private var observedFolderID: LocalFolderNode.ID?
    private var isObserving = false
    private var currentImageID: LocalImageItem.ID?
    private var resetTokenSeen = UUID()

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

    func focus() {
        view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        WorkspaceKeyboardHandler.keyDown(
            event,
            context: WorkspaceKeyboardContext(
                stepSelection: { [weak self] delta in
                    self?.localLibrary.stepImage(delta)
                    return true
                },
                quickLook: { [weak self] in
                    self?.quickLookSelected()
                    return true
                },
                toggleImmersive: { [weak self] in
                    self?.immersive.toggle()
                    return true
                }
            )
        )
    }

    private func setupView() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        zoomableImageView.onDisplayed = { [weak self] in
            self?.updateFilmstripVisibility()
        }

        filmstripView.onSelect = { [weak self] index in
            self?.localLibrary.selectImage(at: index)
        }

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        statusLabel.textColor = .labelColor
        statusLabel.alignment = .center
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusChrome.addSubview(statusLabel)
        statusChrome.isHidden = true

        emptyLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        for subview in [zoomableImageView, filmstripView, statusChrome, emptyLabel] {
            view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let filmstripHeight = filmstripView.heightAnchor.constraint(equalToConstant: 116)
        let imageTopSafeAreaConstraint = zoomableImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        let imageTopFullBleedConstraint = zoomableImageView.topAnchor.constraint(equalTo: view.topAnchor)
        filmstripHeightConstraint = filmstripHeight
        self.imageTopSafeAreaConstraint = imageTopSafeAreaConstraint
        self.imageTopFullBleedConstraint = imageTopFullBleedConstraint
        NSLayoutConstraint.activate([
            zoomableImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomableImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageTopSafeAreaConstraint,
            zoomableImageView.bottomAnchor.constraint(equalTo: filmstripView.topAnchor),

            filmstripView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filmstripView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filmstripView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            filmstripHeight,

            statusChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusChrome.bottomAnchor.constraint(equalTo: filmstripView.topAnchor, constant: -16),
            statusChrome.heightAnchor.constraint(equalToConstant: 28),
            statusChrome.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            statusChrome.widthAnchor.constraint(greaterThanOrEqualTo: statusLabel.widthAnchor, constant: 18),
            statusLabel.leadingAnchor.constraint(equalTo: statusChrome.leadingAnchor, constant: 9),
            statusLabel.trailingAnchor.constraint(equalTo: statusChrome.trailingAnchor, constant: -9),
            statusLabel.centerYAnchor.constraint(equalTo: statusChrome.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = localLibrary.selectedFolderID
            _ = localLibrary.selectedImageIndex
            _ = localLibrary.roots
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
        guard let folder = localLibrary.selectedFolder, let image = localLibrary.selectedImage else {
            currentImageID = nil
            zoomableImageView.setImageURL(nil)
            emptyLabel.isHidden = false
            filmstripView.isHidden = true
            statusChrome.isHidden = true
            updateFilmstripLayout(shouldShow: false)
            return
        }

        emptyLabel.isHidden = true

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
        updateFilmstripVisibility()
        if detailInteraction.resetToken != resetTokenSeen {
            resetTokenSeen = detailInteraction.resetToken
            zoomableImageView.resetZoom()
        }
        updateSaveStatus()
    }

    private func updateFilmstripVisibility() {
        let shouldShow = filmstripVisibility.isPresented && !localLibrary.selectedImages.isEmpty
        updateFilmstripLayout(shouldShow: shouldShow)
    }

    private func updateFilmstripLayout(shouldShow: Bool) {
        filmstripView.isHidden = !shouldShow
        filmstripHeightConstraint?.constant = shouldShow ? 116 : 0
        updateImageTopConstraint(showsFilmstrip: shouldShow)
    }

    private func updateImageTopConstraint(showsFilmstrip: Bool) {
        let usesFullBleedTop = immersive.isImmersive && !showsFilmstrip
        imageTopSafeAreaConstraint?.isActive = !usesFullBleedTop
        imageTopFullBleedConstraint?.isActive = usesFullBleedTop
    }

    private func updateSaveStatus() {
        let message = detailInteraction.saveMessage
        statusLabel.stringValue = message
        statusChrome.isHidden = message.isEmpty
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

    private func showInfo(for _: LocalImageItem) {
        WorkspaceInspectorPresenter.show()
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
