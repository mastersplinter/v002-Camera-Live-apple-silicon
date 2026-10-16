import CoreGraphics
import Foundation

/// Consumers sample the newest complete frame. Optional change notifications
/// coalesce while a consumer is busy; camera/decoder threads never wait for UI.
public final class PreviewFrames {
    public struct Frame {
        public let image: CGImage
        public let sequence: UInt64
        public let receivedAt: TimeInterval
    }

    private let lock = NSLock()
    private var latest: Frame?
    private var sequence: UInt64 = 0
    private var closed = false
    private var observers: [UUID: () -> Void] = [:]

    /// One pending notification per observer, irrespective of camera speed or
    /// main-thread delays. Notifications carry no images: always sample latest.
    public final class Observation {
        private let lock = NSLock()
        private let queue: DispatchQueue
        private var action: (() -> Void)?
        private var pending = false
        private var remove: (() -> Void)?

        fileprivate init(queue: DispatchQueue, action: @escaping () -> Void, remove: @escaping () -> Void) {
            self.queue = queue; self.action = action; self.remove = remove
        }
        fileprivate func notify() {
            lock.lock()
            guard action != nil, !pending else { lock.unlock(); return }
            pending = true
            lock.unlock()
            queue.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let action = self.action
                self.pending = false
                self.lock.unlock()
                action?()
            }
        }
        public func cancel() {
            lock.lock()
            action = nil
            let remove = self.remove
            self.remove = nil
            lock.unlock()
            remove?()
        }
        deinit { cancel() }
    }

    public init() {}

    public func submit(_ image: CGImage) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        sequence &+= 1
        latest = Frame(image: image, sequence: sequence, receivedAt: ProcessInfo.processInfo.systemUptime)
        let callbacks = Array(observers.values)
        lock.unlock()
        callbacks.forEach { $0() }
    }

    /// Retain the token to observe subsequent submissions/closure. The callback
    /// runs outside the store lock and can safely read or close the store.
    public func observe(on queue: DispatchQueue = .main, _ action: @escaping () -> Void) -> Observation {
        let id = UUID()
        let observation = Observation(queue: queue, action: action) { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.observers.removeValue(forKey: id); self.lock.unlock()
        }
        lock.lock()
        if !closed { observers[id] = { [weak observation] in observation?.notify() } }
        lock.unlock()
        return observation
    }

    public func snapshot() -> Frame? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    /// Each camera session owns a new store, so a late old-session frame cannot
    /// replace the new camera's image, even while shutdown is still in progress.
    public func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        latest = nil
        let callbacks = Array(observers.values)
        observers.removeAll()
        lock.unlock()
        callbacks.forEach { $0() }
    }
}
