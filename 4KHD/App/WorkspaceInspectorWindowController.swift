import AppKit
import Observation

@MainActor
final class WorkspaceInspectorWindowController: NSWindowController, NSWindowDelegate {
    private enum State {
        static let isOpenKey = "com.songziqiang.4khd.workspaceInspectorIsOpen.v1"
        static let frameAutosaveName = "WorkspaceInspectorWindow.v2"
    }

    private let inspectorViewController: WorkspaceInspectorViewController

    init(appContext: WorkspaceAppContext) {
        inspectorViewController = WorkspaceInspectorViewController(appContext: appContext)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "信息"
        panel.contentViewController = inspectorViewController
        panel.contentMinSize = NSSize(width: 360, height: 320)
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [.fullScreenAuxiliary]
        if !panel.setFrameUsingName(State.frameAutosaveName) {
            panel.center()
        }
        panel.setFrameAutosaveName(State.frameAutosaveName)

        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    static var shouldOpenAtStartup: Bool {
        UserDefaults.standard.bool(forKey: State.isOpenKey)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        inspectorViewController.setActive(true)
        UserDefaults.standard.set(true, forKey: State.isOpenKey)
    }

    func saveState() {
        UserDefaults.standard.set(
            window?.isVisible == true && window?.isMiniaturized != true,
            forKey: State.isOpenKey
        )
    }

    func windowWillClose(_: Notification) {
        inspectorViewController.setActive(false)
        UserDefaults.standard.set(false, forKey: State.isOpenKey)
    }

    func windowDidMiniaturize(_: Notification) {
        inspectorViewController.setActive(false)
        UserDefaults.standard.set(false, forKey: State.isOpenKey)
    }

    func windowDidDeminiaturize(_: Notification) {
        inspectorViewController.setActive(true)
        UserDefaults.standard.set(true, forKey: State.isOpenKey)
    }
}

@MainActor
private struct InspectorSnapshot {
    let symbolName: String
    let title: String
    let moduleTitle: String
    let summary: String?
    let sections: [InspectorSection]
}

@MainActor
private struct InspectorSection {
    let title: String
    let rows: [InspectorRow]
}

@MainActor
private struct InspectorRow {
    enum Action {
        case open(URL)
        case reveal(URL)
    }

    let label: String
    let value: String
    let valueColor: NSColor
    let allowsWrapping: Bool
    let action: Action?

    init(
        label: String,
        value: String,
        valueColor: NSColor = .labelColor,
        allowsWrapping: Bool = true,
        action: Action? = nil
    ) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.allowsWrapping = allowsWrapping
        self.action = action
    }
}

private final class InspectorFlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}

@MainActor
private final class WorkspaceInspectorViewController: NSViewController {
    private let appContext: WorkspaceAppContext
    private let sourceIconView = NSImageView()
    private let moduleLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let documentView = InspectorFlippedView()
    private let contentStack = NSStackView()

    private var metadataTask: Task<Void, Never>?
    private var metadataRequestID = UUID()
    private var observedImageID: LocalImageItem.ID?
    private var currentMetadata: LocalImageMetadata?
    private var isActive = false
    private var observationGeneration = UUID()
    private var rowActions: [Int: InspectorRow.Action] = [:]
    private var nextActionTag = 1

    init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    deinit {
        metadataTask?.cancel()
    }

