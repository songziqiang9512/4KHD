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
    private let resolutionValue = NSTextField(labelWithString: "")
    private let fileSizeValue = NSTextField(labelWithString: "")
    private let modifiedValue = NSTextField(labelWithString: "")
    private let availabilityValue = NSTextField(labelWithString: "")
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
        guard appContext.routeController.route.moduleID == .localLibrary,
              let image = appContext.localLibraryStore.selectedImage else {
            observedImageID = nil
            currentMetadata = nil
            metadataTask?.cancel()
            applyEmptyState()
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
            makeRow(title: "Resolution", value: resolutionValue),
            makeRow(title: "Size", value: fileSizeValue),
            makeRow(title: "Modified", value: modifiedValue),
            makeRow(title: "Available", value: availabilityValue),
            makeRow(title: "Path", value: pathValue)
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

    private func makeRow(title: String, value: NSTextField) -> [NSView] {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.alignment = .right

        value.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        value.lineBreakMode = .byTruncatingMiddle
        value.maximumNumberOfLines = title == "Path" ? 2 : 1
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return [label, value]
    }

    private func applyEmptyState() {
        titleLabel.stringValue = "No Selection"
        moduleLabel.stringValue = "LocalLibrary"
        resolutionValue.stringValue = "-"
        fileSizeValue.stringValue = "-"
        modifiedValue.stringValue = "-"
        availabilityValue.stringValue = "-"
        pathValue.stringValue = "-"
    }

    private func apply(image: LocalImageItem, metadata: LocalImageMetadata?) {
        titleLabel.stringValue = image.title
        moduleLabel.stringValue = "LocalLibrary"
        resolutionValue.stringValue = formattedResolution(metadata) ?? "-"
        fileSizeValue.stringValue = metadata?.fileSize.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "-"
        modifiedValue.stringValue = metadata?.modifiedDate?.formatted(date: .numeric, time: .omitted) ?? "-"
        availabilityValue.stringValue = metadata?.fileExists == false ? "Missing" : "Available"
        pathValue.stringValue = image.url.path
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = appContext.routeController.route
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
