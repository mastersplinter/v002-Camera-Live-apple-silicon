import AppKit
import SwiftUI
import CameraLiveCore
import CameraLiveVirtualCamera
import Combine
import VirtualCameraShared

// Explicitly use the property wrapper, including with SDKs that also export a
// State macro whose plugin isn't shipped in Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct CameraLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Camera Live") {
            CameraWindow(controller: delegate.controller, virtualCamera: delegate.virtualCamera)
                .frame(minWidth: 400, minHeight: 240)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            SidebarCommands()
            CameraCommands(controller: delegate.controller, virtualCamera: delegate.virtualCamera)
        }
    }
}

private struct CameraCommands: Commands {
    @ObservedObject var controller: CameraController
    @ObservedObject var virtualCamera: VirtualCameraController
    var body: some Commands {
        CommandMenu("Camera") {
            Button("Refresh Cameras") { controller.refresh() }.keyboardShortcut("r")
            Button("Stop Camera") { controller.select(nil) }.disabled(controller.selectedDevice == nil)
            Divider()
            Button("Virtual Camera Setup Guide") { virtualCamera.openSetupGuide() }
            Button("Remove Virtual Camera") { virtualCamera.uninstall() }
                .disabled(!virtualCamera.installed || virtualCamera.busy)
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
