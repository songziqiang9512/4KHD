import AppKit

@MainActor
final class WorkspaceStoragePreferencesViewController: NSViewController, WorkspacePreferencesPane {
    private let cacheLimitPopup = NSPopUpButton()

    let paneContentSize = NSSize(width: 430, height: 112)

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

        stackView.addArrangedSubview(row(label: "Image cache", control: cacheLimitPopup))
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
