import Foundation

@MainActor
final class WorkspaceCoalescingQueue {
    static let standard = WorkspaceCoalescingQueue(name: "Standard", interval: 0.05, maxInterval: 0.1)

    let name: String
    var isPaused = false

    private struct QueueCall {
        let id: String
        let operation: @MainActor () -> Void
    }

    private let interval: TimeInterval
    private let maxInterval: TimeInterval
    private var lastCallTime = Date.distantFuture
    // Timer 的创建与使用都在 MainActor；标记 nonisolated 仅为允许 deinit 中 invalidate（线程安全）。
    nonisolated(unsafe) private var timer: Timer?
    private var calls: [QueueCall] = []

    init(name: String, interval: TimeInterval = 0.05, maxInterval: TimeInterval = 2.0) {
        self.name = name
        self.interval = interval
        self.maxInterval = maxInterval
    }

    deinit {
        timer?.invalidate()
    }

    func add(id: String, operation: @escaping @MainActor () -> Void) {
        restartTimer()
        if !calls.contains(where: { $0.id == id }) {
            calls.append(QueueCall(id: id, operation: operation))
        }
        if Date().timeIntervalSince(lastCallTime) > maxInterval {
            timerDidFire()
        }
    }

    func performCallsImmediately() {
        guard !isPaused else { return }
        let callsToMake = calls
        calls.removeAll()
        callsToMake.forEach { $0.operation() }
    }

    private func timerDidFire() {
        lastCallTime = Date()
        performCallsImmediately()
    }

    private func restartTimer() {
        // 已有未触发的 timer 时直接复用:add 风暴不再反复 invalidate + 重建。
        // fire 后 non-repeating timer 自动失效,下一次 add 会重新创建。
        if timer?.isValid == true { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerDidFire()
            }
        }
    }
}
