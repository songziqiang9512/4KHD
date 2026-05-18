import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceDetailPaneController {
    static let defaultsKey = "com.songziqiang.4khd.detailPanePresented.v1"

    @ObservationIgnored private var observers: [UUID: (Bool) -> Void] = [:]

    var isPresented: Bool = true {
        didSet {
            guard oldValue != isPresented else { return }
            notifyObservers()
        }
    }

    var preferredContentIdealWidth: CGFloat {
        isPresented ? 380 : 760
    }

    var preferredContentMaxWidth: CGFloat {
        isPresented ? 430 : 10_000
    }

    var gridColumnLimit: Int? {
        isPresented ? 2 : nil
    }

    var preferredGridCardMinimumWidth: CGFloat {
        isPresented ? 148 : 136
    }

    var preferredGridCardMaximumWidth: CGFloat? {
        isPresented ? 210 : nil
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
