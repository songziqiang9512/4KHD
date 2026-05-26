import AppKit

@MainActor
final class WorkspaceContentPreferencesViewController: NSViewController, WorkspacePreferencesPane {
    private let toolbarContext: WorkspaceToolbarContext
    private let galleryLayoutPopup = NSPopUpButton()
    private let localLayoutPopup = NSPopUpButton()
    private let localSortFieldPopup = NSPopUpButton()
    private let localSortDirectionPopup = NSPopUpButton()
    private let showAdvancedModulesCheckbox: NSButton = {
        let checkbox = NSButton(checkboxWithTitle: "显示 4KHD 和 MissKon 模块", target: nil, action: nil)
        checkbox.font = .systemFont(ofSize: NSFont.systemFontSize)
        return checkbox
    }()

    let paneContentSize = NSSize(width: 430, height: 200)

    init(toolbarContext: WorkspaceToolbarContext) {
        self.toolbarContext = toolbarContext
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
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -24)
        ])

        configurePopups()
        stackView.addArrangedSubview(sectionLabel("Online Gallery"))
        stackView.addArrangedSubview(row(label: "Layout", control: galleryLayoutPopup))
        stackView.addArrangedSubview(sectionLabel("Local Library"))
        stackView.addArrangedSubview(row(label: "Layout", control: localLayoutPopup))
        stackView.addArrangedSubview(row(label: "Sort by", control: localSortFieldPopup))
        stackView.addArrangedSubview(row(label: "Direction", control: localSortDirectionPopup))
        stackView.addArrangedSubview(sectionLabel("Sidebar"))
        showAdvancedModulesCheckbox.target = self
        showAdvancedModulesCheckbox.action = #selector(toggleAdvancedModules(_:))
        stackView.addArrangedSubview(showAdvancedModulesCheckbox)

        view = rootView
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        showAdvancedModulesCheckbox.state = SidebarModuleVisibility.showAdvancedModules ? .on : .off
        if case .gallery(let snapshot) = toolbarContext.snapshot(for: .fourKHDGallery) {
            galleryLayoutPopup.selectItem(representedObject: snapshot.layout)
        }
        if case .local(let snapshot) = toolbarContext.snapshot(for: .localLibrary) {
            localLayoutPopup.selectItem(representedObject: snapshot.layout)
            localSortFieldPopup.selectItem(representedObject: snapshot.sortField)
            localSortDirectionPopup.selectItem(representedObject: snapshot.sortDirection)
        }
    }

    @objc private func galleryLayoutChanged(_ sender: NSPopUpButton) {
        guard let layout = sender.selectedItem?.representedObject as? GalleryContentLayout else { return }
        toolbarContext.setGalleryLayout(layout)
    }

    @objc private func localLayoutChanged(_ sender: NSPopUpButton) {
        guard let layout = sender.selectedItem?.representedObject as? LocalContentLayout else { return }
        toolbarContext.setLocalLayout(layout)
    }

    @objc private func localSortFieldChanged(_ sender: NSPopUpButton) {
        guard let field = sender.selectedItem?.representedObject as? LocalImageSortField,
              case .local(let snapshot) = toolbarContext.snapshot(for: .localLibrary) else { return }
        toolbarContext.setLocalSort(field: field, direction: snapshot.sortDirection)
    }

    @objc private func toggleAdvancedModules(_ sender: NSButton) {
        SidebarModuleVisibility.showAdvancedModules = (sender.state == .on)
    }

    @objc private func localSortDirectionChanged(_ sender: NSPopUpButton) {
        guard let direction = sender.selectedItem?.representedObject as? LocalImageSortDirection,
              case .local(let snapshot) = toolbarContext.snapshot(for: .localLibrary) else { return }
        toolbarContext.setLocalSort(field: snapshot.sortField, direction: direction)
    }

    private func configurePopups() {
        configure(
            galleryLayoutPopup,
            items: [
                ("List", GalleryContentLayout.list),
                ("Grid", GalleryContentLayout.grid)
            ],
            action: #selector(galleryLayoutChanged(_:))
        )
        configure(
            localLayoutPopup,
            items: [
                ("List", LocalContentLayout.list),
                ("Grid", LocalContentLayout.grid)
            ],
            action: #selector(localLayoutChanged(_:))
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
        popup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        for (title, value) in items {
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = value
        }
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
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

extension NSPopUpButton {
    func selectItem<Value: Equatable>(representedObject value: Value) {
        guard let item = itemArray.first(where: { item in
            (item.representedObject as? Value) == value
        }) else { return }
        select(item)
    }
}
