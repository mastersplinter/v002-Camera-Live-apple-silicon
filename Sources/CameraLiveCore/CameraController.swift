import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

public protocol FramePublishing: AnyObject {
    func submit(jpeg: Data)
    func stop(completion: @escaping () -> Void)
}
extension MetalFramePipeline: FramePublishing {}

public enum CameraState: Equatable {
    case idle, starting, streaming, stopping, waitingForCamera, suspended, failed(String)
    public var title: String {
        switch self {
        case .idle: return "Ready"
        case .starting: return "Starting live view"
        case .streaming: return "Live"
        case .stopping: return "Stopping"
        case .waitingForCamera: return "Waiting for camera"
        case .suspended: return "Paused for sleep"
        case .failed: return "Camera error"
        }
    }
}

/// Main-thread orchestration; USB and image work never execute on the main thread.
@MainActor
public final class CameraController: ObservableObject {
    public typealias PipelineFactory = (String, @escaping (CGImage) -> Void, @escaping (StreamStatistics) -> Void,
                                        @escaping (Error) -> Void) throws -> FramePublishing
    @Published public private(set) var devices: [CameraDevice] = []
    @Published public private(set) var selectedDevice: CameraDevice?
    @Published public private(set) var state: CameraState = .idle
    @Published public private(set) var statistics: StreamStatistics?
    @Published public private(set) var preview: PreviewFrames?
    @Published public private(set) var discoveryError: String?
    private let sourceFactory: (CameraDevice) -> CameraSource
    private let pipelineFactory: PipelineFactory
    private let discovery: (@escaping (Result<[CameraDevice], Error>) -> Void) -> Void
    private let defaults: UserDefaults?
    private var generation = 0
    private var stopping = false
    private var refreshing = false
    private var sleeping = false
    private var failedDeviceID: String?
    private var stopCallbacks: [() -> Void] = []
    private var assertion: IOPMAssertionID = 0
    private struct Run {
        let generation: Int
        let device: CameraDevice
        let source: CameraSource
        let pipeline: FramePublishing
        let preview: PreviewFrames
    }
    private var run: Run?

    public init(defaults: UserDefaults? = .standard,
                sourceFactory: @escaping (CameraDevice) -> CameraSource = { CameraCatalog.shared.source(for: $0) },
                pipelineFactory: @escaping PipelineFactory = { try MetalFramePipeline(name: $0, preview: $1, report: $2, failure: $3) },
                discovery: @escaping (@escaping (Result<[CameraDevice], Error>) -> Void) -> Void = { CameraCatalog.shared.discover(completion: $0) }) {
        self.defaults = defaults
        self.sourceFactory = sourceFactory
        self.pipelineFactory = pipelineFactory
        self.discovery = discovery
        if let data = defaults?.data(forKey: "CameraLive.selectedCamera.v1") {
            selectedDevice = try? JSONDecoder().decode(CameraDevice.self, from: data)
        }
    }

    public func refresh(automatically: Bool = false) {
        // Autodetection shares the USB driver's serial queue. Repeating it during
        // live view interrupts capture. An unplug fails capture and closes the
        // session, after which polling resumes. Explicit refresh remains available.
        if automatically, run != nil || stopping || sleeping { return }
        guard !refreshing else { return }
        refreshing = true
        discovery { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                switch result {
                case let .success(devices): self.discoveryError = nil; self.updateDevices(devices)
                case let .failure(error): self.discoveryError = error.localizedDescription
                }
            }
        }
    }

    public func updateDevices(_ devices: [CameraDevice]) {
        self.devices = devices
        if let selectedDevice, let replacement = selectedDevice.matching(in: devices) {
            self.selectedDevice = replacement
        }
        reconcile()
    }

    public func select(_ device: CameraDevice?) {
        selectedDevice = device
        failedDeviceID = nil
        if let device, let encoded = try? JSONEncoder().encode(device) {
            defaults?.set(encoded, forKey: "CameraLive.selectedCamera.v1")
        } else { defaults?.removeObject(forKey: "CameraLive.selectedCamera.v1") }
        reconcile()
    }

    public func retry() {
        failedDeviceID = nil
        reconcile()
    }

    public func setSleeping(_ sleeping: Bool) {
        self.sleeping = sleeping
        failedDeviceID = nil
        reconcile()
    }

    /// Retains the saved selection for the next launch but closes this session.
    public func shutdown(completion: @escaping () -> Void = {}) {
        selectedDevice = nil
        stopCallbacks.append(completion)
        reconcile()
    }

    private func reconcile() {
        guard !stopping else { return }
        let wanted = sleeping ? nil : selectedDevice?.matching(in: devices)
        if let run {
            if wanted?.id == run.device.id, failedDeviceID == nil { return }
            end(run)
            return
        }
        releaseSleepAssertion()
        statistics = nil
        preview = nil
        if sleeping { state = .suspended }
        else if let selectedDevice {
            if let wanted {
                guard failedDeviceID != selectedDevice.id else { return }
                begin(wanted)
                return
            } else {
                failedDeviceID = nil
                state = .waitingForCamera
            }
        } else { state = .idle }
        let callbacks = stopCallbacks
        stopCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    private func begin(_ device: CameraDevice) {
        generation += 1
        let token = generation
        state = .starting
        do {
            let frames = PreviewFrames()
            let pipeline = try pipelineFactory(device.displayName, { frames.submit($0) }, { [weak self] statistics in
                DispatchQueue.main.async {
                    guard let self, self.run?.generation == token else { return }
                    self.statistics = statistics
                    if self.state != .streaming { self.state = .streaming }
                }
            }, { [weak self] error in
                DispatchQueue.main.async { self?.failed(error, generation: token) }
            })
            let source = sourceFactory(device)
            preview = frames
            run = Run(generation: token, device: device, source: source, pipeline: pipeline, preview: frames)
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Camera Live USB live view" as CFString, &assertion)
            source.start { [weak self, weak pipeline] event in
                switch event {
                case let .jpeg(data): pipeline?.submit(jpeg: data)
                case let .failed(error): DispatchQueue.main.async { self?.failed(error, generation: token) }
                }
            }
        } catch {
            failedDeviceID = device.id
            state = .failed(error.localizedDescription)
        }
    }

    private func failed(_ error: Error, generation token: Int) {
        guard let run, run.generation == token else { return }
        failedDeviceID = run.device.id
        state = .failed(error.localizedDescription)
        end(run, preserveError: true)
    }

    private func end(_ old: Run, preserveError: Bool = false) {
        run = nil // Invalidate every queued frame and error before starting cleanup.
        old.preview.close()
        stopping = true
        if !preserveError { state = .stopping }
        let group = DispatchGroup()
        group.enter(); old.source.stop { group.leave() }
        group.enter(); old.pipeline.stop { group.leave() }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.stopping = false
            self.reconcile()
        }
    }

    private func releaseSleepAssertion() {
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
    }

    deinit {
        run?.preview.close()
        run?.source.stop(completion: {})
        run?.pipeline.stop(completion: {})
        if assertion != 0 { IOPMAssertionRelease(assertion) }
    }
}
