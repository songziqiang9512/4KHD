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
    private var timer: Timer?
    private var calls: [QueueCall] = []

    init(name: String, interval: TimeInterval = 0.05, maxInterval: TimeInterval = 2.0) {
        self.name = name
        self.interval = interval
        self.maxInterval = maxInterval
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
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerDidFire()
            }
        }
    }
}
