import AppKit

@MainActor
final class WorkspaceStoragePreferencesViewController: NSViewController, WorkspacePreferencesPane {
    private let cacheLimitPopup = NSPopUpButton()
    private let clearCacheButton: NSButton = {
        let b = NSButton(title: "清除所有缓存", target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        return b
    }()
    private let statusLabel = NSTextField(labelWithString: "")
    private var clearTask: Task<Void, Never>?

    let paneContentSize = NSSize(width: 430, height: 130)

    override func loadView() {
        let rootView = NSView(frame: NSRect(origin: .zero, size: paneContentSize))
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
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

        clearCacheButton.target = self
        clearCacheButton.action = #selector(clearCache(_:))
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor

        let buttonRow = NSStackView(views: [clearCacheButton, statusLabel])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12

        stackView.addArrangedSubview(row(label: "在线缓存容量", control: cacheLimitPopup))
        stackView.addArrangedSubview(buttonRow)
        view = rootView
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        cacheLimitPopup.selectItem(representedObject: OnlineCacheLimit.current)
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

            // MissKon feed cache
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let missKonDir = appSupport.appendingPathComponent("4KHD/MissKon", isDirectory: true)
                try? FileManager.default.removeItem(at: missKonDir)
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

    private func row(label text: String, control: NSControl) -> NSStackView {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }
}
