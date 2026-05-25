import AppKit
import Observation

@MainActor
final class LocalImageContentViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, WorkspaceFocusable {
    typealias Entry = (originalIndex: Int, image: LocalImageItem)

    let localLibrary: LocalLibraryStore
    private let preferences: LocalLibraryContentPreferences
    private let detailPane: WorkspaceDetailPaneController
    let importRootFolderAction: () -> Void
    private let gridView = LocalImageGridContainerView()
    let tableView = LocalImageListTableView()
    private let scrollView = NSScrollView()

    private var activeView: NSView?
    var metadataByImageID: [LocalImageItem.ID: LocalImageMetadata] = [:]
    var filteredEntries: [Entry] = []
    private var observedImageIDs: [LocalImageItem.ID] = []
    private var lastAppliedListSignature: [LocalImageListRowSignature] = []
    private var metadataTask: Task<Void, Never>?
    private var availabilityTask: Task<Void, Never>?
    private var isObserving = false
    private var isObservingGridLayoutPreferences = false
    var isApplyingSelection = false
    private let reloadQueue = WorkspaceCoalescingQueue(
        name: "LocalContent Reload",
        interval: 0.05,
        maxInterval: 0.12
    )

    init(
        localLibrary: LocalLibraryStore,
        preferences: LocalLibraryContentPreferences,
        detailPane: WorkspaceDetailPaneController,
        importRootFolderAction: @escaping () -> Void
    ) {
        self.localLibrary = localLibrary
        self.preferences = preferences
        self.detailPane = detailPane
        self.importRootFolderAction = importRootFolderAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        metadataTask?.cancel()
        availabilityTask?.cancel()
    }

    override func loadView() {
        view = NSView()
        setupGridView()
        setupTableView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadContent()
        observeState()
        observeGridLayoutPreferences()
    }

    func focus() {
        switch preferences.layout {
        case .list:
            tableView.window?.makeFirstResponderUnlessDescendantIsFirstResponder(tableView)
        case .grid:
            gridView.focus()
        }
    }

    private func setupGridView() {
        gridView.onSelect = { [weak self] index in
            self?.localLibrary.selectImage(at: index)
        }
        gridView.onOpenDetail = { [weak self] in
            self?.detailPane.setPresented(true)
        }
        gridView.onQuickLook = { image in
            LocalQuickLookController.shared.open(url: image.url)
        }
        gridView.onShowInfo = { [weak self] image in
            self?.showInfo(for: image)
        }
    }

