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
    required init?(coder: NSCoder) {
        nil
    }

    override func accessibilityLabel() -> String? {
        "Workspace Sidebar"
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
           WorkspaceKeyboardHandler.keyDown(event, context: keyboardContextProvider()) {
            return
        }
        super.keyDown(with: event)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return super.draggingUpdated(sender)
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
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
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, image: NSImage?, count: Int?) {
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
    }

    func setDraggingPresentation(_ isDragging: Bool) {
        alphaValue = isDragging ? 0 : 1
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
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(spacer)
        stackView.addArrangedSubview(countLabel)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
