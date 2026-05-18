import AppKit

extension LocalImageContentViewController {
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection,
              tableView.selectedRow >= 0,
              filteredEntries.indices.contains(tableView.selectedRow) else { return }
        localLibrary.selectImage(at: filteredEntries[tableView.selectedRow].originalIndex)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        filteredEntries.indices.contains(row)
    }

    func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard filteredEntries.indices.contains(row) else { return nil }
        if tableView.selectedRow != row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            localLibrary.selectImage(at: filteredEntries[row].originalIndex)
        }

        let menu = NSMenu(title: "LocalImageListMenu")
        menu.autoenablesItems = false
        menu.addItem(makeMenuItem(title: "设置为桌面壁纸", symbolName: "photo.fill", action: #selector(setDesktopWallpaper)))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "快速预览", symbolName: "eye", action: #selector(contextQuickLook)))
        menu.addItem(makeMenuItem(title: "详细信息", symbolName: "info.circle", action: #selector(showSelectedInfo)))
        menu.addItem(makeMenuItem(title: "在 Finder 中显示", symbolName: "folder", action: #selector(revealInFinder)))
        menu.addItem(makeMenuItem(title: "复制路径", symbolName: "doc.on.doc", action: #selector(copyPath)))
        menu.addItem(makeMenuItem(title: "打开文件", symbolName: "arrow.up.right.square", action: #selector(openFile)))
        return menu
    }

    func quickLookSelected() -> Bool {
        guard let image = selectedImageForMenu() else { return false }
        LocalQuickLookController.shared.open(url: image.url)
        return true
    }

    func showInfo(for image: LocalImageItem) {
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

    private func makeMenuItem(title: String, symbolName: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        return item
    }

    private func selectedImageForMenu() -> LocalImageItem? {
        if tableView.selectedRow >= 0, filteredEntries.indices.contains(tableView.selectedRow) {
            return filteredEntries[tableView.selectedRow].image
        }
        return localLibrary.selectedImage
    }

    @objc private func setDesktopWallpaper() {
        guard let image = selectedImageForMenu() else { return }
        LocalDesktopWallpaperSetter.setDesktopWallpaper(image.url)
    }

    @objc private func contextQuickLook() {
        _ = quickLookSelected()
    }

    @objc private func showSelectedInfo() {
        guard let image = selectedImageForMenu() else { return }
        showInfo(for: image)
    }

    @objc private func revealInFinder() {
        guard let image = selectedImageForMenu() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([image.url])
    }

    @objc private func copyPath() {
        guard let image = selectedImageForMenu() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(image.url.path, forType: .string)
    }

    @objc private func openFile() {
        guard let image = selectedImageForMenu() else { return }
        NSWorkspace.shared.open(image.url)
    }

    @objc func importRootFolder() {
        importRootFolderAction()
    }
}

final class LocalImageListTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var quickLookHandler: (() -> Bool)?

    override func accessibilityLabel() -> String? {
        "Local Image List"
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return contextMenuProvider?(row)
    }

    override func keyDown(with event: NSEvent) {
        let handled = WorkspaceKeyboardHandler.keyDown(
            event,
            context: WorkspaceKeyboardContext(quickLook: quickLookHandler)
        )
        if handled {
            return
        }
        super.keyDown(with: event)
    }

    override func viewWillStartLiveResize() {
        workspaceWillStartLiveResize()
        super.viewWillStartLiveResize()
    }

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        super.viewDidEndLiveResize()
    }
}

extension LocalImageListTableView: WorkspaceLiveResizeScrollerHiding {}

final class LocalImageListCellView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("LocalImageListCellView")

    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let resolutionLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private var imageTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        imageTask?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
    }

    func configure(image: LocalImageItem, metadata: LocalImageMetadata?) {
        titleLabel.stringValue = image.title
        resolutionLabel.stringValue = formattedResolution(metadata) ?? ""
        metadataLabel.stringValue = formattedSecondaryMetadata(metadata) ?? image.url.deletingLastPathComponent().path
        thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)

        imageTask?.cancel()
        imageTask = Task { [weak self] in
            let loaded = await LocalImageCache.shared.image(for: image.url, maxPixelSize: 160)
            guard !Task.isCancelled else { return }
            self?.thumbnailView.image = loaded ?? NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        }
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 4
        thumbnailView.layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1

        for label in [resolutionLabel, metadataLabel] {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .tertiaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
        }

        let stack = NSStackView(views: [titleLabel, resolutionLabel, metadataLabel])
        stack.orientation = .vertical
        stack.spacing = 3
        stack.alignment = .leading
        stack.distribution = .gravityAreas

        addSubview(thumbnailView)
        addSubview(stack)
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            thumbnailView.widthAnchor.constraint(equalToConstant: 56),
            stack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
