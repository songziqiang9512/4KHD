import AppKit

@MainActor
final class WorkspaceColumnHostController: NSViewController {
    private let respectsSafeAreaTop: Bool
    private var contentController: NSViewController?

    init(respectsSafeAreaTop: Bool = false) {
        self.respectsSafeAreaTop = respectsSafeAreaTop
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
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
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(
                equalTo: respectsSafeAreaTop ? view.safeAreaLayoutGuide.topAnchor : view.topAnchor
            ),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
