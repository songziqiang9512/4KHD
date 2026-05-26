import AppKit
import Observation

@MainActor
final class WorkspaceInspectorWindowController: NSWindowController, NSWindowDelegate {
    private enum State {
        static let isOpenKey = "com.songziqiang.4khd.workspaceInspectorIsOpen.v1"
        static let frameAutosaveName = "WorkspaceInspectorWindow"
    }

    private let inspectorViewController: WorkspaceInspectorViewController

    init(appContext: WorkspaceAppContext) {
        inspectorViewController = WorkspaceInspectorViewController(appContext: appContext)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Inspector"
        panel.contentViewController = inspectorViewController
        panel.contentMinSize = NSSize(width: 280, height: 220)
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.setFrameAutosaveName(State.frameAutosaveName)

        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    static var shouldOpenAtStartup: Bool {
        UserDefaults.standard.bool(forKey: State.isOpenKey)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        inspectorViewController.refresh()
        UserDefaults.standard.set(true, forKey: State.isOpenKey)
    }

    func saveState() {
        UserDefaults.standard.set(window?.isVisible == true, forKey: State.isOpenKey)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: State.isOpenKey)
    }
}

@MainActor
private final class WorkspaceInspectorViewController: NSViewController {
    private let appContext: WorkspaceAppContext
    private let titleLabel = NSTextField(labelWithString: "")
    private let moduleLabel = NSTextField(labelWithString: "")
    private let primaryLabel = NSTextField(labelWithString: "")
    private let resolutionValue = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let fileSizeValue = NSTextField(labelWithString: "")
    private let tertiaryLabel = NSTextField(labelWithString: "")
    private let modifiedValue = NSTextField(labelWithString: "")
    private let quaternaryLabel = NSTextField(labelWithString: "")
    private let formatLabel = NSTextField(labelWithString: "")
    private let formatValue = NSTextField(labelWithString: "")
    private let availabilityIconView = NSImageView()
    private let availabilityTextField: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()
    private lazy var availabilityRowView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(availabilityIconView)
        stack.addArrangedSubview(availabilityTextField)
        return stack
    }()
    private let pathLabel = NSTextField(labelWithString: "")
    private let pathValue = NSTextField(labelWithString: "")

    private var metadataTask: Task<Void, Never>?
    private var observedImageID: LocalImageItem.ID?
    private var currentMetadata: LocalImageMetadata?
    private var isObserving = false

    init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
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
        view = NSVisualEffectView()
        setupView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
        observeState()
    }

    func refresh() {
        switch appContext.routeController.route.moduleID {
        case .fourKHDGallery:
            metadataTask?.cancel()
            observedImageID = nil
            currentMetadata = nil
            guard let item = appContext.galleryStore.selectedItem else {
                applyEmptyState(module: "4KHDGallery")
                return
            }
            apply(item: item)
        case .missKon:
            applyEmptyState(module: "MissKon")
            return
        case .localLibrary:
            guard let image = appContext.localLibraryStore.selectedImage else {
                observedImageID = nil
                currentMetadata = nil
                metadataTask?.cancel()
                applyEmptyState(module: "LocalLibrary")
                return
            }

            if observedImageID == image.id {
                apply(image: image, metadata: currentMetadata)
                return
            }

            observedImageID = image.id
            currentMetadata = nil
            apply(image: image, metadata: nil)
            metadataTask?.cancel()
            metadataTask = Task { [weak self, image] in
                let metadata = await LocalImageMetadataService.loadMetadata(for: [image])[image.id]
                guard !Task.isCancelled else { return }
                self?.currentMetadata = metadata
                self?.apply(image: image, metadata: metadata)
            }
        }
    }

    private func setupView() {
        guard let visualEffectView = view as? NSVisualEffectView else { return }
        visualEffectView.material = .contentBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        moduleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        moduleLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [titleLabel, moduleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2

        let fields = NSGridView(views: [
            makeRow(label: primaryLabel, value: resolutionValue),
            makeRow(label: secondaryLabel, value: fileSizeValue),
            makeRow(label: formatLabel, value: formatValue),
            makeRow(label: tertiaryLabel, value: modifiedValue),
            makeRow(label: quaternaryLabel, value: availabilityRowView),
            makeRow(label: pathLabel, value: pathValue)
        ])
        fields.rowSpacing = 8
        fields.columnSpacing = 12
        fields.column(at: 0).xPlacement = .trailing
        fields.column(at: 1).xPlacement = .leading

        let stack = NSStackView(views: [header, fields])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -18)
        ])
    }

    private func makeRow(label: NSTextField, value: NSView) -> [NSView] {
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.alignment = .right

        if let textField = value as? NSTextField {
            textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            textField.lineBreakMode = .byTruncatingMiddle
            textField.maximumNumberOfLines = label === pathLabel ? 2 : 1
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.isSelectable = true
        }
        return [label, value]
    }

    private func applyEmptyState(module: String) {
        titleLabel.stringValue = "No Selection"
        moduleLabel.stringValue = module
        primaryLabel.stringValue = "Kind"
        resolutionValue.stringValue = "-"
        secondaryLabel.stringValue = "Count"
        fileSizeValue.stringValue = "-"
        formatLabel.stringValue = "Format"
        formatValue.stringValue = "-"
        tertiaryLabel.stringValue = "Section"
        modifiedValue.stringValue = "-"
        quaternaryLabel.stringValue = "URL"
        resetAvailability()
        pathLabel.stringValue = "Path"
        pathValue.stringValue = "-"
    }

    private func apply(image: LocalImageItem, metadata: LocalImageMetadata?) {
        titleLabel.stringValue = image.title
        moduleLabel.stringValue = "LocalLibrary"
        primaryLabel.stringValue = "Resolution"
        resolutionValue.stringValue = formattedResolution(metadata) ?? "-"
        secondaryLabel.stringValue = "Size"
        fileSizeValue.stringValue = metadata?.fileSize.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "-"
        formatLabel.stringValue = "Format"
        formatValue.stringValue = image.url.pathExtension.uppercased().nilIfEmpty ?? "-"
        tertiaryLabel.stringValue = "Modified"
        modifiedValue.stringValue = metadata?.modifiedDate?.formatted(date: .numeric, time: .omitted) ?? "-"
        quaternaryLabel.stringValue = "Status"
        if metadata?.fileExists == false {
            applyAvailability(fileMissing: true)
        } else {
            applyAvailability(fileMissing: false)
        }
        pathLabel.stringValue = "Path"
        pathValue.stringValue = image.url.path
    }

    private func apply(item: GalleryItem) {
        titleLabel.stringValue = item.title
        moduleLabel.stringValue = "4KHDGallery"
        primaryLabel.stringValue = "Kind"
        resolutionValue.stringValue = item.kind.rawValue
        secondaryLabel.stringValue = "Images"
        fileSizeValue.stringValue = "\(item.imageCount)"
        formatLabel.stringValue = "Format"
        formatValue.stringValue = "-"
        tertiaryLabel.stringValue = "Section"
        modifiedValue.stringValue = item.section.title
        quaternaryLabel.stringValue = "Favorite"
        availabilityIconView.isHidden = true
        availabilityTextField.stringValue = appContext.galleryStore.isFavorite(item) ? "Yes" : "No"
        availabilityTextField.textColor = .secondaryLabelColor
        pathLabel.stringValue = "URL"
        pathValue.stringValue = item.detailURL.absoluteString
    }

    private func resetAvailability() {
        availabilityIconView.image = nil
        availabilityIconView.isHidden = true
        availabilityTextField.stringValue = "-"
        availabilityTextField.textColor = .secondaryLabelColor
    }

    private func applyAvailability(fileMissing: Bool) {
        if fileMissing {
            if #available(macOS 11.0, *) {
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                availabilityIconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
                availabilityIconView.symbolConfiguration = config
            }
            availabilityIconView.isHidden = false
            availabilityTextField.stringValue = "Original file unavailable"
            availabilityTextField.textColor = .systemOrange
        } else {
            availabilityIconView.image = nil
            availabilityIconView.isHidden = true
            availabilityTextField.stringValue = "Available"
            availabilityTextField.textColor = .secondaryLabelColor
        }
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = appContext.routeController.route
            _ = appContext.galleryStore.selectedItemID
            _ = appContext.galleryStore.selectedItem?.title
            _ = appContext.galleryStore.section
            _ = appContext.galleryStore.favorites.favorites
            _ = appContext.localLibraryStore.roots
            _ = appContext.localLibraryStore.selectedFolderID
            _ = appContext.localLibraryStore.selectedImageIndex
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.refresh()
                self.observeState()
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
