import Foundation

/// Bridges Swift concurrency cancellation to a URLSessionTask and owns its KVO observation.
final class TaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var observation: NSKeyValueObservation?
    private var isCancelled = false

    func attach(_ task: URLSessionTask) {
        lock.lock(); self.task = task; let cancelled = isCancelled; lock.unlock()
        if cancelled { task.cancel() }
    }
    func setObservation(_ o: NSKeyValueObservation) {
        lock.lock(); observation = o; lock.unlock()
    }
    func cancel() {
        lock.lock(); isCancelled = true; let t = task; lock.unlock()
        t?.cancel()
    }
    func finish() {
        lock.lock(); let o = observation; observation = nil; lock.unlock()
        o?.invalidate()
    }
}
