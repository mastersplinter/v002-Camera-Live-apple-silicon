import CameraLiveCore
import CoreMedia
import CoreVideo
import Foundation
import VirtualCameraShared

public enum VirtualCameraOutputStatus: Equatable {
    case stopped, waitingForCamera, waitingForExtension, broadcasting, failed(String)
}

public final class VirtualCameraPublisher {
    private let queue = DispatchQueue(label: "info.v002.CameraLive.virtual-camera", qos: .userInitiated)
    private let report: (VirtualCameraOutputStatus) -> Void
    private var timer: DispatchSourceTimer?
    private var frames: PreviewFrames?
    private var enabled = false
    private var connected = false
    private var lastStatus: VirtualCameraOutputStatus?
    private var lastSequence: UInt64 = 0
    private var lastImage: CVPixelBuffer?
    private var retryAt: TimeInterval = 0
    private var lastAccepted: TimeInterval = 0
    private var renderer: VirtualCameraRenderer?
    private let transport: VirtualCameraTransport

    public convenience init(report: @escaping (VirtualCameraOutputStatus) -> Void) {
        self.init(transport: CMIOVirtualCameraTransport(), report: report)
    }
    init(transport: VirtualCameraTransport, report: @escaping (VirtualCameraOutputStatus) -> Void) {
        self.transport = transport; self.report = report
    }
    public func probe(_ completion: @escaping (Bool) -> Void) {
        queue.async { completion(CMIOVirtualCameraTransport.isAvailable()) }
    }
    public func setFrames(_ frames: PreviewFrames?) {
        queue.async {
            self.disconnect()
            self.frames = frames; self.retryAt = 0
        }
    }
    public func setEnabled(_ enabled: Bool) {
        queue.async { [self] in
            self.enabled = enabled
            if enabled {
                guard self.timer == nil else { return }
                self.retryAt = 0
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / Int(VirtualCameraFormat.framesPerSecond)), leeway: .milliseconds(1))
                timer.setEventHandler { [weak self] in self?.tick() }
                self.timer = timer; timer.resume()
            } else {
                self.timer?.cancel(); self.timer = nil
                self.disconnect(); self.renderer = nil
                self.status(.stopped)
            }
        }
    }
    public func shutdown(completion: @escaping () -> Void = {}) {
        setEnabled(false)
        queue.async { self.frames = nil; completion() }
    }
    private func status(_ value: VirtualCameraOutputStatus) {
        guard value != lastStatus else { return }
        lastStatus = value; report(value)
    }
    private func disconnect() {
        transport.stop(); connected = false
        lastImage = nil; lastSequence = 0
    }
    private func tick() {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let frame = frames?.snapshot(), now - frame.receivedAt < VirtualCameraFormat.staleInterval else {
            if connected { disconnect() }
            status(.waitingForCamera); return
        }
        guard now >= retryAt else { return }
        do {
            if !connected {
                try transport.start(); connected = true; lastAccepted = now
            }
            if renderer == nil { renderer = try VirtualCameraRenderer() }
            if frame.sequence != lastSequence || lastImage == nil {
                lastImage = try renderer!.render(frame.image)
                lastSequence = frame.sequence
            }
            guard let lastImage else { return }
            let sample = try VirtualCameraFormat.sample(lastImage, at: CMClockGetTime(CMClockGetHostTimeClock()))
            if transport.enqueue(sample) {
                lastAccepted = now; status(.broadcasting)
            } else if now - lastAccepted > 1 {
                // A removed/restarted extension or wedged sink must not retain
                // an ever-growing queue or keep reporting a working broadcast.
                disconnect(); retryAt = now + 1; status(.waitingForExtension)
            }
        } catch {
            disconnect(); retryAt = now + 1
            if case VirtualCameraError.notInstalled = error { status(.waitingForExtension) }
            else { status(.failed(error.localizedDescription)) }
        }
    }
    deinit { timer?.cancel(); transport.stop() }
}
