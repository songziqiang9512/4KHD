import AppKit
import UniformTypeIdentifiers

/// 单页设置面板:显示/本地图库/侧边栏/缓存/收藏分组,统一两列网格排版,
/// 内容超出窗口高度时上下滚动。
@MainActor
final class WorkspacePreferencesViewController: NSViewController {
    private let toolbarContext: WorkspaceToolbarContext
    private let favoritesStore: FavoritesStore
    private let onFavoritesImported: () -> Void
    private let clearCaches: () async -> [String]

    private let layoutPopup = NSPopUpButton()
    private let localSortFieldPopup = NSPopUpButton()
    private let localSortDirectionPopup = NSPopUpButton()
    private let showAdvancedModulesCheckbox = NSButton(
        checkboxWithTitle: "显示 4KHD 和 MissKon 模块",
        target: nil,
        action: nil
    )
    private let cacheLimitPopup = NSPopUpButton()
    private let clearCacheButton = NSButton(title: "清除所有缓存", target: nil, action: nil)
    private let exportFavoritesButton = NSButton(title: "导出收藏...", target: nil, action: nil)
    private let importFavoritesButton = NSButton(title: "导入收藏...", target: nil, action: nil)
    private let clearFavoritesButton = NSButton(title: "清空全部收藏...", target: nil, action: nil)
    private let cacheStatusLabel = NSTextField(labelWithString: "")
    private let favoritesStatusLabel = NSTextField(labelWithString: "")
    private var clearTask: Task<Void, Never>?

    static let contentSize = NSSize(width: 480, height: 560)

    init(
        toolbarContext: WorkspaceToolbarContext,
        favoritesStore: FavoritesStore,
        clearCaches: @escaping () async -> [String],
        onFavoritesImported: @escaping () -> Void
    ) {
        self.toolbarContext = toolbarContext
        self.favoritesStore = favoritesStore
        self.clearCaches = clearCaches
        self.onFavoritesImported = onFavoritesImported
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let documentView = NSView()
        scrollView.documentView = documentView
        documentView.translatesAutoresizingMaskIntoConstraints = false
        view = scrollView

        configureControls()

        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        var rows: [[NSView]] = []
        rows.append([sectionHeader("显示")])
        rows.append(gridRow(label: "布局", control: layoutPopup))
        rows.append([sectionHeader("本地图库")])
        rows.append(gridRow(label: "排序", control: localSortFieldPopup))
        rows.append(gridRow(label: "方向", control: localSortDirectionPopup))
        rows.append([sectionHeader("侧边栏")])
        rows.append([showAdvancedModulesCheckbox])
        rows.append([separator])
        rows.append([sectionHeader("缓存")])
        rows.append(gridRow(label: "缓存上限", control: cacheLimitPopup))
        rows.append([descriptionLabel("包含图片缓存、详情页缓存、模块缓存及临时文件")])
        rows.append([buttonRow([clearCacheButton, cacheStatusLabel], spacing: 12)])
        rows.append([separator])
        rows.append([sectionHeader("收藏")])
        rows.append([buttonRow([exportFavoritesButton, importFavoritesButton, favoritesStatusLabel], spacing: 10)])
        rows.append([descriptionLabel("将所有线上模块的收藏图集导出为 JSON 文件，之后可从文件恢复。")])
        rows.append([buttonRow([clearFavoritesButton], spacing: 10)])
        rows.append([descriptionLabel("清空会立即从所有线上模块移除收藏；建议先导出备份。")])

        for row in rows {
            grid.addRow(with: row)
        }

        grid.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        showAdvancedModulesCheckbox.state = SidebarModuleVisibility.showAdvancedModules ? .on : .off
        // Read layout from any online module — they stay in sync.
        if case let .gallery(snapshot) = toolbarContext.snapshot(for: .fourKHDGallery) {
            layoutPopup.selectItem(representedObject: snapshot.layout)
        }
        if case let .local(snapshot) = toolbarContext.snapshot(for: .localLibrary) {
            localSortFieldPopup.selectItem(representedObject: snapshot.sortField)
            localSortDirectionPopup.selectItem(representedObject: snapshot.sortDirection)
        }
        cacheLimitPopup.selectItem(representedObject: OnlineCacheLimit.current)
        exportFavoritesButton.isEnabled = !favoritesStore.favorites.isEmpty
        clearFavoritesButton.isEnabled = !favoritesStore.favorites.isEmpty
    }

