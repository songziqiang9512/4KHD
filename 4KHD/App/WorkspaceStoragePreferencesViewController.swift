import AppKit
import UniformTypeIdentifiers

@MainActor
final class WorkspaceStoragePreferencesViewController: NSViewController, WorkspacePreferencesPane {
    private let favoritesStore: FavoritesStore
    private let onFavoritesImported: () -> Void
    private let cacheLimitPopup = NSPopUpButton()
    private let clearCacheButton: NSButton = {
        let b = NSButton(title: "清除所有缓存", target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        return b
    }()
    private let exportFavoritesButton: NSButton = {
        let b = NSButton(title: "导出收藏...", target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        return b
    }()
    private let importFavoritesButton: NSButton = {
        let b = NSButton(title: "导入收藏...", target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        return b
    }()
    private let statusLabel = NSTextField(labelWithString: "")
    private let favoritesStatusLabel = NSTextField(labelWithString: "")
    private var clearTask: Task<Void, Never>?

    let paneContentSize = NSSize(width: 470, height: 235)

    init(
        favoritesStore: FavoritesStore,
        onFavoritesImported: @escaping () -> Void
    ) {
        self.favoritesStore = favoritesStore
        self.onFavoritesImported = onFavoritesImported
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(origin: .zero, size: paneContentSize))
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -24)
        ])

        cacheLimitPopup.removeAllItems()
        cacheLimitPopup.target = self
        cacheLimitPopup.action = #selector(cacheLimitChanged(_:))
        cacheLimitPopup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        for limit in OnlineCacheLimit.allCases {
            cacheLimitPopup.addItem(withTitle: limit.title)
            cacheLimitPopup.lastItem?.representedObject = limit
        }

        let descLabel = NSTextField(labelWithString: "包含图片缓存、详情页缓存、模块缓存及临时文件")
        descLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        descLabel.textColor = .secondaryLabelColor

        clearCacheButton.target = self
        clearCacheButton.action = #selector(clearCache(_:))
        clearCacheButton.title = "清除所有缓存"
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        favoritesStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        favoritesStatusLabel.textColor = .secondaryLabelColor

        let buttonRow = NSStackView(views: [clearCacheButton, statusLabel])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12

        exportFavoritesButton.target = self
        exportFavoritesButton.action = #selector(exportFavorites(_:))
        importFavoritesButton.target = self
        importFavoritesButton.action = #selector(importFavorites(_:))

        let favoritesDescLabel = NSTextField(labelWithString: "将所有线上模块的收藏图集导出为 JSON 文件，之后可从文件恢复。")
        favoritesDescLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        favoritesDescLabel.textColor = .secondaryLabelColor

        let favoritesButtonRow = NSStackView(views: [exportFavoritesButton, importFavoritesButton, favoritesStatusLabel])
        favoritesButtonRow.orientation = .horizontal
        favoritesButtonRow.alignment = .centerY
        favoritesButtonRow.spacing = 10

        stackView.addArrangedSubview(row(label: "缓存上限", control: cacheLimitPopup))
        stackView.addArrangedSubview(descLabel)
        stackView.addArrangedSubview(buttonRow)
        stackView.addArrangedSubview(separator())
        stackView.addArrangedSubview(row(label: "收藏备份", control: favoritesButtonRow))
        stackView.addArrangedSubview(favoritesDescLabel)
        view = rootView
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        cacheLimitPopup.selectItem(representedObject: OnlineCacheLimit.current)
        exportFavoritesButton.isEnabled = !favoritesStore.favorites.isEmpty
    }

    @objc private func cacheLimitChanged(_ sender: NSPopUpButton) {
        guard let limit = sender.selectedItem?.representedObject as? OnlineCacheLimit else { return }
        OnlineCacheLimit.apply(limit)
    }

    @objc private func clearCache(_ sender: NSButton) {
        guard clearTask == nil else { return }
        clearCacheButton.isEnabled = false
        statusLabel.stringValue = "清除中..."
        clearTask = Task.detached(priority: .utility) {
            // Nuke image/data caches + URL cache
            await RemoteImagePipeline.shared.clearAllCaches()

            // Detail page cache (Gallery)
            await DetailPageImageCache.shared.flush()
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let detailPageDir = appSupport.appendingPathComponent("4KHD/DetailPageCache", isDirectory: true)
                try? FileManager.default.removeItem(at: detailPageDir)

                // MissKon feed cache
                let missKonDir = appSupport.appendingPathComponent("4KHD/MissKon", isDirectory: true)
                try? FileManager.default.removeItem(at: missKonDir)

                // Wallhaven detail cache
                let wallhavenDir = appSupport.appendingPathComponent("4KHD/Wallhaven", isDirectory: true)
                try? FileManager.default.removeItem(at: wallhavenDir)

                // Local image thumbnail cache
                let localThumbDir = appSupport.appendingPathComponent("4KHD/LocalImageThumbnails", isDirectory: true)
                try? FileManager.default.removeItem(at: localThumbDir)
            }

            // Wallhaven temp downloads
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("4KHD-Wallpaper", isDirectory: true)
            try? FileManager.default.removeItem(at: tempDir)

            await MainActor.run { [weak self] in
                self?.statusLabel.stringValue = "已清除"
                self?.clearCacheButton.isEnabled = true
                self?.clearTask = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.statusLabel.stringValue = ""
                }
            }
        }
    }

    @objc private func exportFavorites(_ sender: NSButton) {
        let panel = NSSavePanel()
        panel.title = "导出收藏"
        panel.prompt = "导出"
        panel.nameFieldStringValue = defaultFavoritesBackupFileName()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try favoritesStore.exportFavorites(to: url)
            favoritesStatusLabel.stringValue = "已导出 \(favoritesStore.favorites.count) 个收藏"
            clearFavoritesStatusLater()
        } catch {
            favoritesStatusLabel.stringValue = "导出失败"
        }
    }

    @objc private func importFavorites(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.title = "导入收藏"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try favoritesStore.importFavorites(from: url)
            onFavoritesImported()
            refresh()
            if result.skippedCount > 0 {
                favoritesStatusLabel.stringValue = "已导入 \(result.importedCount) 个，跳过 \(result.skippedCount) 个"
            } else {
                favoritesStatusLabel.stringValue = "已导入 \(result.importedCount) 个收藏"
            }
            clearFavoritesStatusLater()
        } catch {
            favoritesStatusLabel.stringValue = "导入失败"
        }
    }

    private func row(label text: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func defaultFavoritesBackupFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "4KHD-Favorites-\(formatter.string(from: Date())).json"
    }

    private func clearFavoritesStatusLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.favoritesStatusLabel.stringValue = ""
        }
    }
}
