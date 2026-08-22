import Foundation
import Observation

// MARK: - Immersive 控制器（窗内大图模式）

@MainActor
@Observable
final class ImmersiveController {
    @ObservationIgnored private var observers: [UUID: (ImmersiveController) -> Void] = [:]
    @ObservationIgnored private var hideToolbarWorkItem: DispatchWorkItem?

    var isImmersive: Bool = false
    var peekRevealing: Bool = false
    var isToolbarVisible: Bool = true

    func toggle() {
        set(!isImmersive)
    }

    func set(_ on: Bool) {
        cancelHideToolbar()
        if on {
            isImmersive = true
            peekRevealing = false
            isToolbarVisible = false
        } else {
            isImmersive = false
            peekRevealing = false
            isToolbarVisible = true
        }
        notifyObservers()
    }

    func handleToolbarPointer(isNearTop: Bool) {
        guard isImmersive else { return }
        if isNearTop {
            // 工具栏已可见时状态未变,只取消待执行的隐藏调度,不再重复广播
            // (顶部 72px 内的 mouseMoved 风暴会反复触发 observer)。
            if isToolbarVisible {
                cancelHideToolbar()
                return
            }
            cancelHideToolbar()
            isToolbarVisible = true
            notifyObservers()
            return
        }

        guard isToolbarVisible, hideToolbarWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isToolbarVisible = false
            self.hideToolbarWorkItem = nil
            self.notifyObservers()
        }
        hideToolbarWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func cancelHideToolbar() {
        hideToolbarWorkItem?.cancel()
        hideToolbarWorkItem = nil
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
