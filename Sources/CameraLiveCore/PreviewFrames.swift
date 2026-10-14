import CoreGraphics
import Foundation

/// The display samples the newest complete frame at its own refresh rate. It
/// never queues old images, and camera/decoder threads never wait for the UI.
public final class PreviewFrames {
    public struct Frame {
        public let image: CGImage
        public let sequence: UInt64
    }

    private let lock = NSLock()
    private var latest: Frame?
    private var sequence: UInt64 = 0
    private var closed = false

    public init() {}

    public func submit(_ image: CGImage) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        sequence &+= 1
        latest = Frame(image: image, sequence: sequence)
    }

    public func snapshot() -> Frame? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    /// Each camera session owns a new store, so a late old-session frame cannot
    /// replace the new camera's image, even while shutdown is still in progress.
    public func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true
        latest = nil
    }
}
