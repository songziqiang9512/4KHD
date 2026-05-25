import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceDetailPaneController {
    static let defaultsKey = "com.songziqiang.4khd.detailPanePresented.v1"

    @ObservationIgnored private var observers: [UUID: (Bool) -> Void] = [:]

    var isPresented: Bool = false {
        didSet {
            guard oldValue != isPresented else { return }
            notifyObservers()
        }
    }

    func setPresented(_ isPresented: Bool) {
        self.isPresented = isPresented
    }

    func toggle() {
        isPresented.toggle()
    }

    func addObserver(_ observer: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(isPresented)
        return id
    }

    func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer(isPresented)
        }
    }
}
