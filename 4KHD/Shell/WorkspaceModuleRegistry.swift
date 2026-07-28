import AppKit

@MainActor
struct WorkspaceModuleControllerContext {
    let appContext: WorkspaceAppContext
    let immersive: ImmersiveController
    let detailPaneController: WorkspaceDetailPaneController
    let sidebarDisclosure: SidebarDisclosureState
}

struct WorkspaceModuleDescriptor {
    let id: WorkspaceModuleID
    let displayName: String
    let defaultRoute: @MainActor () -> WorkspaceRoute
    let makeContentController: @MainActor (_ context: WorkspaceModuleControllerContext) -> NSViewController
    let makeDetailController: @MainActor (_ context: WorkspaceModuleControllerContext) -> NSViewController
    let normalizeRoute: @MainActor (_ route: WorkspaceRoute) -> WorkspaceRoute
    let applyRoute: @MainActor (_ route: WorkspaceRoute) -> Void
    let bootstrap: @MainActor () -> Void
}

@MainActor
final class WorkspaceModuleRegistry {
    let modules: [WorkspaceModuleDescriptor]
    private var bootstrappedModuleIDs = Set<WorkspaceModuleID>()

    init(modules: [WorkspaceModuleDescriptor]) {
        self.modules = modules
    }

    private var modulesByID: [WorkspaceModuleID: WorkspaceModuleDescriptor] {
        Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
    }

    func descriptor(for moduleID: WorkspaceModuleID) -> WorkspaceModuleDescriptor? {
        modulesByID[moduleID]
    }

    func descriptor(for route: WorkspaceRoute) -> WorkspaceModuleDescriptor? {
        descriptor(for: route.moduleID)
    }

    func defaultRoute() -> WorkspaceRoute {
        for module in modules {
            let route = module.defaultRoute()
            if let normalized = normalizedRouteIfAvailable(route) {
                return normalized
            }
        }
        return WorkspaceRoute(moduleID: modules.first?.id ?? .fourKHDGallery, itemID: "")
    }

    func normalizedRoute(_ route: WorkspaceRoute) -> WorkspaceRoute {
        guard let normalized = normalizedRouteIfAvailable(route) else {
            return defaultRoute()
        }
        return normalized
    }

    func contentController(
        for route: WorkspaceRoute,
        context: WorkspaceModuleControllerContext
    ) -> NSViewController {
        descriptor(for: route)?.makeContentController(context)
            ?? WorkspaceUnavailableController(message: "模块不可用")
    }

    func detailController(
        for route: WorkspaceRoute,
        context: WorkspaceModuleControllerContext
    ) -> NSViewController {
        descriptor(for: route)?.makeDetailController(context)
            ?? WorkspaceUnavailableController(message: "模块不可用")
    }

    func apply(_ route: WorkspaceRoute) {
        descriptor(for: route)?.applyRoute(route)
    }

    func bootstrapModule(_ moduleID: WorkspaceModuleID) {
        guard bootstrappedModuleIDs.insert(moduleID).inserted else { return }
        descriptor(for: moduleID)?.bootstrap()
    }

    private func normalizedRouteIfAvailable(_ route: WorkspaceRoute) -> WorkspaceRoute? {
        guard let descriptor = descriptor(for: route) else { return nil }
        return descriptor.normalizeRoute(route)
    }
}

@MainActor
private final class WorkspaceUnavailableController: NSViewController {
    private let message: String

    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.textColor = .secondaryLabelColor

        let container = NSView()
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        view = container
    }
}
