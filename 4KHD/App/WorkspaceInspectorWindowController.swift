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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "信息"
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
        if window?.isVisible != true, let mainWindow = NSApp.mainWindow {
            let origin = NSPoint(
                x: mainWindow.frame.midX - (window?.frame.width ?? 320) / 2,
                y: mainWindow.frame.midY - (window?.frame.height ?? 280) / 2
            )
            window?.setFrameOrigin(origin)
        }
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
                applyEmptyState(module: "4KHD 在线图库")
                return
            }
            apply(item: item)
        case .missKon:
            metadataTask?.cancel()
            observedImageID = nil
            currentMetadata = nil
            guard let item = appContext.missKonStore.currentItem else {
                applyEmptyState(module: "MissKon")
                return
            }
            applyMissKon(item: item)
        case .wallhaven:
            metadataTask?.cancel()
            observedImageID = nil
            currentMetadata = nil
            guard let wallpaper = appContext.wallhavenStore.effectiveSelectedWallpaper else {
                applyEmptyState(module: "Wallhaven")
                return
            }
            applyWallhaven(wallpaper: wallpaper)
        case .favorites:
            metadataTask?.cancel()
            observedImageID = nil
            currentMetadata = nil
            guard let record = appContext.favoritesModuleStore.selectedRecord else {
                applyEmptyState(module: "在线收藏")
                return
            }
            applyFavoriteRecord(record)
        case .localLibrary:
            guard let image = appContext.localLibraryStore.selectedImage else {
                observedImageID = nil
                currentMetadata = nil
                metadataTask?.cancel()
                applyEmptyState(module: "本地图库")
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
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 3
        titleLabel.preferredMaxLayoutWidth = 180
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
            textField.lineBreakMode = .byWordWrapping
            textField.maximumNumberOfLines = 0
            textField.preferredMaxLayoutWidth = 180
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.isSelectable = true
        }
        return [label, value]
    }

    private func applyEmptyState(module: String) {
        titleLabel.stringValue = "未选择项目"
        moduleLabel.stringValue = module
        primaryLabel.stringValue = "类型"
        resolutionValue.stringValue = "-"
        secondaryLabel.stringValue = "数量"
        fileSizeValue.stringValue = "-"
        formatLabel.stringValue = "格式"
        formatValue.stringValue = "-"
        tertiaryLabel.stringValue = "栏目"
        modifiedValue.stringValue = "-"
        quaternaryLabel.stringValue = "链接"
        resetAvailability()
        pathLabel.stringValue = "路径"
        pathValue.stringValue = "-"
    }

    private func apply(image: LocalImageItem, metadata: LocalImageMetadata?) {
        titleLabel.stringValue = image.title
        moduleLabel.stringValue = "本地图库"
        primaryLabel.stringValue = "分辨率"
        resolutionValue.stringValue = formattedResolution(metadata) ?? "-"
        secondaryLabel.stringValue = "大小"
        fileSizeValue.stringValue = metadata?.fileSize.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "-"
        formatLabel.stringValue = "格式"
        formatValue.stringValue = image.url.pathExtension.uppercased().nilIfEmpty ?? "-"
        tertiaryLabel.stringValue = "修改日期"
        modifiedValue.stringValue = metadata?.modifiedDate?.formatted(date: .numeric, time: .omitted) ?? "-"
        quaternaryLabel.stringValue = "状态"
        if metadata?.fileExists == false {
            applyAvailability(fileMissing: true)
        } else {
            applyAvailability(fileMissing: false)
        }
        pathLabel.stringValue = "路径"
        pathValue.stringValue = image.url.path
    }

    private func apply(item: GalleryItem) {
        titleLabel.stringValue = item.title
        moduleLabel.stringValue = "4KHD 在线图库"
        primaryLabel.stringValue = "类型"
        resolutionValue.stringValue = item.kind.rawValue
        secondaryLabel.stringValue = "图片数"
        fileSizeValue.stringValue = "\(item.imageCount)"
        formatLabel.stringValue = "格式"
        formatValue.stringValue = "-"
        tertiaryLabel.stringValue = "栏目"
        modifiedValue.stringValue = item.section.title
        quaternaryLabel.stringValue = "已收藏"
        availabilityIconView.isHidden = true
        availabilityTextField.stringValue = appContext.galleryStore.isFavorite(item) ? "是" : "否"
        availabilityTextField.textColor = .secondaryLabelColor
        pathLabel.stringValue = "链接"
        pathValue.stringValue = item.detailURL.absoluteString
    }

    private func applyMissKon(item: MissKonItem) {
        titleLabel.stringValue = item.title
        moduleLabel.stringValue = "MissKon"
        primaryLabel.stringValue = "标签"
        resolutionValue.stringValue = item.tags.isEmpty ? "-" : item.tags.joined(separator: ", ")
        secondaryLabel.stringValue = "图片数"
        fileSizeValue.stringValue = "\(item.imageCount)"
        formatLabel.stringValue = "页数"
        formatValue.stringValue = "\(item.pageCount)"
        tertiaryLabel.stringValue = "栏目"
        modifiedValue.stringValue = item.section.title
        quaternaryLabel.stringValue = "已收藏"
        availabilityIconView.isHidden = true
        availabilityTextField.stringValue = appContext.missKonStore.isFavorite(item) ? "是" : "否"
        availabilityTextField.textColor = .secondaryLabelColor
        pathLabel.stringValue = "链接"
        pathValue.stringValue = item.detailURL.absoluteString
    }

    private func applyFavoriteRecord(_ record: FavoriteRecord) {
        titleLabel.stringValue = record.title
        moduleLabel.stringValue = "在线收藏"
        primaryLabel.stringValue = "来源"
        resolutionValue.stringValue = FavoriteSource.source(for: record)?.title ?? "-"
        secondaryLabel.stringValue = "图片数"
        fileSizeValue.stringValue = "\(record.imageCount)"
        formatLabel.stringValue = "页数"
        formatValue.stringValue = "\(record.pageCount)"
        tertiaryLabel.stringValue = "描述"
        modifiedValue.stringValue = record.subtitle.nilIfEmpty ?? "-"
        quaternaryLabel.stringValue = "已收藏"
        availabilityIconView.isHidden = true
        availabilityTextField.stringValue = "是"
        availabilityTextField.textColor = .secondaryLabelColor
        pathLabel.stringValue = "链接"
        pathValue.stringValue = record.detailURL
    }

    private func resetAvailability() {
        availabilityIconView.image = nil
        availabilityIconView.isHidden = true
        availabilityTextField.stringValue = "-"
        availabilityTextField.textColor = .secondaryLabelColor
    }

    private func applyWallhaven(wallpaper: Wallpaper) {
        titleLabel.stringValue = wallpaper.tags.prefix(5).joined(separator: ", ").nilIfEmpty ?? wallpaper.displayName
        moduleLabel.stringValue = "Wallhaven"
        primaryLabel.stringValue = "分辨率"
        resolutionValue.stringValue = wallpaper.resolutionText
        secondaryLabel.stringValue = "大小"
        fileSizeValue.stringValue = wallpaper.formattedFileSize
        formatLabel.stringValue = "格式"
        formatValue.stringValue = wallpaper.fileType?.replacingOccurrences(of: "image/", with: "").uppercased() ?? "-"
        tertiaryLabel.stringValue = "分类"
        modifiedValue.stringValue = wallpaper.category ?? "-"
        quaternaryLabel.stringValue = "内容分级"
        availabilityIconView.isHidden = true
        availabilityTextField.stringValue = wallpaper.purity.title
        availabilityTextField.textColor = .secondaryLabelColor
        pathLabel.stringValue = "链接"
        pathValue.stringValue = wallpaper.sourcePageUrl.absoluteString
    }

    private func applyAvailability(fileMissing: Bool) {
        if fileMissing {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            availabilityIconView.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "原始文件不可用"
            )
            availabilityIconView.symbolConfiguration = config
            availabilityIconView.isHidden = false
            availabilityTextField.stringValue = "原始文件不可用"
            availabilityTextField.textColor = .systemOrange
        } else {
            availabilityIconView.image = nil
            availabilityIconView.isHidden = true
            availabilityTextField.stringValue = "可用"
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
            _ = appContext.missKonStore.selectedItemID
            _ = appContext.missKonStore.currentItem?.title
            _ = appContext.missKonStore.section
            _ = appContext.missKonStore.favorites.favorites
            _ = appContext.wallhavenStore.selectedWallpaperID
            _ = appContext.wallhavenStore.effectiveSelectedWallpaper
            _ = appContext.wallhavenStore.isResolvingDetail
            _ = appContext.wallhavenStore.favorites.favorites
            _ = appContext.favoritesModuleStore.selectedRecordID
            _ = appContext.favoritesModuleStore.selectedRecord
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
