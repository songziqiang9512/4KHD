import Foundation
import Observation

// MARK: - Immersive 控制器（窗内大图模式）

@MainActor
@Observable
final class ImmersiveController {
    @ObservationIgnored private var observers: [UUID: (ImmersiveController) -> Void] = [:]

    var isImmersive: Bool = false
    var peekRevealing: Bool = false
    var isToolbarVisible: Bool = true
    @ObservationIgnored private var peekHideWorkItem: DispatchWorkItem?

    func toggle() {
        set(!isImmersive)
    }

    func set(_ on: Bool) {
        if on {
            peekHideWorkItem?.cancel()
            isImmersive = true
            peekRevealing = false
            isToolbarVisible = false
        } else {
            peekHideWorkItem?.cancel()
            isImmersive = false
            peekRevealing = false
            isToolbarVisible = true
        }
        notifyObservers()
    }

    func revealColumns() {
        guard isImmersive else { return }
        peekHideWorkItem?.cancel()
        peekRevealing = true
        notifyObservers()
    }

    func handleColumnHover(_ hovering: Bool) {
        guard isImmersive else { return }
        peekHideWorkItem?.cancel()
        if hovering {
            peekRevealing = true
            notifyObservers()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isImmersive else { return }
            self.peekRevealing = false
            self.notifyObservers()
        }
        peekHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func handleToolbarPointer(isNearTop: Bool) {
        guard isImmersive else { return }
        if isNearTop {
            isToolbarVisible = true
            notifyObservers()
            return
        }

        guard isToolbarVisible else { return }
        isToolbarVisible = false
        notifyObservers()
    }

    func addObserver(_ observer: @escaping (ImmersiveController) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(self)
        return id
    }

    func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer(self)
        }
    }
}
