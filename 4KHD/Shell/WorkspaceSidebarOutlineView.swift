import AppKit

@MainActor
final class WorkspaceSidebarOutlineView: NSOutlineView, WorkspaceLiveResizeScrollerHiding {
    var keyboardContextProvider: (() -> WorkspaceKeyboardContext)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var draggingSessionEndedHandler: ((NSDragOperation) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        draggingDestinationFeedbackStyle = .none
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func accessibilityLabel() -> String? {
        "工作区侧边栏"
    }

    override func viewWillStartLiveResize() {
        workspaceWillStartLiveResize()
        super.viewWillStartLiveResize()
    }

    override func viewDidEndLiveResize() {
        workspaceDidEndLiveResize()
        super.viewDidEndLiveResize()
    }

    override func keyDown(with event: NSEvent) {
        if let keyboardContextProvider,
           WorkspaceKeyboardHandler.keyDown(event, context: keyboardContextProvider())
        {
            return
        }
        super.keyDown(with: event)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return super.draggingUpdated(sender)
    }

    override func draggingSession(
        _: NSDraggingSession,
        sourceOperationMaskFor _: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        super.draggingSession(session, endedAt: screenPoint, operation: operation)
        draggingSessionEndedHandler?(operation)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, delegate?.outlineView?(self, shouldSelectItem: item(atRow: row) as Any) != false {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return contextMenuProvider?(row)
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        if isGroupRow(row) {
            return .zero
        }
        return super.frameOfOutlineCell(atRow: row)
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        guard isGroupRow(row) else { return frame }
        let outlineFrame = super.frameOfOutlineCell(atRow: row)
        let targetX = outlineFrame.width > 0.5 ? outlineFrame.minX : frame.minX - indentationPerLevel
        let shift = frame.minX - targetX
        guard shift > 0.5 else { return frame }
        frame.origin.x -= shift
        frame.size.width += shift
        return frame
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else { return nil }
        if isGroupRow(row(at: point)) {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if isGroupRow(row), let node = item(atRow: row) as? WorkspaceSidebarNode {
            window?.makeFirstResponder(self)
            toggleGroup(node)
            return
        }
        super.mouseDown(with: event)
    }

    private func toggleGroup(_ node: WorkspaceSidebarNode) {
        if isItemExpanded(node) {
            if selectedRowIsInside(node) {
                deselectAll(nil)
            }
            collapseItem(node)
        } else {
            expandItem(node)
        }
    }

    private func selectedRowIsInside(_ group: WorkspaceSidebarNode) -> Bool {
        guard selectedRow >= 0 else { return false }
        var current: Any? = item(atRow: selectedRow)
        while let item = current {
            if let node = item as? WorkspaceSidebarNode, node == group {
                return true
            }
            current = parent(forItem: item)
        }
        return false
    }

    private func isGroupRow(_ row: Int) -> Bool {
        guard row >= 0, let node = item(atRow: row) as? WorkspaceSidebarNode else { return false }
        if case .group = node {
            return true
        }
        return false
    }
}

final class WorkspaceSidebarRowView: NSTableRowView {
    var suppressSelectionDuringDrag = false

    override func drawSelection(in dirtyRect: NSRect) {
        guard !suppressSelectionDuringDrag else { return }
        super.drawSelection(in: dirtyRect)
    }
}

final class WorkspaceSidebarCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let spacer = NSView()
    private let disclosureView = NSImageView()
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(title: String, image: NSImage?, count: Int?, isGroupExpanded: Bool? = nil) {
        titleLabel.stringValue = title
        iconView.image = image
        iconView.isHidden = image == nil
        if let count {
            countLabel.stringValue = "\(count)"
            countLabel.isHidden = false
        } else {
            countLabel.stringValue = ""
            countLabel.isHidden = true
        }
        setGroupDisclosure(isExpanded: isGroupExpanded)
    }

    func setDraggingPresentation(_ isDragging: Bool) {
        alphaValue = isDragging ? 0 : 1
    }

    func setTitleStyle(font: NSFont, color: NSColor) {
        titleLabel.font = font
        titleLabel.textColor = color
        iconView.contentTintColor = color
    }

    func setGroupDisclosure(isExpanded: Bool?) {
        guard let isExpanded else {
            disclosureView.isHidden = true
            disclosureView.image = nil
            return
        }
        disclosureView.isHidden = false
        let symbolName = isExpanded ? "chevron.down" : "chevron.right"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isExpanded ? "已展开" : "已折叠")
        image?.isTemplate = true
        disclosureView.image = image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.refusesFirstResponder = true
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        disclosureView.imageScaling = .scaleProportionallyDown
        disclosureView.contentTintColor = .tertiaryLabelColor
        disclosureView.setContentHuggingPriority(.required, for: .horizontal)
        disclosureView.setContentCompressionResistancePriority(.required, for: .horizontal)
        disclosureView.isHidden = true

        spacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(spacer)
        stackView.addArrangedSubview(countLabel)
        stackView.addArrangedSubview(disclosureView)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            disclosureView.widthAnchor.constraint(equalToConstant: 12),
            disclosureView.heightAnchor.constraint(equalToConstant: 12),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
