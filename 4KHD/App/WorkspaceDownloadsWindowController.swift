import AppKit
import Observation

/// Non-modal download manager. Closing the window hides it while queued work
/// continues in DownloadStore.
@MainActor
final class WorkspaceDownloadsWindowController: NSWindowController, NSWindowDelegate {
    private enum State {
        static let frameAutosaveName = "WorkspaceDownloadsWindow.v2"
    }

    private let downloadsViewController: DownloadsViewController

    init(downloadStore: DownloadStore) {
        downloadsViewController = DownloadsViewController(downloadStore: downloadStore)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "下载"
        window.contentViewController = downloadsViewController
        window.contentMinSize = NSSize(width: 520, height: 300)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.setFrameAutosaveName(State.frameAutosaveName)

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        downloadsViewController.reloadData()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

@MainActor
private final class DownloadsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum CellID {
        static let column = NSUserInterfaceItemIdentifier("DownloadTaskColumn")
        static let row = NSUserInterfaceItemIdentifier("DownloadTaskRow")
    }

    private let downloadStore: DownloadStore
    private let summaryLabel = NSTextField(labelWithString: "")
    private let tableView = WorkspaceTableView()
    private let scrollView = NSScrollView()
    private let emptyIconView = NSImageView()
    private let emptyLabel = NSTextField(labelWithString: "还没有下载任务")
    private let emptyHintLabel = NSTextField(labelWithString: "从图库工具栏的“保存”菜单添加图集或视频")
    private let cancelAllButton = NSButton(title: "取消全部", target: nil, action: nil)
    private let clearFinishedButton = NSButton(title: "清除已完成", target: nil, action: nil)
    private let refreshQueue = WorkspaceCoalescingQueue(
        name: "Downloads Refresh",
        interval: 0.12,
        maxInterval: 0.4
    )
    private var isObserving = false

    private var tasks: [DownloadStore.DownloadTask] {
        downloadStore.tasks
    }

    init(downloadStore: DownloadStore) {
        self.downloadStore = downloadStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSVisualEffectView()
        setupView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadData()
        observeStore()
    }

    func reloadData() {
        let hasTasks = !tasks.isEmpty
        scrollView.isHidden = !hasTasks
        emptyIconView.isHidden = hasTasks
        emptyLabel.isHidden = hasTasks
        emptyHintLabel.isHidden = hasTasks
        cancelAllButton.isEnabled = tasks.contains {
            $0.status == .queued || $0.status == .running || $0.status == .paused
        }
        clearFinishedButton.isEnabled = tasks.contains { $0.status == .completed }
        summaryLabel.stringValue = summaryText()
        tableView.reloadData()
    }

    private func setupView() {
        if let effectView = view as? NSVisualEffectView {
            effectView.material = .contentBackground
            effectView.blendingMode = .behindWindow
            effectView.state = .followsWindowActiveState
        }

        summaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        configureHeaderButton(cancelAllButton, symbolName: "xmark.circle")
        cancelAllButton.target = self
        cancelAllButton.action = #selector(cancelAll(_:))
        configureHeaderButton(clearFinishedButton, symbolName: "checkmark.circle")
        clearFinishedButton.target = self
        clearFinishedButton.action = #selector(clearFinished(_:))

        let actions = NSStackView(views: [cancelAllButton, clearFinishedButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: CellID.column)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 112
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true
        tableView.backgroundColor = .clear
        tableView.contextMenuProvider = { [weak self] row in
            self?.contextMenu(forRow: row)
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyIconView.image = NSImage(
            systemSymbolName: "arrow.down.to.line.compact",
            accessibilityDescription: "无下载任务"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 38, weight: .light))
        emptyIconView.contentTintColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyHintLabel.font = .systemFont(ofSize: 12)
        emptyHintLabel.textColor = .tertiaryLabelColor
        emptyHintLabel.alignment = .center

        let emptyStack = NSStackView(views: [emptyIconView, emptyLabel, emptyHintLabel])
        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 8
        emptyStack.translatesAutoresizingMaskIntoConstraints = false

        [summaryLabel, actions, separator, scrollView, emptyStack].forEach { view.addSubview($0) }
        NSLayoutConstraint.activate([
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            summaryLabel.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
            summaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -16),

            actions.topAnchor.constraint(equalTo: view.topAnchor, constant: 13),
            actions.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            separator.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            emptyStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -8),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func configureHeaderButton(_ button: NSButton, symbolName: String) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: button.title)
        button.imagePosition = .imageLeading
    }

    private func summaryText() -> String {
        guard !tasks.isEmpty else { return "暂无任务" }
        let running = tasks.filter { $0.status == .running }.count
        let queued = tasks.filter { $0.status == .queued }.count
        let paused = tasks.filter { $0.status == .paused }.count
        let completed = tasks.filter { $0.status == .completed }.count
        var parts = ["共 \(tasks.count) 个任务"]
        if running > 0 { parts.append("\(running) 个进行中") }
        if paused > 0 { parts.append("\(paused) 个已暂停") }
        if queued > 0 { parts.append("\(queued) 个等待") }
        if completed > 0 { parts.append("\(completed) 个已完成") }
        let other = tasks.count - running - queued - paused - completed
        if other > 0 { parts.append("\(other) 个已停止") }
        return parts.joined(separator: " · ")
    }

    func numberOfRows(in _: NSTableView) -> Int {
        tasks.count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard tasks.indices.contains(row) else { return nil }
        let cell = tableView.makeView(withIdentifier: CellID.row, owner: nil) as? DownloadTaskRowView
            ?? DownloadTaskRowView()
        cell.identifier = CellID.row
        let task = tasks[row]
        let primary: DownloadRowAction
        let secondary: DownloadRowAction?
        switch task.status {
        case .queued:
            primary = DownloadRowAction(
                symbolName: "xmark",
                toolTip: "取消下载",
                selector: #selector(cancelFromRow(_:))
            )
            secondary = nil
        case .running:
            if task.kind == .video {
                primary = DownloadRowAction(
                    symbolName: "pause.fill",
                    toolTip: "暂停下载",
                    selector: #selector(pauseFromRow(_:))
                )
                secondary = DownloadRowAction(
                    symbolName: "xmark",
                    toolTip: "取消下载",
                    selector: #selector(cancelFromRow(_:))
                )
            } else {
                primary = DownloadRowAction(
                    symbolName: "xmark",
                    toolTip: "取消下载",
                    selector: #selector(cancelFromRow(_:))
                )
                secondary = nil
            }
        case .paused:
            primary = DownloadRowAction(
                symbolName: "play.fill",
                toolTip: "继续下载",
                selector: #selector(retryFromRow(_:))
            )
            secondary = DownloadRowAction(
                symbolName: "xmark",
                toolTip: "取消下载",
                selector: #selector(cancelFromRow(_:))
            )
        case .failed, .cancelled:
            primary = DownloadRowAction(
                symbolName: "arrow.clockwise",
                toolTip: "重试",
                selector: #selector(retryFromRow(_:))
            )
            secondary = DownloadRowAction(
                symbolName: "xmark",
                toolTip: "从列表移除",
                selector: #selector(removeFromRow(_:))
            )
        case .completed:
            primary = DownloadRowAction(
                symbolName: "folder",
                toolTip: "在 Finder 中显示",
                selector: #selector(revealFromRow(_:))
            )
            secondary = nil
        }
        cell.configure(
            with: task,
            metadata: metadataText(for: task),
            statusText: statusText(for: task),
            actionID: task.id.uuidString,
            primary: primary,
            secondary: secondary,
            target: self
        )
        return cell
    }

    private func metadataText(for task: DownloadStore.DownloadTask) -> String {
        let kind = task.kind == .album ? "图集" : "视频"
        let destinationPath = (task.destinationURL.path as NSString).abbreviatingWithTildeInPath
        return "来源：\(task.sourceTitle) · \(kind)    目标：\(destinationPath)"
    }

    private func statusText(for task: DownloadStore.DownloadTask) -> String {
        switch task.status {
        case .queued:
            if let position = queuePosition(of: task.id) {
                return "排队中 · 第 \(position) 位"
            }
            return "排队中"
        case .running:
            return task.progressText.isEmpty ? "正在下载" : task.progressText
        case .paused:
            return task.progressText.isEmpty ? "已暂停" : "已暂停 · \(task.progressText)"
        case .completed:
            guard task.kind == .album else { return "MP4 已保存" }
            let failures = task.failedCount + task.failedPageCount
            return failures > 0
                ? "已保存 \(task.completedCount) 张 · \(failures) 项失败"
                : "已保存 \(task.completedCount) 张"
        case .failed:
            return task.errorMessage.isEmpty ? "下载失败" : "下载失败 · \(task.errorMessage)"
        case .cancelled:
            if task.kind == .album, task.completedCount > 0 {
                return "已取消 · 已保存 \(task.completedCount) 张"
            }
            return "已取消"
        }
    }

    private func queuePosition(of id: UUID) -> Int? {
        let queuedIDs = tasks.filter { $0.status == .queued }.map(\.id)
        guard let index = queuedIDs.firstIndex(of: id) else { return nil }
        return index + 1
    }

    @objc private func cancelAll(_: Any?) {
        downloadStore.cancelAll()
    }

    @objc private func clearFinished(_: Any?) {
        downloadStore.clearFinishedTasks()
    }

    @objc private func pauseFromRow(_ sender: NSButton) {
        guard let id = taskID(from: sender) else { return }
        downloadStore.pauseTask(id: id)
    }

    @objc private func cancelFromRow(_ sender: NSButton) {
        guard let id = taskID(from: sender) else { return }
        downloadStore.cancelTask(id: id)
    }

    @objc private func retryFromRow(_ sender: NSButton) {
        guard let id = taskID(from: sender) else { return }
        downloadStore.retryTask(id: id)
    }

    @objc private func removeFromRow(_ sender: NSButton) {
        guard let id = taskID(from: sender) else { return }
        downloadStore.removeTask(id: id)
    }

    @objc private func revealFromRow(_ sender: NSButton) {
        guard let id = taskID(from: sender),
              let task = downloadStore.tasks.first(where: { $0.id == id }) else { return }
        reveal(task)
    }

    private func taskID(from sender: NSButton) -> UUID? {
        guard let idString = sender.identifier?.rawValue else { return nil }
        return UUID(uuidString: idString)
    }

    @objc private func pauseFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        downloadStore.pauseTask(id: id)
    }

