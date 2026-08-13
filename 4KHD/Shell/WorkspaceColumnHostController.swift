import AppKit

@MainActor
final class WorkspaceColumnHostController: NSViewController {
    private let respectsSafeAreaTop: Bool
    private let backgroundMaterial: NSVisualEffectView.Material?
    private var contentController: NSViewController?
    private var vibrancyWrapperView: NSVisualEffectView?

    init(
        respectsSafeAreaTop: Bool = false,
        backgroundMaterial: NSVisualEffectView.Material? = nil
    ) {
        self.respectsSafeAreaTop = respectsSafeAreaTop
        self.backgroundMaterial = backgroundMaterial
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        guard let backgroundMaterial else {
            view = NSView()
            return
        }
        let materialView = NSVisualEffectView()
        materialView.material = backgroundMaterial
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        view = materialView

        // Vibrancy wrapper 一次性创建并复用：内容控制器每次切换时只替换其子视图，
        // 避免重复 addSubview 导致包装视图在宿主内无限累积。
        let vibrancyView = NSVisualEffectView()
        vibrancyView.material = backgroundMaterial
        vibrancyView.blendingMode = .withinWindow
        vibrancyView.state = .active
        vibrancyView.isEmphasized = true
        vibrancyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vibrancyView)
        NSLayoutConstraint.activate([
            vibrancyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vibrancyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vibrancyView.topAnchor.constraint(
                equalTo: respectsSafeAreaTop
                    ? view.safeAreaLayoutGuide.topAnchor
                    : view.topAnchor
            ),
            vibrancyView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        vibrancyWrapperView = vibrancyView
    }

    func setContentController(_ controller: NSViewController) {
        if contentController === controller {
            return
        }

        if let contentController {
            contentController.view.removeFromSuperview()
            contentController.removeFromParent()
        }

        contentController = controller
        addChild(controller)

        // 背景材质存在时内容挂在 vibrancy 包装视图内，保证文字与控件在
        // 半透明材质上的可读性。
        let container: NSView = vibrancyWrapperView ?? view
        container.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

extension WorkspaceColumnHostController: WorkspaceFocusable {
    func focus() {
        if let focusable = contentController as? WorkspaceFocusable {
            focusable.focus()
            return
        }
        view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
    }
}
