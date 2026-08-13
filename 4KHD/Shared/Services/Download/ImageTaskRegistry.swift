import Foundation
import Nuke

/// 登记在飞的 Nuke ImageTask,取消时能立即结束它们。
/// loadData 的完成回调恰好触发一次;register 时顺带清理已结束任务,
/// 登记表不会无限增长。
final nonisolated class ImageTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: ImageTask] = [:]

    func register(_ task: ImageTask) {
        lock.lock()
        tasks = tasks.filter { $0.value.state == .running }
        tasks[ObjectIdentifier(task)] = task
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        let snapshot = Array(tasks.values)
        lock.unlock()
        snapshot.forEach { $0.cancel() }
    }
}