    @objc private func cancelFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        downloadStore.cancelTask(id: id)
    }

    @objc private func retryFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        downloadStore.retryTask(id: id)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let task = downloadStore.tasks.first(where: { $0.id == id }) else { return }
        reveal(task)
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        downloadStore.removeTask(id: id)
    }

    private func reveal(_ task: DownloadStore.DownloadTask) {
        let fileManager = FileManager.default
        let target = fileManager.fileExists(atPath: task.revealURL.path)
            ? task.revealURL
            : task.revealURL.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private func contextMenu(forRow row: Int) -> NSMenu? {
        guard tasks.indices.contains(row) else { return nil }
        let task = tasks[row]
        let menu = NSMenu()
        if task.status == .running, task.kind == .video {
            let pause = NSMenuItem(title: "暂停下载", action: #selector(pauseFromMenu(_:)), keyEquivalent: "")
            pause.target = self
            pause.representedObject = task.id
            pause.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "暂停下载")
            menu.addItem(pause)
        }
        if task.status == .queued || task.status == .running || task.status == .paused {
            let cancel = NSMenuItem(title: "取消下载", action: #selector(cancelFromMenu(_:)), keyEquivalent: "")
            cancel.target = self
            cancel.representedObject = task.id
            cancel.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "取消下载")
            menu.addItem(cancel)
        }
        if task.status == .failed || task.status == .cancelled || task.status == .paused {
            let retry = NSMenuItem(
                title: task.status == .paused ? "继续下载" : "重试",
                action: #selector(retryFromMenu(_:)),
                keyEquivalent: ""
            )
            retry.target = self
            retry.representedObject = task.id
            retry.image = NSImage(
                systemSymbolName: task.status == .paused ? "play.circle" : "arrow.clockwise",
                accessibilityDescription: task.status == .paused ? "继续下载" : "重试"
            )
            menu.addItem(retry)
        }
        let reveal = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealInFinder(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = task.id
        reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "在 Finder 中显示")
        menu.addItem(reveal)
        if task.status.isTerminal {
            menu.addItem(.separator())
            let remove = NSMenuItem(title: "从列表移除", action: #selector(removeFromMenu(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = task.id
            remove.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "从列表移除")
            menu.addItem(remove)
        }
        return menu
    }

    private func observeStore() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = downloadStore.tasks
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.scheduleReload()
                self.observeStore()
            }
        }
    }

    private func scheduleReload() {
        refreshQueue.add(id: "reload") { [weak self] in
            self?.reloadData()
        }
    }
}