    override func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .contentBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .followsWindowActiveState
        view = visualEffectView
        setupView()
    }

    func setActive(_ active: Bool) {
        guard isActive != active else {
            if active { refresh() }
            return
        }
        isActive = active
        observationGeneration = UUID()
        if active {
            refresh()
            observeState(generation: observationGeneration)
        } else {
            metadataTask?.cancel()
            metadataTask = nil
        }
    }

    func refresh() {
        guard isViewLoaded else { return }
        switch appContext.routeController.route.moduleID {
        case .fourKHDGallery:
            cancelLocalMetadata()
            guard let item = appContext.galleryStore.selectedItem else {
                renderEmpty(module: "4KHD 在线图库", symbolName: "photo.on.rectangle")
                return
            }
            render(snapshot(for: item, moduleTitle: "4KHD 在线图库"))
        case .missKon:
            cancelLocalMetadata()
            guard let item = appContext.missKonStore.currentItem else {
                renderEmpty(module: "MissKon", symbolName: "person.crop.square")
                return
            }
            render(snapshot(for: item, moduleTitle: "MissKon"))
        case .wallhaven:
            cancelLocalMetadata()
            guard let wallpaper = appContext.wallhavenStore.effectiveSelectedWallpaper else {
                renderEmpty(module: "Wallhaven", symbolName: "photo.stack")
                return
            }
            render(snapshot(for: wallpaper, moduleTitle: "Wallhaven"))
        case .favorites:
            cancelLocalMetadata()
            guard let record = appContext.favoritesModuleStore.selectedRecord else {
                renderEmpty(module: "我的收藏", symbolName: "heart")
                return
            }
            render(snapshot(for: record))
        case .knitGallery:
            cancelLocalMetadata()
            guard let item = appContext.knitStore.selectedItem else {
                renderEmpty(module: "爱妹子", symbolName: "photo.on.rectangle.angled")
                return
            }
            render(snapshot(for: item, moduleTitle: "爱妹子"))
        case .mrdsGallery:
            cancelLocalMetadata()
            guard let item = appContext.mrdsStore.selectedItem else {
                renderEmpty(module: "每日大赛", symbolName: "flag.checkered")
                return
            }
            render(snapshot(for: item, moduleTitle: "每日大赛"))
        case .quanjiGallery:
            cancelLocalMetadata()
            guard let item = appContext.quanjiStore.selectedItem else {
                renderEmpty(module: "木瓜视频", symbolName: "play.rectangle")
                return
            }
            render(snapshot(for: item, moduleTitle: "木瓜视频", store: appContext.quanjiStore))
        case .pornyGallery:
            cancelLocalMetadata()
            guard let item = appContext.pornyStore.selectedItem else {
                renderEmpty(module: "91PORNY", symbolName: "play.tv")
                return
            }
            render(snapshot(for: item, moduleTitle: "91PORNY", store: appContext.pornyStore))
        case .tangxinGallery:
            cancelLocalMetadata()
            guard let item = appContext.tangxinStore.selectedItem else {
                renderEmpty(module: "糖心Vlog", symbolName: "play.rectangle.on.rectangle")
                return
            }
            render(snapshot(for: item, moduleTitle: "糖心Vlog", store: appContext.tangxinStore))
        case .localLibrary:
            guard let image = appContext.localLibraryStore.selectedImage else {
                cancelLocalMetadata()
                renderEmpty(module: "本地图库", symbolName: "photo")
                return
            }
            refreshLocalImage(image)
        }
    }

    private func setupView() {
        sourceIconView.imageScaling = .scaleProportionallyDown
        sourceIconView.contentTintColor = .secondaryLabelColor
        sourceIconView.setContentHuggingPriority(.required, for: .horizontal)
        sourceIconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        moduleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        moduleLabel.textColor = .secondaryLabelColor
        moduleLabel.lineBreakMode = .byTruncatingTail

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 4
        titleLabel.isSelectable = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.maximumNumberOfLines = 3
        summaryLabel.isSelectable = true
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerTextStack = NSStackView(views: [moduleLabel, titleLabel, summaryLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 3
        headerTextStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [sourceIconView, headerTextStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .top
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        view.addSubview(headerStack)
        view.addSubview(separator)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            sourceIconView.widthAnchor.constraint(equalToConstant: 38),
            sourceIconView.heightAnchor.constraint(equalToConstant: 38),

            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            separator.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 1),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20),
        ])
    }

    private func refreshLocalImage(_ image: LocalImageItem) {
        let previousMetadata = observedImageID == image.id ? currentMetadata : nil
        observedImageID = image.id
        if previousMetadata == nil {
            currentMetadata = nil
        }
        render(snapshot(for: image, metadata: previousMetadata))

        metadataTask?.cancel()
        let requestID = UUID()
        metadataRequestID = requestID
        metadataTask = Task { [weak self, image] in
            let metadata = await LocalImageMetadataService.loadMetadata(for: [image])[image.id]
            guard !Task.isCancelled, let self,
                  self.isActive,
                  self.metadataRequestID == requestID,
                  self.appContext.routeController.route.moduleID == .localLibrary,
                  self.appContext.localLibraryStore.selectedImage?.id == image.id else { return }
            self.currentMetadata = metadata
            self.render(self.snapshot(for: image, metadata: metadata))
        }
    }

    private func cancelLocalMetadata() {
        metadataTask?.cancel()
        metadataTask = nil
        metadataRequestID = UUID()
        observedImageID = nil
        currentMetadata = nil
    }

    private func renderEmpty(module: String, symbolName: String) {
        render(
            InspectorSnapshot(
                symbolName: symbolName,
                title: "未选择项目",
                moduleTitle: module,
                summary: "在主窗口中选择一个项目后，这里会显示完整信息。",
                sections: []
            )
        )
    }

    private func render(_ snapshot: InspectorSnapshot) {
        sourceIconView.image = NSImage(
            systemSymbolName: snapshot.symbolName,
            accessibilityDescription: snapshot.moduleTitle
        )
        sourceIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 27, weight: .medium)
        moduleLabel.stringValue = snapshot.moduleTitle
        titleLabel.stringValue = snapshot.title
        summaryLabel.stringValue = snapshot.summary ?? ""
        summaryLabel.isHidden = snapshot.summary?.isEmpty != false

        for arrangedSubview in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        rowActions.removeAll(keepingCapacity: true)
        nextActionTag = 1

        if snapshot.sections.isEmpty {
            let emptyState = makeEmptyStateView()
            contentStack.addArrangedSubview(emptyState)
            emptyState.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        } else {
            for section in snapshot.sections where !section.rows.isEmpty {
                let sectionView = makeSectionView(section)
                contentStack.addArrangedSubview(sectionView)
                sectionView.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            }
        }
    }

    private func makeEmptyStateView() -> NSView {
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        iconView.contentTintColor = .tertiaryLabelColor
        let stack = NSStackView(views: [iconView])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 0, bottom: 12, right: 0)
        return stack
    }

    private func makeSectionView(_ section: InspectorSection) -> NSView {
        let heading = NSTextField(labelWithString: section.title)
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        let gridRows = section.rows.map(makeGridRow)
        let grid = NSGridView(views: gridRows)
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).width = 82
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for rowIndex in section.rows.indices {
            grid.row(at: rowIndex).yPlacement = .top
        }

        let stack = NSStackView(views: [heading, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        grid.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeGridRow(_ row: InspectorRow) -> [NSView] {
        let label = NSTextField(labelWithString: row.label)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail

        let value = NSTextField(labelWithString: row.value)
        value.font = .systemFont(ofSize: 12.5)
        value.textColor = row.valueColor
        value.isSelectable = true
        value.maximumNumberOfLines = row.allowsWrapping ? 0 : 1
        value.lineBreakMode = row.allowsWrapping ? .byWordWrapping : .byTruncatingMiddle
        value.setContentHuggingPriority(.defaultLow, for: .horizontal)
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        guard let action = row.action else { return [label, value] }

        let button = NSButton(
            image: NSImage(
                systemSymbolName: action.symbolName,
                accessibilityDescription: action.accessibilityDescription
            ) ?? NSImage(),
            target: self,
            action: #selector(performRowAction(_:))
        )
        button.tag = nextActionTag
        rowActions[nextActionTag] = action
        nextActionTag += 1
        button.isBordered = false
        button.bezelStyle = .inline
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .linkColor
        button.toolTip = action.accessibilityDescription
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        let valueStack = NSStackView(views: [value, button])
        valueStack.orientation = .horizontal
        valueStack.alignment = .top
        valueStack.spacing = 6
        valueStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        value.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        return [label, valueStack]
    }

    @objc private func performRowAction(_ sender: NSButton) {
        guard let action = rowActions[sender.tag] else { return }
        switch action {
        case let .open(url):
            guard url.scheme?.lowercased() == "https", url.host != nil else { return }
            NSWorkspace.shared.open(url)
        case let .reveal(url):
            guard url.isFileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func snapshot(for image: LocalImageItem, metadata: LocalImageMetadata?) -> InspectorSnapshot {
        let fileStatus: InspectorRow
        if let metadata {
            fileStatus = metadata.fileExists
                ? InspectorRow(label: "状态", value: "可用", valueColor: .secondaryLabelColor)
                : InspectorRow(label: "状态", value: "原始文件不可用", valueColor: .systemOrange)
        } else {
            fileStatus = InspectorRow(label: "状态", value: "读取中…", valueColor: .secondaryLabelColor)
        }
        return InspectorSnapshot(
            symbolName: "photo",
            title: image.title,
            moduleTitle: "本地图库",
            summary: image.url.deletingLastPathComponent().lastPathComponent,
            sections: compactSections([
                section("文件", rows: [
                    row("分辨率", formattedResolution(metadata)),
                    row("格式", image.url.pathExtension.uppercased().nilIfEmpty),
                    row("大小", metadata?.fileSize.map {
                        ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                    }),
                    row("修改日期", metadata?.modifiedDate?.formatted(date: .abbreviated, time: .shortened)),
                    fileStatus,
                ]),
                section("位置", rows: [
                    row("路径", image.url.path, allowsWrapping: false, action: .reveal(image.url)),
                ]),
            ])
        )
    }

    private func snapshot(for item: GalleryItem, moduleTitle: String) -> InspectorSnapshot {
        let kindTitle = switch item.kind {
        case .gallery: "图集"
        case .recommended: "推荐"
        case .advertisement: "广告"
        }
        return InspectorSnapshot(
            symbolName: "photo.on.rectangle",
            title: item.title,
            moduleTitle: moduleTitle,
            summary: item.subtitle.nilIfEmpty,
            sections: compactSections([
                section("概览", rows: [
                    row("类型", kindTitle),
                    row("栏目", item.section.title),
                    row("图片数", item.imageCount.formatted()),
                    row("页数", item.pageCount.formatted()),
                    row("收藏", appContext.galleryStore.isFavorite(item) ? "已收藏" : "未收藏"),
                ]),
                section("来源", rows: [
                    row("原网页", item.detailURL.absoluteString, allowsWrapping: false, action: .open(item.detailURL)),
                ]),
            ])
        )
    }

    private func snapshot(for item: MissKonItem, moduleTitle: String) -> InspectorSnapshot {
        let mediaFireURL = appContext.missKonStore.currentItem?.id == item.id
            ? (appContext.missKonStore.detail.mediaFireDownloadURL
                ?? MissKonDetailMetadataCache.shared.metadata(for: item.detailURL)?.mediaFireURL)
            : MissKonDetailMetadataCache.shared.metadata(for: item.detailURL)?.mediaFireURL
        return InspectorSnapshot(
            symbolName: "person.crop.square",
            title: item.title,
            moduleTitle: moduleTitle,
            summary: item.tags.isEmpty ? nil : item.tags.prefix(8).joined(separator: " · "),
            sections: compactSections([
                section("概览", rows: [
                    row("栏目", item.section.title),
                    row("图片数", item.imageCount > 0 ? item.imageCount.formatted() : "未知"),
                    row("页数", item.pageCount.formatted()),
                    row("标签", item.tags.isEmpty ? nil : item.tags.joined(separator: ", ")),
                    row("收藏", appContext.missKonStore.isFavorite(item) ? "已收藏" : "未收藏"),
                ]),
                section("资源", rows: [
                    row("原网页", item.detailURL.absoluteString, allowsWrapping: false, action: .open(item.detailURL)),
                    mediaFireURL.flatMap {
                        row("MediaFire", $0.absoluteString, allowsWrapping: false, action: .open($0))
                    },
                ]),
            ])
        )
    }

    private func snapshot(for wallpaper: Wallpaper, moduleTitle: String) -> InspectorSnapshot {
        let format = wallpaper.fileType?
            .replacingOccurrences(of: "image/", with: "")
            .uppercased()
        let category = wallpaper.category.flatMap { WallhavenCategory(rawValue: $0)?.title ?? $0 }
        return InspectorSnapshot(
            symbolName: "photo.stack",
            title: "Wallhaven \(wallpaper.id)",
            moduleTitle: moduleTitle,
            summary: wallpaper.tags.isEmpty ? wallpaper.displayName.nilIfEmpty : wallpaper.tags.prefix(8).joined(separator: " · "),
            sections: compactSections([
                section("图像", rows: [
                    row("分辨率", wallpaper.resolutionText.nilIfPlaceholder),
                    row("大小", wallpaper.fileSize.map {
                        ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                    }),
                    row("格式", format),
                    row("分类", category),
                    row("内容分级", wallpaper.purity.title),
                ]),
                section("发布信息", rows: [
                    row("上传者", wallpaper.uploader),
                    row("上传日期", wallpaper.createdAt?.formatted(date: .abbreviated, time: .shortened)),
                    row("浏览数", wallpaper.views?.formatted()),
                    row("站内收藏", wallpaper.favorites?.formatted()),
                    row("标签", wallpaper.tags.isEmpty ? nil : wallpaper.tags.joined(separator: ", ")),
                    row("应用收藏", appContext.wallhavenStore.isFavorite(wallpaper) ? "已收藏" : "未收藏"),
                ]),
                section("来源", rows: [
                    wallpaper.uploaderProfileURL.flatMap {
                        row("作者主页", $0.absoluteString, allowsWrapping: false, action: .open($0))
                    },
                    row("原网页", wallpaper.sourcePageUrl.absoluteString, allowsWrapping: false, action: .open(wallpaper.sourcePageUrl)),
                ]),
            ])
        )
    }

    private func snapshot(for item: KnitGalleryItem, moduleTitle: String) -> InspectorSnapshot {
        let metadata = appContext.knitStore.detailMetadata
        let videoStatus: String? = if appContext.knitStore.videoURL != nil {
            "可播放"
        } else if item.hasVideo {
            "页面标记含视频"
        } else {
            nil
        }
        return InspectorSnapshot(
            symbolName: "photo.on.rectangle.angled",
            title: item.title,
            moduleTitle: moduleTitle,
            summary: [item.category, item.metadataText].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty,
            sections: compactSections([
                section("概览", rows: [
                    row("分类", item.category.nilIfEmpty),
                    row("图片", item.reportedPhotoCount > 0 ? item.reportedPhotoCount.formatted() : nil),
                    row("GIF", item.reportedGIFCount > 0 ? item.reportedGIFCount.formatted() : nil),
                    row("视频", item.reportedVideoCount > 0 ? item.reportedVideoCount.formatted() : nil),
                    row("浏览数", item.viewCount?.formatted()),
                    row("发布日期", item.publishedDate.nilIfEmpty),
                    row("收藏", appContext.knitStore.isFavorite(item) ? "已收藏" : "未收藏"),
                ]),
                section("已解析详情", rows: [
                    row("实际图片", metadata?.totalImages.formatted()),
                    row("图集页数", metadata?.totalPages.formatted()),
                    row("视频状态", videoStatus),
                    row("标签", metadata?.tags.isEmpty == false ? metadata?.tags.joined(separator: ", ") : nil),
                    row("描述", metadata?.description.nilIfEmpty),
                ]),
                section("来源", rows: [
                    row("原网页", item.detailURL.absoluteString, allowsWrapping: false, action: .open(item.detailURL)),
                ]),
            ])
        )
    }

    private func snapshot(for item: MrdsGalleryItem, moduleTitle: String) -> InspectorSnapshot {
        let metadata = appContext.mrdsStore.detailMetadata
        let videoStatus: String? = if appContext.mrdsStore.videoURL != nil {
            "可播放"
        } else {
            nil
        }
        return InspectorSnapshot(
            symbolName: "flag.checkered",
            title: item.title,
            moduleTitle: moduleTitle,
            summary: [item.category, item.metadataText].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty,
            sections: compactSections([
                section("概览", rows: [
                    row("分类", item.category.nilIfEmpty),
                    row("发布日期", item.publishedDate.nilIfEmpty),
                    row("收藏", appContext.mrdsStore.isFavorite(item) ? "已收藏" : "未收藏"),
                ]),
                section("已解析详情", rows: [
                    row("实际图片", metadata?.totalImages.formatted()),
                    row("视频状态", videoStatus),
                    row("标签", metadata?.tags.isEmpty == false ? metadata?.tags.joined(separator: ", ") : nil),
                    row("描述", metadata?.description.nilIfEmpty),
                ]),
                section("来源", rows: [
                    row("原网页", item.detailURL.absoluteString, allowsWrapping: false, action: .open(item.detailURL)),
                ]),
            ])
        )
    }

    private func snapshot(
        for item: OnlineVideoItem,
        moduleTitle: String,
        store: OnlineVideoGalleryStore
    ) -> InspectorSnapshot {
        let videoStatus: String? = if item.isDirectoryEntry {
            nil
        } else if store.videoURL != nil {
            "可播放"
        } else if store.isResolvingDetail {
            "解析中"
        } else if let message = store.detailErrorMessage {
            message
        } else {
            nil
        }
        let symbolName = switch store.policySource {
        case .quanji: "play.rectangle"
        case .tangxin: "play.rectangle.on.rectangle"
        default: "play.tv"
        }
        let tagText = item.tagFilters.map(\.title).filter { !$0.isEmpty }.joined(separator: "、").nilIfEmpty
        return InspectorSnapshot(
            symbolName: symbolName,
            title: item.title,
            moduleTitle: moduleTitle,
            summary: [item.durationText, item.subtitle].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty,
            sections: compactSections([
                section("概览", rows: [
                    row("作者", item.authorName?.nilIfEmpty),
                    row("分类", tagText),
                    row("时长", item.isDirectoryEntry ? nil : item.durationText.nilIfEmpty),
                    row("收藏", item.isDirectoryEntry ? nil : (store.isFavorite(item) ? "已收藏" : "未收藏")),
                    row("视频状态", videoStatus),
                ]),
                section("来源", rows: [
                    row("原网页", item.detailURL.absoluteString, allowsWrapping: false, action: .open(item.detailURL)),
                ]),
            ])
        )
    }

    private func snapshot(for record: FavoriteRecord) -> InspectorSnapshot {
        let source = FavoriteSource.source(for: record)
        let detailStore = appContext.favoritesDetailStore
        let isCurrentDetail = detailStore.currentRecord?.detailURL == record.detailURL
        let adapter = source.flatMap { FavoriteSourceAdapterRegistry.shared.adapter(for: $0) }
        let detailURL = source.flatMap { _ in URL(string: record.detailURL) }
        let resolvedMetadata = isCurrentDetail ? detailStore.detailMetadata : nil
        let metadata = resolvedMetadata ?? adapter?.detailMetadata(record)
        let cachedExternalAction = detailURL.flatMap { adapter?.cachedExternalAction($0) }
        let externalAction = isCurrentDetail ? (detailStore.externalAction ?? cachedExternalAction) : cachedExternalAction
        let videoURL = isCurrentDetail ? detailStore.videoURL : nil
        let sourceFactRows = metadata?.facts.map {
            row($0.label, $0.value)
        } ?? []

        return InspectorSnapshot(
            symbolName: source?.systemImage ?? "heart",
            title: metadata?.title.nilIfEmpty ?? record.title,
            moduleTitle: "我的收藏 · \(source?.title ?? "未知来源")",
            summary: metadata?.detailText.nilIfEmpty ?? record.subtitle.nilIfEmpty,
            sections: compactSections([
                section("收藏记录", rows: [
                    row("来源", source?.title),
                    row("图片数", record.imageCount > 0 ? record.imageCount.formatted() : "未知"),
                    row("页数", record.pageCount.formatted()),
                    row("来源标识", record.sourceID.nilIfEmpty),
                    row("作者或专题", metadata?.secondaryTitle),
                ]),
                section("来源详情", rows: sourceFactRows),
                section("可用资源", rows: [
                    row("视频", videoURL == nil ? nil : "可播放并下载"),
                    externalAction.flatMap {
                        row($0.title, $0.url.absoluteString, allowsWrapping: false, action: .open($0.url))
                    },
                ]),
                section("来源", rows: [
                    metadata?.secondaryURL.flatMap {
                        row("相关页面", $0.absoluteString, allowsWrapping: false, action: .open($0))
                    },
                    detailURL.flatMap {
                        row("原网页", $0.absoluteString, allowsWrapping: false, action: .open($0))
                    },
                ]),
            ])
        )
    }

    private func row(
        _ label: String,
        _ value: String?,
        valueColor: NSColor = .labelColor,
        allowsWrapping: Bool = true,
        action: InspectorRow.Action? = nil
    ) -> InspectorRow? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return InspectorRow(
            label: label,
            value: value,
            valueColor: valueColor,
            allowsWrapping: allowsWrapping,
            action: action
        )
    }

    private func section(_ title: String, rows: [InspectorRow?]) -> InspectorSection? {
        let rows = rows.compactMap { $0 }
        guard !rows.isEmpty else { return nil }
        return InspectorSection(title: title, rows: rows)
    }

    private func compactSections(_ sections: [InspectorSection?]) -> [InspectorSection] {
        sections.compactMap { $0 }
    }

    private func observeState(generation: UUID) {
        guard isActive, observationGeneration == generation else { return }
        withObservationTracking {
            let route = appContext.routeController.route
            switch route.moduleID {
            case .fourKHDGallery:
                _ = appContext.galleryStore.selectedItemID
                _ = appContext.galleryStore.selectedItem
                _ = appContext.galleryStore.favorites.favorites
            case .missKon:
                _ = appContext.missKonStore.selectedItemID
                _ = appContext.missKonStore.currentItem
                _ = appContext.missKonStore.detail.mediaFireDownloadURL
                _ = appContext.missKonStore.favorites.favorites
            case .wallhaven:
                _ = appContext.wallhavenStore.selectedWallpaperID
                _ = appContext.wallhavenStore.effectiveSelectedWallpaper
                _ = appContext.wallhavenStore.favorites.favorites
            case .favorites:
                _ = appContext.favoritesModuleStore.selectedRecordID
                _ = appContext.favoritesModuleStore.selectedRecord
                _ = appContext.favoritesDetailStore.currentRecord
                _ = appContext.favoritesDetailStore.detailMetadata
                _ = appContext.favoritesDetailStore.videoURL
                _ = appContext.favoritesDetailStore.externalAction
            case .knitGallery:
                _ = appContext.knitStore.selectedItemID
                _ = appContext.knitStore.selectedItem
                _ = appContext.knitStore.videoURL
                _ = appContext.knitStore.detailMetadata
                _ = appContext.favoritesStore.favorites
            case .mrdsGallery:
                _ = appContext.mrdsStore.selectedItemID
                _ = appContext.mrdsStore.selectedItem
                _ = appContext.mrdsStore.videoURL
                _ = appContext.mrdsStore.detailMetadata
                _ = appContext.favoritesStore.favorites
            case .quanjiGallery:
                _ = appContext.quanjiStore.selectedItemID
                _ = appContext.quanjiStore.selectedItem
                _ = appContext.quanjiStore.videoURL
                _ = appContext.quanjiStore.isResolvingDetail
                _ = appContext.favoritesStore.favorites
            case .pornyGallery:
                _ = appContext.pornyStore.selectedItemID
                _ = appContext.pornyStore.selectedItem
                _ = appContext.pornyStore.videoURL
                _ = appContext.pornyStore.isResolvingDetail
                _ = appContext.favoritesStore.favorites
            case .tangxinGallery:
                _ = appContext.tangxinStore.selectedItemID
                _ = appContext.tangxinStore.selectedItem
                _ = appContext.tangxinStore.videoURL
                _ = appContext.tangxinStore.isResolvingDetail
                _ = appContext.favoritesStore.favorites
            case .localLibrary:
                _ = appContext.localLibraryStore.roots
                _ = appContext.localLibraryStore.selectedFolderID
                _ = appContext.localLibraryStore.selectedImageIndex
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive,
                      self.observationGeneration == generation else { return }
                self.refresh()
                self.observeState(generation: generation)
            }
        }
    }
}

@MainActor
private extension InspectorRow.Action {
    var symbolName: String {
        switch self {
        case .open: "arrow.up.forward.square"
        case .reveal: "folder"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .open: "打开链接"
        case .reveal: "在 Finder 中显示"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var nilIfPlaceholder: String? {
        isEmpty || self == "-" ? nil : self
    }
}
