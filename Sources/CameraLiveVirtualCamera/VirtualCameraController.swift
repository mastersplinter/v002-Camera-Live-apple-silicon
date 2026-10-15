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
    @Published public private(set) var message = "Use Camera Live directly in Zoom and other video apps."
    private var request: OSSystemExtensionRequest?
    private enum RequestKind { case inspect, activate, remove }
    private var requestKind: RequestKind?
    private var checkedBundledExtension = false
    private lazy var publisher = VirtualCameraPublisher { [weak self] status in
        DispatchQueue.main.async { self?.update(status) }
    }
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
                if available, !self.enabled, !self.busy { self.message = "Ready. Select Camera Live in Zoom’s camera settings." }
            }
        }
    }
    public func start() {
        guard !busy else { return }
        let installable = Bundle.main.object(forInfoDictionaryKey: "CameraLiveVirtualCameraInstallable") as? Bool == true
        if installed, checkedBundledExtension || !installable {
            enabled = true; publisher.setEnabled(true); return
        }
        guard Bundle.main.object(forInfoDictionaryKey: "CameraLiveVirtualCameraInstallable") as? Bool == true else {
            message = "Virtual-camera setup needs an Apple-signed build. See the setup guide."
            return
        }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            message = "Move Camera Live to Applications, reopen it, then enable the virtual camera."
            return
        }
        busy = true
        message = "Enabling the virtual camera…"
        submit(OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: VirtualCameraFormat.extensionIdentifier, queue: .main), kind: .activate)
    }
    public func stop() { enabled = false; publisher.setEnabled(false) }
    public func uninstall() {
        guard !busy else { return }
        stop(); busy = true
        message = "Removing the virtual camera…"
        submit(OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: VirtualCameraFormat.extensionIdentifier, queue: .main), kind: .remove)
    }
    public func shutdown(completion: @escaping () -> Void) {
        enabled = false
        publisher.shutdown(completion: completion)
    }
    public func openSetupGuide() {
        if let url = Bundle.main.url(forResource: "VIRTUAL_CAMERA", withExtension: "md") { NSWorkspace.shared.open(url) }
    }
    private func submit(_ request: OSSystemExtensionRequest, kind: RequestKind) {
        self.request = request; requestKind = kind; request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    private func update(_ status: VirtualCameraOutputStatus) {
        guard !busy else { return }
        switch status {
        case .stopped: message = installed ? "Virtual camera stopped." : "Virtual camera is not enabled."
        case .waitingForCamera: message = "Start your camera to send video to Zoom."
        case .waitingForExtension: message = "Waiting for macOS to make the virtual camera available…"; refresh()
        case .broadcasting: installed = true; message = "Broadcasting. Choose Camera Live in Zoom."
        case let .failed(error): message = error
        }
    }
    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        guard self.request === request else { return }
        message = "Allow Camera Live in System Settings → General → Login Items & Extensions → Camera Extensions."
    }
    public func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        guard self.request === request, requestKind == .inspect else { return }
        self.request = nil; requestKind = nil; busy = false
        installed = properties.contains { $0.isEnabled && !$0.isUninstalling }
        if installed { message = "Ready. Select Camera Live in Zoom’s camera settings." }
    }
    public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        guard self.request === request, let kind = requestKind else { return }
        self.request = nil; requestKind = nil; busy = false
        if result == .willCompleteAfterReboot {
            message = "Restart your Mac to finish virtual-camera setup."
        } else if kind == .remove {
            installed = false; checkedBundledExtension = false; message = "Virtual camera removed."
        } else if kind == .activate {
            checkedBundledExtension = true
            installed = true; enabled = true
            publisher.setEnabled(true)
        }
    }
    public func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        guard self.request === request else { return }
        self.request = nil; requestKind = nil; busy = false
        message = "Virtual-camera setup failed: \(error.localizedDescription)"
    }
    public func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                        withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
}
