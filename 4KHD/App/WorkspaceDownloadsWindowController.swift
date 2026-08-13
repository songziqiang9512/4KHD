import AppKit
import Observation

/// 下载管理器浮窗:仿 Inspector 的 utility 面板,关闭=隐藏,任务在后台继续。
@MainActor
final class WorkspaceDownloadsWindowController: NSWindowController, NSWindowDelegate {
    private enum State {
        static let frameAutosaveName = "WorkspaceDownloadsWindow"
    }

    private let downloadsViewController: DownloadsViewController

    init(downloadStore: DownloadStore) {
        downloadsViewController = DownloadsViewController(downloadStore: downloadStore)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "下载"
        panel.contentViewController = downloadsViewController
        panel.contentMinSize = NSSize(width: 440, height: 220)
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.setFrameAutosaveName(State.frameAutosaveName)

        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        downloadsViewController.reloadData()
    }

    /// 关闭按钮 = 隐藏;Window 菜单可重新打开。
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
    private let tableView = WorkspaceTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "无下载任务")
    private let cancelAllButton = NSButton(title: "取消全部", target: nil, action: nil)
    private let clearFinishedButton = NSButton(title: "清除已完成", target: nil, action: nil)
    private let refreshQueue = WorkspaceCoalescingQueue(
        name: "Downloads Refresh",
        interval: 0.15,
        maxInterval: 0.5
    )
    private var isObserving = false

    private var tasks: [DownloadStore.AlbumDownloadTask] {
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
        view = NSView()
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
        emptyLabel.isHidden = hasTasks
        cancelAllButton.isEnabled = tasks.contains { $0.status == .queued || $0.status == .running }
        clearFinishedButton.isEnabled = tasks.contains { $0.status.isTerminal }
        tableView.reloadData()
    }

    // MARK: - 布局

    private func setupView() {
        cancelAllButton.target = self
        cancelAllButton.action = #selector(cancelAll(_:))
        cancelAllButton.bezelStyle = .rounded
        clearFinishedButton.target = self
        clearFinishedButton.action = #selector(clearFinished(_:))
        clearFinishedButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [cancelAllButton, clearFinishedButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY

        let column = NSTableColumn(identifier: CellID.column)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true
        tableView.backgroundColor = .clear
        tableView.contextMenuProvider = { [weak self] row in
            self?.contextMenu(forRow: row)
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let stack = NSStackView(views: [buttonRow, scrollView])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    // MARK: - 表格数据源

    func numberOfRows(in _: NSTableView) -> Int {
        tasks.count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard tasks.indices.contains(row) else { return nil }
        let cell = tableView.makeView(withIdentifier: CellID.row, owner: nil) as? DownloadTaskRowView
            ?? DownloadTaskRowView()
        cell.identifier = CellID.row
        let task = tasks[row]
        let isActive = task.status == .queued || task.status == .running
        cell.configure(
            with: task,
            subtitle: subtitle(for: task),
            actionTitle: isActive ? "取消" : "移除",
            actionID: task.id.uuidString,
            target: self,
            action: #selector(rowAction(_:))
        )
        return cell
    }

    // MARK: - 行展示

    private func subtitle(for task: DownloadStore.AlbumDownloadTask) -> String {
        switch task.status {
        case .queued:
            if let position = queuePosition(of: task.id) {
                return "排队中·第 \(position) 位"
            }
            return "排队中"
        case .running:
            if task.totalCount > 0 {
                return "下载中 \(task.completedCount)/\(task.totalCount)"
            }
            return "下载中 \(task.completedCount) 张"
        case .completed:
            let failures = task.failedCount + task.failedPageCount
            if failures > 0 {
                return "已完成 \(task.completedCount) 张·失败 \(failures) 项"
            }
            return "已完成 \(task.completedCount) 张"
        case .failed:
            if !task.errorMessage.isEmpty {
                return task.errorMessage
            }
            return "下载失败"
        case .cancelled:
            return "已取消·已保存 \(task.completedCount) 张"
        }
    }

    private func queuePosition(of id: UUID) -> Int? {
        let queuedIDs = tasks.filter { $0.status == .queued }.map(\.id)
        guard let index = queuedIDs.firstIndex(of: id) else { return nil }
        return index + 1
    }

    // MARK: - 动作

    @objc private func cancelAll(_: Any?) {
        downloadStore.cancelAll()
    }

    @objc private func clearFinished(_: Any?) {
        downloadStore.clearFinishedTasks()
    }

    @objc private func rowAction(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue,
              let id = UUID(uuidString: idString),
              let task = downloadStore.tasks.first(where: { $0.id == id }) else { return }
        if task.status == .queued || task.status == .running {
            downloadStore.cancelTask(id: id)
        } else {
            downloadStore.removeTask(id: id)
        }
    }

    @objc private func cancelFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        downloadStore.cancelTask(id: id)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let task = downloadStore.tasks.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([task.destinationFolderURL])
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        downloadStore.removeTask(id: id)
    }

    private func contextMenu(forRow row: Int) -> NSMenu? {
        guard tasks.indices.contains(row) else { return nil }
        let task = tasks[row]
        let menu = NSMenu()
        if task.status == .queued || task.status == .running {
            let cancel = NSMenuItem(title: "取消", action: #selector(cancelFromMenu(_:)), keyEquivalent: "")
            cancel.target = self
            cancel.representedObject = task.id
            menu.addItem(cancel)
        }
        let reveal = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealInFinder(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = task.id
        reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "在 Finder 中显示")
        menu.addItem(reveal)
        if task.status.isTerminal {
            let remove = NSMenuItem(title: "从列表移除", action: #selector(removeFromMenu(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = task.id
            menu.addItem(remove)
        }
        return menu
    }

    // MARK: - 观察

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

@MainActor
private final class DownloadTaskRowView: NSTableCellView {
    private let statusIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    private func buildView() {
        statusIconView.translatesAutoresizingMaskIntoConstraints = false
        statusIconView.contentTintColor = .secondaryLabelColor

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [statusIconView, textStack, progressIndicator, actionButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            statusIconView.widthAnchor.constraint(equalToConstant: 16),
            statusIconView.heightAnchor.constraint(equalToConstant: 16),
            progressIndicator.widthAnchor.constraint(equalToConstant: 140),
            actionButton.widthAnchor.constraint(equalToConstant: 52),
        ])
    }

    func configure(
        with task: DownloadStore.AlbumDownloadTask,
        subtitle: String,
        actionTitle: String,
        actionID: String,
        target: AnyObject?,
        action: Selector
    ) {
        statusIconView.image = NSImage(
            systemSymbolName: statusSymbol(for: task.status),
            accessibilityDescription: nil
        )
        titleLabel.stringValue = task.title
        subtitleLabel.stringValue = subtitle
        toolTip = task.detailURL.absoluteString

        let total = task.totalCount
        if task.status == .running, total == 0 {
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.maxValue = max(Double(total), 1)
            progressIndicator.doubleValue = total > 0 ? Double(task.completedCount) : 0
        }

        actionButton.title = actionTitle
        actionButton.identifier = NSUserInterfaceItemIdentifier(actionID)
        actionButton.target = target
        actionButton.action = action
    }

    private func statusSymbol(for status: DownloadStore.TaskStatus) -> String {
        switch status {
        case .queued:
            "clock"
        case .running:
            "arrow.down.circle"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .cancelled:
            "xmark.circle"
        }
    }
}
