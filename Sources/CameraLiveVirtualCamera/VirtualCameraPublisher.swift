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
    private enum TimerMode { case video, retry }
    private var timerMode: TimerMode?
    private var timerGeneration: UInt64 = 0
    private var frameObservation: PreviewFrames.Observation?
    private var frames: PreviewFrames?
    private var enabled = false
    private var connected = false
    private var lastStatus: VirtualCameraOutputStatus?
    private var lastSequence: UInt64 = 0
    private var lastImage: CVPixelBuffer?
    private var retryAt: TimeInterval = 0
    private var lastAccepted: TimeInterval = 0
    private var renderer: VirtualCameraRenderer?
    private var framing = VideoFraming()
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
            self.cancelTimer(); self.frameObservation = nil
            self.disconnect()
            self.frames = frames; self.retryAt = 0
            if self.enabled { self.tick() }
        }
    }
    public func setFraming(_ framing: VideoFraming) {
        queue.async { [self] in
            guard self.framing != framing else { return }
            let changedCanvas = self.framing.canvas != framing.canvas
            if changedCanvas {
                cancelTimer(); disconnect(); retryAt = 0
            }
            self.framing = framing
            // Crop changes must be visible even when reusing the same camera frame.
            lastImage = nil; lastSequence = 0
            if changedCanvas, enabled { tick() }
        }
    }
    public func setEnabled(_ enabled: Bool) {
        queue.async { [self] in
            if enabled {
                guard !self.enabled else { return }
                self.enabled = true
                self.retryAt = 0
                self.tick()
            } else {
                self.enabled = false
                self.cancelTimer(); self.frameObservation = nil
                self.disconnect()
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
        renderer = nil
    }

    private func cancelTimer() {
        timerGeneration &+= 1
        timer?.cancel(); timer = nil; timerMode = nil
    }

    private func schedule(_ mode: TimerMode) {
        if mode == .video, timerMode == .video { return }
        cancelTimer()
        let token = timerGeneration
        let timer = DispatchSource.makeTimerSource(queue: queue)
        if mode == .video {
            let interval = DispatchTimeInterval.nanoseconds(1_000_000_000 / Int(VirtualCameraFormat.framesPerSecond))
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))
        } else {
            timer.schedule(deadline: .now() + max(0.001, retryAt - ProcessInfo.processInfo.systemUptime), leeway: .milliseconds(1))
        }
        timer.setEventHandler { [weak self] in
            guard let self, token == self.timerGeneration else { return }
            if mode == .retry { self.cancelTimer() }
            self.tick()
        }
        self.timer = timer; timerMode = mode; timer.resume()
    }

    private func waitForFreshFrame() {
        cancelTimer()
        if frameObservation == nil {
            frameObservation = frames?.observe(on: queue) { [weak self] in self?.tick() }
            // Close the race between the initial empty/stale snapshot and
            // subscribing. The newest frame may have arrived in that interval.
            if let frame = frames?.snapshot(),
               ProcessInfo.processInfo.systemUptime - frame.receivedAt < VirtualCameraFormat.staleInterval {
                tick()
            }
        }
    }

    private func tick() {
        autoreleasepool { publishIfReady() }
    }

    private func publishIfReady() {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let frame = frames?.snapshot(), now - frame.receivedAt < VirtualCameraFormat.staleInterval else {
            if connected { disconnect() }
            status(.waitingForCamera)
            waitForFreshFrame(); return
        }
        frameObservation = nil
        guard now >= retryAt else { schedule(.retry); return }
        do {
            if !connected {
                try transport.start(canvas: framing.canvas); connected = true; lastAccepted = now
            }
            if renderer == nil { renderer = try VirtualCameraRenderer(canvas: framing.canvas) }
            if frame.sequence != lastSequence || lastImage == nil {
                lastImage = try renderer!.render(frame.image, framing: framing)
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
                schedule(.retry); return
            }
            schedule(.video)
        } catch {
            disconnect(); retryAt = now + 1
            if case VirtualCameraError.notInstalled = error { status(.waitingForExtension) }
            else { status(.failed(error.localizedDescription)) }
            schedule(.retry)
        }
    }
    deinit { timer?.cancel(); frameObservation?.cancel(); transport.stop() }
}
