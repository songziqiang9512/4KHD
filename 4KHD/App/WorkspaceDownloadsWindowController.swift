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
    private let emptyIconView = NSImageView()
    private let emptyLabel = NSTextField(labelWithString: "无下载任务")
    private let emptyHintLabel = NSTextField(labelWithString: "从工具栏「保存」菜单选择「保存整个图集…」开始")
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
        emptyIconView.isHidden = hasTasks
        emptyLabel.isHidden = hasTasks
        emptyHintLabel.isHidden = hasTasks
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
        tableView.rowHeight = 64
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
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

        emptyIconView.image = NSImage(
            systemSymbolName: "arrow.down.circle",
            accessibilityDescription: "无下载任务"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 44, weight: .light))
        emptyIconView.contentTintColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyHintLabel.font = .systemFont(ofSize: 11)
        emptyHintLabel.textColor = .tertiaryLabelColor
        emptyHintLabel.alignment = .center

        let emptyStack = NSStackView(views: [emptyIconView, emptyLabel, emptyHintLabel])
        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 8

        let stack = NSStackView(views: [buttonRow, scrollView])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(emptyStack)
        emptyStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            emptyStack.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
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
    private let percentageLabel = NSTextField(labelWithString: "")
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
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percentageLabel.textColor = .secondaryLabelColor
        percentageLabel.alignment = .right
        percentageLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        // 第一行:图标 + 标题 + 行尾按钮。
        let titleRow = NSStackView(views: [statusIconView, titleLabel, actionButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        // 第二行:副标题 + 进度条 + 百分比。
        let progressRow = NSStackView(views: [subtitleLabel, progressIndicator, percentageLabel])
        progressRow.orientation = .horizontal
        progressRow.alignment = .centerY
        progressRow.spacing = 8

        let stack = NSStackView(views: [titleRow, progressRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            statusIconView.widthAnchor.constraint(equalToConstant: 18),
            statusIconView.heightAnchor.constraint(equalToConstant: 18),
            progressIndicator.widthAnchor.constraint(equalToConstant: 150),
            actionButton.widthAnchor.constraint(equalToConstant: 52)
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
        statusIconView.image = statusImage(for: task.status)
        titleLabel.stringValue = task.title
        subtitleLabel.stringValue = subtitle
        toolTip = task.detailURL.absoluteString

        let total = task.totalCount
        if task.status == .running, total == 0 {
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
            percentageLabel.stringValue = "…"
        } else {
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.maxValue = max(Double(total), 1)
            progressIndicator.doubleValue = total > 0 ? Double(task.completedCount) : 0
            let percent = total > 0 ? Int((Double(task.completedCount) / Double(total) * 100).rounded()) : 0
            percentageLabel.stringValue = total > 0 ? "\(percent)%" : ""
        }

        actionButton.title = actionTitle
        actionButton.identifier = NSUserInterfaceItemIdentifier(actionID)
        actionButton.target = target
        actionButton.action = action
    }

    /// 状态图标带语义色:进行中蓝、完成绿、失败橙、等待/取消灰。
    private func statusImage(for status: DownloadStore.TaskStatus) -> NSImage? {
        let symbolName: String
        let color: NSColor
        switch status {
        case .queued:
            symbolName = "clock"
            color = .secondaryLabelColor
        case .running:
            symbolName = "arrow.down.circle.fill"
            color = .controlAccentColor
        case .completed:
            symbolName = "checkmark.circle.fill"
            color = .systemGreen
        case .failed:
            symbolName = "exclamationmark.triangle.fill"
            color = .systemOrange
        case .cancelled:
            symbolName = "xmark.circle.fill"
            color = .secondaryLabelColor
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
    }
}
