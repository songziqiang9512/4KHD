import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceRouteController {
    private static let defaultsKey = "com.songziqiang.4khd.sidebarSelection"

    private let normalizeRoute: (WorkspaceRoute) -> WorkspaceRoute
    private let applyRoute: (WorkspaceRoute) -> Void
    @ObservationIgnored private var observers: [UUID: (WorkspaceRoute) -> Void] = [:]

    var route: WorkspaceRoute {
        didSet {
            UserDefaults.standard.set(route.rawValue, forKey: Self.defaultsKey)
        }
    }

    init(
        defaultRoute: WorkspaceRoute,
        normalizeRoute: @escaping (WorkspaceRoute) -> WorkspaceRoute,
        applyRoute: @escaping (WorkspaceRoute) -> Void,
        defaults: UserDefaults = .standard
    ) {
        self.normalizeRoute = normalizeRoute
        self.applyRoute = applyRoute
        if let stored = defaults.string(forKey: Self.defaultsKey),
           let route = WorkspaceRoute(rawValue: stored) {
            self.route = normalizeRoute(route)
        } else {
            self.route = normalizeRoute(defaultRoute)
        }
    }

    func select(_ route: WorkspaceRoute) {
        let normalized = normalizeRoute(route)
        guard self.route != normalized else {
            applyRoute(normalized)
            return
        }
        self.route = normalized
        applyRoute(normalized)
        notifyObservers()
    }

    func applyCurrentRoute() {
        select(route)
    }

    func addObserver(_ observer: @escaping (WorkspaceRoute) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(route)
        return id
    }

    func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer(route)
        }
    }
}
