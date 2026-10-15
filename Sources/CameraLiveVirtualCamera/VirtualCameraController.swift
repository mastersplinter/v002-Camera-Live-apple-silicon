import AppKit
import Combine
import CameraLiveCore
import SystemExtensions
import VirtualCameraShared

@MainActor
public final class VirtualCameraController: NSObject, ObservableObject, @preconcurrency OSSystemExtensionRequestDelegate {
    @Published public private(set) var installed = false
    @Published public private(set) var enabled = false
    @Published public private(set) var busy = false
    @Published public var framing: VideoFraming = {
        guard let data = UserDefaults.standard.data(forKey: "videoFraming"),
              let saved = try? JSONDecoder().decode(VideoFraming.self, from: data) else { return VideoFraming() }
        return saved
    }() {
        didSet {
            guard framing != oldValue else { return }
            if let data = try? JSONEncoder().encode(framing) { UserDefaults.standard.set(data, forKey: "videoFraming") }
            publisher.setFraming(framing)
        }
    }
    @Published public private(set) var state: VirtualCameraState = .notInstalled
    public var message: String { state.message }
    private var request: OSSystemExtensionRequest?
    private enum RequestKind { case inspect, activate, remove }
    private var requestKind: RequestKind?
    private var checkedBundledExtension = false
    private lazy var publisher: VirtualCameraPublisher = {
        let result = VirtualCameraPublisher { [weak self] status in
            DispatchQueue.main.async { self?.update(status) }
        }
        result.setFraming(framing)
        return result
    }()
    public override init() { super.init(); refresh() }
    public func setFrames(_ frames: PreviewFrames?) { publisher.setFrames(frames) }
    public func refresh() {
        guard !busy else { return }
        // Opening CMIO before replacing the extension can leave this process
        // connected to the retired device. Inspect installation through the
        // system-extension manager until activation has finished instead.
        if !checkedBundledExtension,
           Bundle.main.object(forInfoDictionaryKey: "CameraLiveVirtualCameraInstallable") as? Bool == true {
            busy = true
            submit(OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: VirtualCameraFormat.extensionIdentifier,
                queue: .main), kind: .inspect)
            return
        }
        publisher.probe { [weak self] available in
            DispatchQueue.main.async {
                guard let self else { return }
                self.installed = available
                if available, !self.enabled, !self.busy { self.state = .ready }
            }
        }
    }
    public func start() {
        guard !busy else { return }
        let installable = Bundle.main.object(forInfoDictionaryKey: "CameraLiveVirtualCameraInstallable") as? Bool == true
        if installed, checkedBundledExtension || !installable {
            state = .waitingForCamera
            enabled = true; publisher.setEnabled(true); return
        }
        guard Bundle.main.object(forInfoDictionaryKey: "CameraLiveVirtualCameraInstallable") as? Bool == true else {
            state = .failed("Virtual-camera setup needs an Apple-signed build. See the setup guide.")
            return
        }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            state = .failed("Move Camera Live to Applications, reopen it, then enable the virtual camera.")
            return
        }
        busy = true
        state = .enabling
        submit(OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: VirtualCameraFormat.extensionIdentifier, queue: .main), kind: .activate)
    }
    public func stop() { enabled = false; state = .stopped; publisher.setEnabled(false) }
    public func uninstall() {
        guard !busy else { return }
        stop(); busy = true
        state = .removing
        submit(OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: VirtualCameraFormat.extensionIdentifier, queue: .main), kind: .remove)
    }
    public func shutdown(completion: @escaping () -> Void) {
        enabled = false
        publisher.shutdown(completion: completion)
    }
    public func openSetupGuide() {
        if let url = Bundle.main.url(forResource: "VIRTUAL_CAMERA", withExtension: "md") { NSWorkspace.shared.open(url) }
    }
    public func openSystemSettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
    private func submit(_ request: OSSystemExtensionRequest, kind: RequestKind) {
        self.request = request; requestKind = kind; request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    private func update(_ status: VirtualCameraOutputStatus) {
        guard !busy else { return }
        switch status {
        case .stopped: state = installed ? .stopped : .notInstalled
        case .waitingForCamera: state = .waitingForCamera
        case .waitingForExtension: state = .waitingForExtension; refresh()
        case .broadcasting: installed = true; state = .broadcasting
        case let .failed(error): state = .failed(error)
        }
    }
    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        guard self.request === request else { return }
        state = .needsApproval
    }
    public func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        guard self.request === request, requestKind == .inspect else { return }
        self.request = nil; requestKind = nil; busy = false
        installed = properties.contains { $0.isEnabled && !$0.isUninstalling }
        // A host-only UI update can keep the existing camera extension. Avoid
        // replacing an already enabled identical version and retiring its device.
        let extensionURL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Library/SystemExtensions/\(VirtualCameraFormat.extensionIdentifier).systemextension")
        if let bundled = Bundle(url: extensionURL),
           let version = bundled.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           let release = bundled.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            checkedBundledExtension = properties.contains {
                $0.isEnabled && !$0.isUninstalling && $0.bundleVersion == version && $0.bundleShortVersion == release
            }
        }
        if installed { state = .ready }
    }
    public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        guard self.request === request, let kind = requestKind else { return }
        self.request = nil; requestKind = nil; busy = false
        if result == .willCompleteAfterReboot {
            state = .needsRestart
        } else if kind == .remove {
            installed = false; checkedBundledExtension = false; state = .notInstalled
        } else if kind == .activate {
            checkedBundledExtension = true
            state = .waitingForCamera
            installed = true; enabled = true
            publisher.setEnabled(true)
        }
    }
    public func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        guard self.request === request else { return }
        self.request = nil; requestKind = nil; busy = false
        state = .failed("Virtual-camera setup failed: \(error.localizedDescription)")
    }
    public func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                        withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
}
