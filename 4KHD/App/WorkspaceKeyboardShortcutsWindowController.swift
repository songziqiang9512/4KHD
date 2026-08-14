import AppKit

@MainActor
final class WorkspaceKeyboardShortcutsWindowController: NSWindowController {
    init() {
        let viewController = WorkspaceKeyboardShortcutsViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = "键盘快捷键"
        window.styleMask = [.titled, .closable, .resizable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 520))
        window.contentMinSize = NSSize(width: 420, height: 360)
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class WorkspaceKeyboardShortcutsViewController: NSViewController {
    private struct ShortcutGroup {
        let title: String
        let shortcuts: [Shortcut]
    }

    private struct Shortcut {
        let title: String
        let keys: String
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(
            title: "应用",
            shortcuts: [
                Shortcut(title: "设置", keys: "⌘,"),
                Shortcut(title: "键盘快捷键", keys: "⌘?"),
                Shortcut(title: "关闭窗口", keys: "⌘W"),
                Shortcut(title: "退出", keys: "⌘Q")
            ]
        ),
        ShortcutGroup(
            title: "内容",
            shortcuts: [
                Shortcut(title: "导入目录", keys: "⌘O"),
                Shortcut(title: "查找", keys: "⌘F"),
                Shortcut(title: "刷新", keys: "⌘R"),
                Shortcut(title: "保存图片", keys: "⌘S"),
                Shortcut(title: "快速预览", keys: "⌘Y"),
                Shortcut(title: "拷贝", keys: "⌘C")
            ]
        ),
        ShortcutGroup(
            title: "显示",
            shortcuts: [
                Shortcut(title: "切换工具栏", keys: "⌘T"),
                Shortcut(title: "实际大小", keys: "⌘0"),
                Shortcut(title: "增加网格列数", keys: "⌘-"),
                Shortcut(title: "减少网格列数", keys: "⌘="),
                Shortcut(title: "切换详情区", keys: "⌘\\"),
                Shortcut(title: "聚焦侧边栏", keys: "⌘1"),
                Shortcut(title: "聚焦内容区", keys: "⌘2"),
                Shortcut(title: "聚焦详情区", keys: "⌘3")
            ]
        )
    ]

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let containerView = NSView()
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24),
            containerView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        for group in groups {
            stackView.addArrangedSubview(sectionView(for: group))
        }

        scrollView.documentView = containerView
        view = scrollView
    }

    private func sectionView(for group: ShortcutGroup) -> NSView {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: group.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(titleLabel)

        for shortcut in group.shortcuts {
            stackView.addArrangedSubview(rowView(for: shortcut))
        }
        return stackView
    }

    private func rowView(for shortcut: Shortcut) -> NSView {
        let titleLabel = NSTextField(labelWithString: shortcut.title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let keysLabel = NSTextField(labelWithString: shortcut.keys)
        keysLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        keysLabel.textColor = .secondaryLabelColor
        keysLabel.alignment = .right
        keysLabel.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [titleLabel, keysLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        keysLabel.setContentHuggingPriority(.required, for: .horizontal)
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        return row
    }
}