    private func setupTableView() {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.hasVerticalScroller = true
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Image"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 84
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .controlBackgroundColor
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
        tableView.contextMenuProvider = { [weak self] row in
            self?.makeContextMenu(forRow: row)
        }
        tableView.quickLookHandler = { [weak self] in
            self?.quickLookSelected() ?? false
        }
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedTableImageInDetail)
    }

    private func reloadContent() {
        filteredEntries = makeFilteredEntries()

        if localLibrary.roots.isEmpty {
            setActiveView(makePlaceholderView(title: "还没有本地目录", detail: "导入一个图片目录开始浏览。", showsImportButton: true))
            return
        }
        let selectedImages = localLibrary.selectedImages
        guard !selectedImages.isEmpty else {
            setActiveView(makePlaceholderView(title: "当前目录没有图片", detail: selectedPlaceholderDetail, showsImportButton: false))
            return
        }
        guard !filteredEntries.isEmpty else {
            setActiveView(makePlaceholderView(title: "没有匹配图片", detail: preferences.searchText, showsImportButton: false))
            return
        }

        loadMetadataIfNeeded(for: metadataVisibleImages)
        switch preferences.layout {
        case .grid:
            let gridLayoutPreferences = currentGridLayoutPreferences()
            setActiveView(gridView)
            gridView.update(
                items: filteredEntries,
                metadataByImageID: metadataByImageID,
                selectedImageID: localLibrary.selectedImage?.id,
                minimumColumnCount: gridLayoutPreferences.minimumColumnCount,
                maximumColumnCount: gridLayoutPreferences.maximumColumnCount,
                preferredCardMinimumWidth: gridLayoutPreferences.preferredCardMinimumWidth
            )
        case .list:
            setActiveView(scrollView)
            let signature = listSignature()
            if signature != lastAppliedListSignature {
                lastAppliedListSignature = signature
                tableView.reloadData()
            }
            syncTableSelection()
        }
    }

    private func setActiveView(_ nextView: NSView) {
        animateViewTransition(to: nextView, activeView: &activeView)
    }

    private func makePlaceholderView(title: String, detail: String?, showsImportButton: Bool) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center

        let stack = NSStackView(views: [titleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8

        if let detail, !detail.isEmpty {
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            detailLabel.textColor = .tertiaryLabelColor
            detailLabel.alignment = .center
            detailLabel.maximumNumberOfLines = 2
            stack.addArrangedSubview(detailLabel)
        }

        if showsImportButton {
            let button = NSButton(
                title: "选择目录...",
                target: self,
                action: #selector(importRootFolder)
            )
            button.bezelStyle = .rounded
            stack.addArrangedSubview(button)
        }

        let container = NSView()
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let readableArea = container.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: readableArea.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: readableArea.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: readableArea.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: readableArea.trailingAnchor, constant: -24)
        ])
        return container
    }

    private func observeState() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = localLibrary.roots
            _ = localLibrary.selectedFolderID
            _ = localLibrary.selectedImageIndex
            _ = preferences.searchText
            _ = preferences.layout
            _ = preferences.sortField
            _ = preferences.sortDirection
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.reloadQueue.add(id: "reload") { [weak self] in
                    self?.reloadContent()
                }
                self.observeState()
            }
        }
    }

    private func observeGridLayoutPreferences() {
        guard !isObservingGridLayoutPreferences else { return }
        isObservingGridLayoutPreferences = true
        withObservationTracking {
            _ = preferences.gridColumnCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingGridLayoutPreferences = false
                self.updateGridLayoutPreferences()
                self.observeGridLayoutPreferences()
            }
        }
    }

    private func updateGridLayoutPreferences() {
        guard preferences.layout == .grid, activeView === gridView else { return }
        let gridLayoutPreferences = currentGridLayoutPreferences()
        gridView.updateLayoutPreferences(
            minimumColumnCount: gridLayoutPreferences.minimumColumnCount,
            maximumColumnCount: gridLayoutPreferences.maximumColumnCount,
            preferredCardMinimumWidth: gridLayoutPreferences.preferredCardMinimumWidth
        )
    }

    private func currentGridLayoutPreferences() -> GridLayoutPreferences {
        let columnLimits = preferences.gridColumnLimits()
        return GridLayoutPreferences(
            minimumColumnCount: columnLimits.minimum,
            maximumColumnCount: columnLimits.maximum,
            preferredCardMinimumWidth: 136
        )
    }

    private func loadMetadataIfNeeded(for images: [LocalImageItem]) {
        let ids = images.map(\.id)
        guard ids != observedImageIDs else { return }
        observedImageIDs = ids
        metadataTask?.cancel()
        availabilityTask?.cancel()

        metadataTask = Task { [weak self] in
            let metadata = await LocalImageMetadataService.loadMetadata(for: images)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.metadataByImageID.merge(metadata) { _, new in new }
            self.reloadContent()
        }
        availabilityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let availability = await LocalImageMetadataService.loadAvailability(for: images)
                guard !Task.isCancelled else { return }
                var changed = false
                for (id, fileExists) in availability {
                    guard let metadata = self?.metadataByImageID[id], metadata.fileExists != fileExists else { continue }
                    self?.metadataByImageID[id] = LocalImageMetadata(
                        fileSize: metadata.fileSize,
                        modifiedDate: metadata.modifiedDate,
                        pixelWidth: metadata.pixelWidth,
                        pixelHeight: metadata.pixelHeight,
                        fileExists: fileExists
                    )
                    changed = true
                }
                if changed {
                    self?.reloadContent()
                }
            }
        }
    }

    private func makeFilteredEntries() -> [Entry] {
        let query = preferences.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = Array(localLibrary.selectedImages.enumerated()).map { ($0.offset, $0.element) }
        let filtered = query.isEmpty ? entries : entries.filter { $0.1.title.localizedStandardContains(query) }
        return filtered.sorted(by: { compare($0.1, $1.1) == .orderedAscending })
    }

    private var selectedPlaceholderDetail: String? {
        if localLibrary.selectedFolderID == LocalLibraryStore.allImagesFolderID {
            return "我的图片"
        }
        return localLibrary.selectedFolder?.title
    }

    private var metadataVisibleImages: [LocalImageItem] {
        let selectedID = localLibrary.selectedImage?.id
        let selectedRow = selectedID.flatMap { id in
            filteredEntries.firstIndex { $0.image.id == id }
        } ?? 0
        let lowerBound = max(0, selectedRow - 80)
        let upperBound = min(filteredEntries.count, selectedRow + 160)
        return filteredEntries[lowerBound..<upperBound].map(\.image)
    }

    private func compare(_ lhs: LocalImageItem, _ rhs: LocalImageItem) -> ComparisonResult {
        let result: ComparisonResult
        switch preferences.sortField {
        case .name:
            result = lhs.title.localizedStandardCompare(rhs.title)
        case .modifiedDate:
            result = compare(metadataByImageID[lhs.id]?.modifiedDate, metadataByImageID[rhs.id]?.modifiedDate)
        case .fileSize:
            result = compare(metadataByImageID[lhs.id]?.fileSize, metadataByImageID[rhs.id]?.fileSize)
        }
        guard preferences.sortDirection == .descending else { return result }
        if result == .orderedAscending { return .orderedDescending }
        if result == .orderedDescending { return .orderedAscending }
        return .orderedSame
    }

    private func compare<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        let lhs = lhs
        let rhs = rhs
        if lhs == rhs {
            return .orderedSame
        }
        if let lhs, let rhs {
            return lhs < rhs ? .orderedAscending : .orderedDescending
        }
        return lhs == nil ? .orderedDescending : .orderedAscending
    }

    private func syncTableSelection() {
        guard let selectedID = localLibrary.selectedImage?.id,
              let row = filteredEntries.firstIndex(where: { $0.image.id == selectedID }) else {
            tableView.deselectAll(nil)
            return
        }
        guard tableView.selectedRow != row else { return }
        isApplyingSelection = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        isApplyingSelection = false
    }

    private func listSignature() -> [LocalImageListRowSignature] {
        filteredEntries.map { entry in
            let metadata = metadataByImageID[entry.image.id]
            return LocalImageListRowSignature(
                id: entry.image.id,
                title: entry.image.title,
                resolution: formattedResolution(metadata),
                secondaryMetadata: formattedSecondaryMetadata(metadata)
                    ?? entry.image.url.deletingLastPathComponent().path
            )
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filteredEntries.indices.contains(row) else { return nil }
        let cell = tableView.makeView(
            withIdentifier: LocalImageListCellView.reuseID,
            owner: self
        ) as? LocalImageListCellView ?? LocalImageListCellView()
        let image = filteredEntries[row].image
        cell.configure(image: image, metadata: metadataByImageID[image.id])
        return cell
    }

    @objc private func openSelectedTableImageInDetail() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard filteredEntries.indices.contains(row) else { return }
        localLibrary.selectImage(at: filteredEntries[row].originalIndex)
        detailPane.setPresented(true)
    }
}

private struct LocalImageListRowSignature: Equatable {
    let id: LocalImageItem.ID
    let title: String
    let resolution: String?
    let secondaryMetadata: String
}

private struct GridLayoutPreferences {
    let minimumColumnCount: Int?
    let maximumColumnCount: Int?
    let preferredCardMinimumWidth: CGFloat
}
