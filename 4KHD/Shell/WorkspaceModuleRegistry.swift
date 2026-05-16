import SwiftUI

struct WorkspaceModuleDescriptor {
    let id: WorkspaceModuleID
    let displayName: String
    let defaultRoute: @MainActor () -> WorkspaceRoute
    let makeSidebarSection: (_ selection: Binding<WorkspaceRoute?>, _ importRootFolder: @escaping () -> Void) -> AnyView
    let makeContentView: () -> AnyView
    let makeDetailView: () -> AnyView
    let normalizeRoute: @MainActor (_ route: WorkspaceRoute) -> WorkspaceRoute
    let applyRoute: @MainActor (_ route: WorkspaceRoute) -> Void
    let bootstrap: @MainActor () -> Void
}

@MainActor
struct WorkspaceModuleRegistry {
    let modules: [WorkspaceModuleDescriptor]

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

    func contentView(for route: WorkspaceRoute) -> AnyView {
        descriptor(for: route)?.makeContentView()
            ?? AnyView(ContentUnavailableView("模块不可用", systemImage: "square.stack"))
    }

    func sidebarSection(
        for moduleID: WorkspaceModuleID,
        selection: Binding<WorkspaceRoute?>,
        importRootFolder: @escaping () -> Void
    ) -> AnyView? {
        descriptor(for: moduleID)?.makeSidebarSection(selection, importRootFolder)
    }

    func detailView(for route: WorkspaceRoute) -> AnyView {
        descriptor(for: route)?.makeDetailView()
            ?? AnyView(ContentUnavailableView("模块不可用", systemImage: "photo"))
    }

    func apply(_ route: WorkspaceRoute) {
        descriptor(for: route)?.applyRoute(route)
    }

    func bootstrapModules() {
        for module in modules {
            module.bootstrap()
        }
    }

    private func normalizedRouteIfAvailable(_ route: WorkspaceRoute) -> WorkspaceRoute? {
        guard let descriptor = descriptor(for: route) else { return nil }
        return descriptor.normalizeRoute(route)
    }
}
