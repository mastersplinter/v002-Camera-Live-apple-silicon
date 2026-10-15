import AppKit
import SwiftUI
import CameraLiveCore
import CameraLiveVirtualCamera
import Combine

@main
struct CameraLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Camera Live") {
            CameraWindow(controller: delegate.controller, virtualCamera: delegate.virtualCamera)
                .frame(minWidth: 820, minHeight: 510)
        }
        .defaultSize(width: 1020, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Refresh Cameras") { delegate.controller.refresh() }.keyboardShortcut("r")
                Button("Virtual Camera Setup Guide") { delegate.virtualCamera.openSetupGuide() }
                Button("Remove Virtual Camera") { delegate.virtualCamera.uninstall() }
                    .disabled(!delegate.virtualCamera.installed || delegate.virtualCamera.busy)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = CameraController()
    let virtualCamera = VirtualCameraController()
    private var previewSubscription: AnyCancellable?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        previewSubscription = controller.$preview.sink { [weak self] in self?.virtualCamera.setFrames($0) }
        controller.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.controller.refresh(automatically: true) }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.controller.setSleeping(true) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.controller.setSleeping(false); self?.controller.refresh() }
        })
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        timer?.invalidate()
        DispatchQueue.main.async {
            let group = DispatchGroup()
            group.enter(); self.virtualCamera.shutdown { group.leave() }
            group.enter(); self.controller.shutdown { group.leave() }
            group.notify(queue: .main) { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct CameraWindow: View {
    @ObservedObject var controller: CameraController
    @ObservedObject var virtualCamera: VirtualCameraController
    private var selectedID: Binding<String?> {
        Binding(get: { controller.selectedDevice?.id }, set: { id in
            // List may clear its selection when a USB row disappears. Retain
            // that device for reconnection; the explicit Stop button clears it.
            if id == nil, let selected = controller.selectedDevice,
               !controller.devices.contains(where: { $0.id == selected.id }) { return }
            controller.select(controller.devices.first { $0.id == id })
        })
    }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Camera Live", systemImage: "camera.aperture")
                    .font(.title2.weight(.semibold)).padding(.top, 10)
                Text("USB CAMERAS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if controller.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connect your camera").font(.headline)
                        Text("Connect the Canon 550D by USB and turn it on. Close other apps that use the camera.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(controller.devices, selection: selectedID) { camera in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(camera.displayName, systemImage: "camera")
                            Text(camera.port).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).tag(camera.id)
                    }.listStyle(.sidebar)
                }
                if let error = controller.discoveryError {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                Button { controller.refresh() } label: { Label("Refresh cameras", systemImage: "arrow.clockwise") }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label("Virtual Camera", systemImage: "video").font(.headline)
                    Text(virtualCamera.message).font(.caption).foregroundStyle(.secondary)
                    if virtualCamera.enabled {
                        Button("Stop Virtual Camera") { virtualCamera.stop() }
                    } else {
                        Button(virtualCamera.installed ? "Start Virtual Camera" : "Enable Virtual Camera") { virtualCamera.start() }
                            .disabled(virtualCamera.busy)
                    }
                    if !virtualCamera.installed {
                        Button("Setup guide") { virtualCamera.openSetupGuide() }.buttonStyle(.link)
                    }
                }
                Text("Syphon sharing is also available.").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(minWidth: 235, idealWidth: 265, maxWidth: 330)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(controller.selectedDevice?.displayName ?? "Live view").font(.title2.weight(.semibold))
                        HStack(spacing: 7) {
                            Circle().fill(controller.state == .streaming ? Color.green : Color.secondary).frame(width: 7, height: 7)
                            Text(controller.state.title).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if controller.selectedDevice != nil {
                        if case .failed = controller.state { Button("Try again") { controller.retry() } }
                        Button("Stop") { controller.select(nil) }
                    }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.92))
                    if let frames = controller.preview, controller.statistics != nil {
                        LivePreview(frames: frames).id(ObjectIdentifier(frames))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).padding(1)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "camera.viewfinder").font(.system(size: 42, weight: .light))
                            Text(controller.state == .starting ? "Opening live view…" : "Select a camera to start")
                                .font(.headline)
                            if controller.state == .waitingForCamera { Text("The feed will resume when the camera reconnects.").font(.callout) }
                        }.foregroundStyle(.white.opacity(0.7)).padding(30)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if case let .failed(message) = controller.state {
                    Label(message, systemImage: "exclamationmark.triangle").font(.callout)
                        .foregroundStyle(.orange).textSelection(.enabled)
                }
                HStack {
                    if let stats = controller.statistics {
                        Text("\(stats.width) × \(stats.height)")
                        Text(String(format: "%.1f fps", stats.framesPerSecond))
                        Spacer()
                        Text(stats.hasClients ? "Syphon connected" : "Syphon available • waiting for an app")
                    } else {
                        Text("Live-view resolution is set by the camera.")
                        Spacer()
                        Text("Apple Silicon · Metal")
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}

private struct LivePreview: NSViewRepresentable {
    let frames: PreviewFrames
    func makeNSView(context: Context) -> NSView {
        // The publishing pipeline has already verified that Metal is available.
        // Keep any unexpected preview allocation failure local to this view.
        do { return try CameraPreviewView(frames: frames) }
        catch {
            let label = NSTextField(labelWithString: "Preview unavailable: \(error.localizedDescription)")
            label.textColor = .white
            return label
        }
    }
    func updateNSView(_ view: NSView, context: Context) {}
    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view as? CameraPreviewView)?.isPaused = true
    }
}
