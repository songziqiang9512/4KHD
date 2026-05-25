import AppKit

@MainActor
final class WorkspaceColumnHostController: NSViewController {
    private let respectsSafeAreaTop: Bool
    private let backgroundMaterial: NSVisualEffectView.Material?
    private var contentController: NSViewController?

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

        // Determine the container that will host the content view.
        // When a background material is configured, insert a vibrancy wrapper
        // so that text and controls in the content composite correctly over the
        // translucent material.  Without the vibrancy layer labels and controls
        // may appear washed out or have reduced legibility.
        let container: NSView
        if let backgroundMaterial {
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
            container = vibrancyView
        } else {
            container = view
        }

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