private struct DownloadRowAction {
    var symbolName: String
    var toolTip: String
    var selector: Selector
}

@MainActor
private final class DownloadTaskRowView: NSTableCellView {
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private let statusIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let percentageLabel = NSTextField(labelWithString: "")
    private let speedLabel = NSTextField(labelWithString: "")
    private let primaryActionButton = NSButton(image: NSImage(), target: nil, action: nil)
    private let secondaryActionButton = NSButton(image: NSImage(), target: nil, action: nil)
    private let actionStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    private func buildView() {
        statusIconView.translatesAutoresizingMaskIntoConstraints = false
        statusIconView.imageScaling = .scaleProportionallyDown

        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        metadataLabel.font = .systemFont(ofSize: 11)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingMiddle

        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.isDisplayedWhenStopped = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        for item in [sizeLabel, percentageLabel, speedLabel] {
            item.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
            item.textColor = .secondaryLabelColor
            item.lineBreakMode = .byTruncatingTail
        }
        sizeLabel.alignment = .left
        percentageLabel.alignment = .center
        speedLabel.alignment = .right

        configureIconButton(primaryActionButton)
        configureIconButton(secondaryActionButton)
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 4
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.addArrangedSubview(primaryActionButton)
        actionStack.addArrangedSubview(secondaryActionButton)

        let titleRow = NSStackView(views: [titleLabel, statusLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.distribution = .fill
        titleRow.spacing = 12

        let metricsRow = NSStackView(views: [sizeLabel, percentageLabel, speedLabel])
        metricsRow.orientation = .horizontal
        metricsRow.alignment = .firstBaseline
        metricsRow.distribution = .fillEqually
        metricsRow.spacing = 8

        let content = NSStackView(views: [titleRow, metadataLabel, progressIndicator, metricsRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        [statusIconView, content, actionStack, separator].forEach { addSubview($0) }
        NSLayoutConstraint.activate([
            statusIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            statusIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusIconView.widthAnchor.constraint(equalToConstant: 28),
            statusIconView.heightAnchor.constraint(equalToConstant: 28),

            content.leadingAnchor.constraint(equalTo: statusIconView.trailingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: actionStack.leadingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),

            titleRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 170),
            metadataLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            progressIndicator.widthAnchor.constraint(equalTo: content.widthAnchor),
            metricsRow.widthAnchor.constraint(equalTo: content.widthAnchor),

            actionStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actionStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureIconButton(_ button: NSButton) {
        button.bezelStyle = .flexiblePush
        button.controlSize = .small
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    func configure(
        with task: DownloadStore.DownloadTask,
        metadata: String,
        statusText: String,
        actionID: String,
        primary: DownloadRowAction,
        secondary: DownloadRowAction?,
        target: AnyObject?
    ) {
        statusIconView.image = statusImage(for: task)
        titleLabel.stringValue = task.title
        metadataLabel.stringValue = metadata
        statusLabel.stringValue = statusText
        statusLabel.textColor = statusColor(for: task.status)
        statusLabel.toolTip = statusText
        metadataLabel.toolTip = task.destinationURL.path
        sizeLabel.stringValue = sizeText(for: task)
        percentageLabel.stringValue = percentageText(for: task)
        speedLabel.stringValue = speedText(for: task)
        speedLabel.textColor = speedColor(for: task.status)
        toolTip = task.destinationURL.path

        let fraction = displayFraction(for: task)
        if task.status == .running, fraction == nil {
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.doubleValue = fraction ?? 0
        }

        apply(primary, to: primaryActionButton, actionID: actionID, target: target)
        if let secondary {
            secondaryActionButton.isHidden = false
            apply(secondary, to: secondaryActionButton, actionID: actionID, target: target)
        } else {
            secondaryActionButton.isHidden = true
            secondaryActionButton.target = nil
            secondaryActionButton.action = nil
        }
    }

    private func apply(
        _ action: DownloadRowAction,
        to button: NSButton,
        actionID: String,
        target: AnyObject?
    ) {
        button.title = ""
        button.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.toolTip)
        button.imagePosition = .imageOnly
        button.toolTip = action.toolTip
        button.identifier = NSUserInterfaceItemIdentifier(actionID)
        button.target = target
        button.action = action.selector
    }

    private func sizeText(for task: DownloadStore.DownloadTask) -> String {
        let downloadedBytes = max(task.downloadedBytes, 0)
        let reportedTotal = task.totalBytes.flatMap { $0 > 0 ? $0 : nil }
        let completedTotal = task.status == .completed && downloadedBytes > 0
            ? downloadedBytes
            : nil
        let downloadedText = Self.byteCountFormatter.string(fromByteCount: downloadedBytes)
        guard let totalBytes = reportedTotal ?? completedTotal else {
            return "已下载 \(downloadedText) / 大小未知"
        }
        let totalText = Self.byteCountFormatter.string(fromByteCount: totalBytes)
        let estimateMarker = task.status == .completed ? "" : "约 "
        return "已下载 \(downloadedText) / \(estimateMarker)\(totalText)"
    }

    private func percentageText(for task: DownloadStore.DownloadTask) -> String {
        guard task.status != .queued,
              let fraction = displayFraction(for: task) else { return "—" }
        let percentage = Int((fraction * 100).rounded(.down))
        return "\(percentage)%"
    }

    private func speedText(for task: DownloadStore.DownloadTask) -> String {
        switch task.status {
        case .queued:
            return "等待中"
        case .running:
            guard let rate = formattedRate(task.bytesPerSecond) else { return "速度 —" }
            return "速度 \(rate)"
        case .paused:
            return "已暂停"
        case .completed:
            guard let rate = formattedRate(task.averageBytesPerSecond) else { return "已完成" }
            return "平均 \(rate)"
        case .failed:
            return "下载失败"
        case .cancelled:
            return "已取消"
        }
    }

    private func formattedRate(_ bytesPerSecond: Double) -> String? {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return nil }
        let byteCount = Int64(min(bytesPerSecond.rounded(), Double(Int64.max / 2)))
        return "\(Self.byteCountFormatter.string(fromByteCount: byteCount))/秒"
    }

    private func displayFraction(for task: DownloadStore.DownloadTask) -> Double? {
        switch task.status {
        case .queued:
            return 0
        case .completed:
            return 1
        case .running:
            let reportedFraction = clampedFraction(task.progressFraction)
            return reportedFraction > 0 ? reportedFraction : nil
        case .paused, .failed, .cancelled:
            return clampedFraction(task.progressFraction)
        }
    }

    private func clampedFraction(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    private func statusColor(for status: DownloadStore.TaskStatus) -> NSColor {
        switch status {
        case .queued:
            return .secondaryLabelColor
        case .running:
            return .controlAccentColor
        case .paused:
            return .systemOrange
        case .completed:
            return .systemGreen
        case .failed:
            return .systemRed
        case .cancelled:
            return .tertiaryLabelColor
        }
    }

    private func speedColor(for status: DownloadStore.TaskStatus) -> NSColor {
        switch status {
        case .completed:
            return .systemGreen
        case .failed:
            return .systemRed
        case .cancelled:
            return .tertiaryLabelColor
        case .queued, .running:
            return .secondaryLabelColor
        case .paused:
            return .systemOrange
        }
    }

    private func statusImage(for task: DownloadStore.DownloadTask) -> NSImage? {
        let symbolName = task.kind == .album ? "photo.stack" : "film"
        let color: NSColor
        switch task.status {
        case .queued:
            color = .secondaryLabelColor
        case .running:
            color = .controlAccentColor
        case .paused:
            color = .systemOrange
        case .completed:
            color = .systemGreen
        case .failed:
            color = .systemRed
        case .cancelled:
            color = .tertiaryLabelColor
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            )
    }
}
