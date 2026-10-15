import Foundation

/// User-visible state, including installation steps that precede frame delivery.
public enum VirtualCameraState: Equatable {
    case notInstalled, ready, enabling, needsApproval, needsRestart, removing
    case stopped, waitingForCamera, waitingForExtension, broadcasting, failed(String)

    public var title: String {
        switch self {
        case .notInstalled: return "Virtual camera off"
        case .ready, .stopped: return "Preview only"
        case .enabling: return "Setting up virtual camera"
        case .needsApproval: return "Approval needed"
        case .needsRestart: return "Restart needed"
        case .removing: return "Removing virtual camera"
        case .waitingForCamera: return "Virtual camera on standby"
        case .waitingForExtension: return "Connecting virtual camera"
        case .broadcasting: return "Virtual camera on"
        case .failed: return "Virtual camera needs attention"
        }
    }

    public var message: String {
        switch self {
        case .notInstalled: return "Use Camera Live directly in Zoom and other video apps."
        case .ready: return "Ready. Select Camera Live in Zoom’s camera settings."
        case .enabling: return "Enabling the virtual camera…"
        case .needsApproval: return "Allow Camera Live in System Settings → General → Login Items & Extensions → Camera Extensions."
        case .needsRestart: return "Restart your Mac to finish virtual-camera setup."
        case .removing: return "Removing the virtual camera…"
        case .stopped: return "Virtual camera stopped."
        case .waitingForCamera: return "Start your camera to send video to Zoom."
        case .waitingForExtension: return "Waiting for macOS to make the virtual camera available…"
        case .broadcasting: return "Broadcasting. Choose Camera Live in Zoom."
        case .failed(let message): return message
        }
    }

    public var needsAttention: Bool {
        switch self {
        case .needsApproval, .needsRestart, .waitingForExtension, .failed: return true
        default: return false
        }
    }
}
