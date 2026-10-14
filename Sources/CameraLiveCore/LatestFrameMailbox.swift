import Foundation

/// One frame being processed plus at most one waiting frame. Overload replaces the
/// waiting frame, so slow consumers cannot accumulate seconds of video latency.
final class LatestFrameMailbox<Value> {
    private let lock = NSLock()
    private var value: Value?
    private var scheduled = false
    private var closed = false
    private var drops = 0

    var droppedCount: Int { lock.lock(); defer { lock.unlock() }; return drops }

    /// True means the caller must schedule a worker. False means one already exists.
    func offer(_ newValue: Value) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return false }
        if value != nil { drops += 1 }
        value = newValue
        guard !scheduled else { return false }
        scheduled = true
        return true
    }

    func take() -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard !closed, let next = value else { scheduled = false; return nil }
        value = nil
        return next
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true
        value = nil
    }
}