    // MARK: - 控件配置

    private func configureControls() {
        showAdvancedModulesCheckbox.target = self
        showAdvancedModulesCheckbox.action = #selector(toggleAdvancedModules(_:))

        configure(
            layoutPopup,
            items: [("列表", GalleryContentLayout.list), ("网格", GalleryContentLayout.grid)],
            action: #selector(layoutChanged(_:))
        )
        configure(
            localSortFieldPopup,
            items: LocalImageSortField.allCases.map { ($0.title, $0) },
            action: #selector(localSortFieldChanged(_:))
        )
        configure(
            localSortDirectionPopup,
            items: LocalImageSortDirection.allCases.map { ($0.title, $0) },
            action: #selector(localSortDirectionChanged(_:))
        )
        configure(
            cacheLimitPopup,
            items: OnlineCacheLimit.allCases.map { ($0.title, $0) },
            action: #selector(cacheLimitChanged(_:))
        )

        for button in [clearCacheButton, exportFavoritesButton, importFavoritesButton, clearFavoritesButton] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
        }
        clearCacheButton.target = self
        clearCacheButton.action = #selector(clearCache(_:))
        exportFavoritesButton.target = self
        exportFavoritesButton.action = #selector(exportFavorites(_:))
        importFavoritesButton.target = self
        importFavoritesButton.action = #selector(importFavorites(_:))
        clearFavoritesButton.target = self
        clearFavoritesButton.action = #selector(clearFavorites(_:))

        cacheStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        cacheStatusLabel.textColor = .secondaryLabelColor
        favoritesStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        favoritesStatusLabel.textColor = .secondaryLabelColor
    }

    private func configure<Value>(
        _ popup: NSPopUpButton,
        items: [(String, Value)],
        action: Selector
    ) {
        popup.removeAllItems()
        popup.target = self
        popup.action = action
        popup.controlSize = .regular
        popup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        for (title, value) in items {
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = value
        }
    }

    // MARK: - 布局辅助

    private func sectionHeader(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func descriptionLabel(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func gridRow(label text: String, control: NSView) -> [NSView] {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        return [label, control]
    }

    private func buttonRow(_ views: [NSView], spacing: CGFloat) -> NSView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = spacing
        return row
    }

    private var separator: NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    // MARK: - 动作

    @objc private func layoutChanged(_ sender: NSPopUpButton) {
        guard let layout = sender.selectedItem?.representedObject as? GalleryContentLayout else { return }
        let mkLayout: MissKonContentLayout = layout == .grid ? .grid : .list
        let whLayout: WallhavenContentLayout = layout == .grid ? .grid : .list
        let locLayout: LocalContentLayout = layout == .grid ? .grid : .list
        toolbarContext.setGalleryLayout(layout)
        toolbarContext.setMissKonLayout(mkLayout)
        toolbarContext.setWallhavenLayout(whLayout)
        toolbarContext.setLocalLayout(locLayout)
    }

    @objc private func localSortFieldChanged(_ sender: NSPopUpButton) {
        guard let field = sender.selectedItem?.representedObject as? LocalImageSortField,
              case let .local(snapshot) = toolbarContext.snapshot(for: .localLibrary) else { return }
        toolbarContext.setLocalSort(field: field, direction: snapshot.sortDirection)
    }

    @objc private func localSortDirectionChanged(_ sender: NSPopUpButton) {
        guard let direction = sender.selectedItem?.representedObject as? LocalImageSortDirection,
              case let .local(snapshot) = toolbarContext.snapshot(for: .localLibrary) else { return }
        toolbarContext.setLocalSort(field: snapshot.sortField, direction: direction)
    }

    @objc private func toggleAdvancedModules(_ sender: NSButton) {
        SidebarModuleVisibility.showAdvancedModules = (sender.state == .on)
    }

    @objc private func cacheLimitChanged(_ sender: NSPopUpButton) {
        guard let limit = sender.selectedItem?.representedObject as? OnlineCacheLimit else { return }
        OnlineCacheLimit.apply(limit)
    }

    @objc private func clearCache(_: NSButton) {
        guard clearTask == nil else { return }
        clearCacheButton.isEnabled = false
        cacheStatusLabel.stringValue = "清除中..."
        clearTask = Task { [weak self] in
            guard let self else { return }
            let failures = await clearCaches()
            if failures.isEmpty {
                cacheStatusLabel.stringValue = "已清除"
            } else {
                cacheStatusLabel.stringValue = "\(failures.count) 项清除失败"
            }
            clearCacheButton.isEnabled = true
            clearTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.cacheStatusLabel.stringValue = ""
            }
        }
    }

    @objc private func exportFavorites(_: NSButton) {
        let panel = NSSavePanel()
        panel.title = "导出收藏"
        panel.prompt = "导出"
        panel.nameFieldStringValue = defaultFavoritesBackupFileName()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFavoritesActionsEnabled(false)
        Task { [weak self] in
            guard let self else { return }
            defer { setFavoritesActionsEnabled(true) }
            do {
                try await favoritesStore.exportFavorites(to: url)
                favoritesStatusLabel.stringValue = "已导出 \(favoritesStore.favorites.count) 个收藏"
                clearFavoritesStatusLater()
            } catch {
                favoritesStatusLabel.stringValue = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    @objc private func importFavorites(_: NSButton) {
        let panel = NSOpenPanel()
        panel.title = "导入收藏"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFavoritesActionsEnabled(false)
        Task { [weak self] in
            guard let self else { return }
            defer { setFavoritesActionsEnabled(true) }
            do {
                let result = try await favoritesStore.importFavorites(from: url)
                onFavoritesImported()
                refresh()
                if result.skippedCount > 0 {
                    favoritesStatusLabel.stringValue = "已导入 \(result.importedCount) 个，跳过 \(result.skippedCount) 个"
                } else {
                    favoritesStatusLabel.stringValue = "已导入 \(result.importedCount) 个收藏"
                }
                clearFavoritesStatusLater()
            } catch {
                favoritesStatusLabel.stringValue = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    @objc private func clearFavorites(_: NSButton) {
        let count = favoritesStore.favorites.count
        guard count > 0 else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确定要清空全部收藏吗？"
        alert.informativeText = "将从所有线上模块移除 \(count) 个收藏。此操作无法撤销，建议先导出备份。"
        alert.addButton(withTitle: "清空收藏")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        setFavoritesActionsEnabled(false)
        clearFavoritesButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer { setFavoritesActionsEnabled(true) }
            do {
                try await favoritesStore.removeAllFavorites()
                refresh()
                favoritesStatusLabel.stringValue = "已清空 \(count) 个收藏"
                clearFavoritesStatusLater()
            } catch {
                favoritesStatusLabel.stringValue = "清空失败：\(error.localizedDescription)"
            }
        }
    }

    private func setFavoritesActionsEnabled(_ isEnabled: Bool) {
        importFavoritesButton.isEnabled = isEnabled
        exportFavoritesButton.isEnabled = isEnabled && !favoritesStore.favorites.isEmpty
        clearFavoritesButton.isEnabled = isEnabled && !favoritesStore.favorites.isEmpty
    }

    private static let backupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private func defaultFavoritesBackupFileName() -> String {
        "4KHD-Favorites-\(Self.backupDateFormatter.string(from: Date())).json"
    }

    private func clearFavoritesStatusLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.favoritesStatusLabel.stringValue = ""
        }
    }
}

extension NSPopUpButton {
    func selectItem<Value: Equatable>(representedObject value: Value) {
        guard let item = itemArray.first(where: { item in
            (item.representedObject as? Value) == value
        }) else { return }
        select(item)
    }
}
