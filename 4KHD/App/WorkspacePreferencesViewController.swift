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
        checkboxWithTitle: "显示 4KHD、MissKon、爱妹子和每日大赛模块",
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

        // 每行从左到右:标签居左,控件居右(右对齐),行宽铺满。
        // 每个职责分组之间用分隔线隔开,分组标题居中。
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        addRow(separator, to: stack)
        addRow(sectionHeader("显示"), to: stack)
        addRow(formRow(label: "布局", control: layoutPopup), to: stack)
        addRow(separator, to: stack)
        addRow(sectionHeader("本地图库"), to: stack)
        addRow(formRow(label: "排序", control: localSortFieldPopup), to: stack)
        addRow(formRow(label: "方向", control: localSortDirectionPopup), to: stack)
        addRow(separator, to: stack)
        addRow(sectionHeader("侧边栏"), to: stack)
        addRow(showAdvancedModulesCheckbox, to: stack)
        addRow(separator, to: stack)
        addRow(sectionHeader("缓存"), to: stack)
        addRow(formRow(label: "缓存上限", control: cacheLimitPopup), to: stack)
        addRow(descriptionLabel("包含图片缓存、详情页缓存、模块缓存及临时文件"), to: stack)
        addRow(buttonRow([clearCacheButton, cacheStatusLabel], spacing: 12), to: stack)
        addRow(separator, to: stack)
        addRow(sectionHeader("收藏"), to: stack)
        addRow(buttonRow([exportFavoritesButton, importFavoritesButton, favoritesStatusLabel], spacing: 10), to: stack)
        addRow(descriptionLabel("将所有线上模块的收藏图集导出为 JSON 文件，之后可从文件恢复。"), to: stack)
        addRow(buttonRow([clearFavoritesButton], spacing: 10), to: stack)
        addRow(descriptionLabel("清空会立即从所有线上模块移除收藏；建议先导出备份。"), to: stack)

        documentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -20),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            // 内容不足一屏时撑满可视高度,让内容从顶部开始排(否则内容贴底,顶部出现空白)。
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
        ])

        refresh()
    }

    /// 行宽铺满整个设置面板。
    private func addRow(_ row: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
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
        label.alignment = .center
        return label
    }

    private func descriptionLabel(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func formRow(label text: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)

        // spacer 撑满中间,把控件推到最右。
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
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
        toolbarContext.setLayout(isList: layout == .list, for: .knitGallery)
        toolbarContext.setLayout(isList: layout == .list, for: .mrdsGallery)
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
