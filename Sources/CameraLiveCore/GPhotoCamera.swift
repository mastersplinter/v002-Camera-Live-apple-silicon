import Foundation
import CameraLiveNative

private func cameraError(_ operation: String, _ code: Int32) -> CameraLiveError {
    .camera(operation: operation, code: code, detail: String(cString: cl_error_string(code)))
}

private final class Cancellation {
    let pointer: OpaquePointer
    private let lock = NSLock()
    private var value = false
    init() { pointer = cl_cancellation_new()! }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        value = true
        cl_cancellation_cancel(pointer)
    }
    deinit { cl_cancellation_free(pointer) }
}

/// All libgphoto2 work shares one serial queue: discovery, session setup, preview,
/// keep-alive and shutdown can never race inside the camera driver.
public final class CameraCatalog {
    public static let shared = CameraCatalog()
    private let queue = DispatchQueue(label: "info.v002.CameraLive.camera", qos: .userInitiated)
    private init() {
        let resources = Bundle.main.resourceURL
        if let base = resources?.appendingPathComponent("CameraDrivers"),
           FileManager.default.fileExists(atPath: base.path) {
            cl_configure_drivers(base.appendingPathComponent("camlibs").path,
                                 base.appendingPathComponent("iolibs").path)
        }
    }

    public func discover(completion: @escaping (Result<[CameraDevice], Error>) -> Void) {
        queue.async {
            var list: OpaquePointer?
            let code = cl_list_devices(&list)
            defer { cl_list_free(list) }
            guard code >= 0, let list else {
                completion(.failure(cameraError("Find cameras", code))); return
            }
            let devices = (0..<cl_list_count(list)).compactMap { index -> CameraDevice? in
                guard let model = cl_list_model(list, index), let port = cl_list_port(list, index) else { return nil }
                return CameraDevice(model: String(cString: model), port: String(cString: port))
            }.sorted { $0.id < $1.id }
            completion(.success(devices))
        }
    }

    public func source(for device: CameraDevice) -> CameraSource { GPhotoSource(device: device, queue: queue) }
}

private final class GPhotoSource: CameraSource {
    private let device: CameraDevice
    private let queue: DispatchQueue
    private let cancellation = Cancellation()
    // The following properties belong exclusively to queue.
    private var session: OpaquePointer?
    private var receive: ((CaptureEvent) -> Void)?
    private var started = false
    private var consecutiveFailures = 0
    private var lastKeepAlive = ProcessInfo.processInfo.systemUptime

    init(device: CameraDevice, queue: DispatchQueue) { self.device = device; self.queue = queue }

    func start(_ receive: @escaping (CaptureEvent) -> Void) {
        queue.async {
            guard !self.started, !self.cancellation.isCancelled else { return }
            self.started = true
            self.receive = receive
            let code = cl_session_open(self.device.model, self.device.port, self.cancellation.pointer, &self.session)
            guard code >= 0 else { self.fail(cameraError("Open \(self.device.displayName)", code)); return }
            self.capture()
        }
    }

    private func capture() {
        guard !cancellation.isCancelled, let session else { return }
        let beginning = ProcessInfo.processInfo.systemUptime
        var bytes: UnsafeMutableRawPointer?
        var count = 0
        let code = cl_session_preview(session, &bytes, &count)
        defer { cl_bytes_free(bytes) }
        guard !cancellation.isCancelled else { return }
        if code >= 0, let bytes, count > 0 {
            consecutiveFailures = 0
            receive?(.jpeg(Data(bytes: bytes, count: count)))
        } else {
            consecutiveFailures += 1
            // libgphoto2 already retries EOS "not ready" for up to three seconds.
            guard cl_error_is_transient(code) != 0, consecutiveFailures < 5 else {
                fail(cameraError("Read live view", code)); return
            }
        }
        if beginning - lastKeepAlive >= 25 * 60 {
            // Preview itself sends Canon KeepDeviceOn. Reasserting the viewfinder
            // additionally prevents the camera's long-running live-view timeout.
            _ = cl_session_keep_alive(session)
            lastKeepAlive = beginning
        }
        let interval = code < 0 ? 0.2 : 1.0 / 30.0
        let delay = max(0, interval - (ProcessInfo.processInfo.systemUptime - beginning))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.capture() }
    }

    private func fail(_ error: Error) {
        let callback = receive
        close()
        if !cancellation.isCancelled { callback?(.failed(error)) }
    }

    private func close() {
        if let session { cl_session_close(session) }
        session = nil
        receive = nil
    }

    func stop(completion: @escaping () -> Void) {
        cancellation.cancel()
        queue.async { self.close(); completion() }
    }
}
