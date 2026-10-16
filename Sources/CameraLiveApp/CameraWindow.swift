import AppKit
import SwiftUI
import CameraLiveCore
import CameraLiveVirtualCamera
import VirtualCameraShared

struct CameraWindow: View {
    @ObservedObject var controller: CameraController
    @ObservedObject var virtualCamera: VirtualCameraController
    @ViewState private var columns: NavigationSplitViewVisibility
    @ViewState private var showingInspector = false
    @ViewState private var inspectorPage = InspectorPage.stream
    @ViewState private var windowSize = CGSize(width: 1080, height: 720)
    @ViewState private var compactPanel: CompactPanel?

    private enum CompactPanel: Equatable {
        case cameras, inspector
    }

    private var compact: Bool { windowSize.width < 700 || windowSize.height < 400 }
    private var narrow: Bool { windowSize.width < 320 }
    private var hasNotices: Bool {
        if case .failed = controller.state { return true }
        return virtualCamera.state.needsAttention
    }
    private func presenting(_ panel: CompactPanel) -> Binding<Bool> {
        Binding(get: { compact && compactPanel == panel }, set: { presented in
            if presented { compactPanel = panel }
            else if compactPanel == panel { compactPanel = nil }
        })
    }

    init(controller: CameraController, virtualCamera: VirtualCameraController) {
        self.controller = controller
        self.virtualCamera = virtualCamera
        // First launch exposes camera selection. Returning users get Focus.
        _columns = ViewState(initialValue: controller.selectedDevice == nil ? .all : .detailOnly)
    }

    private enum InspectorPage: String {
        case stream = "Stream", framing = "Framing", cameras = "Cameras"
    }

    private var inspectorPages: [InspectorPage] {
        narrow ? [.stream, .framing, .cameras] : [.stream, .framing]
    }

    private var selectedID: Binding<String?> {
        Binding(get: { controller.selectedDevice?.id }, set: { id in
            // Preserve the remembered camera when its USB row disappears.
            if id == nil, let selected = controller.selectedDevice,
               !controller.devices.contains(where: { $0.id == selected.id }) { return }
            controller.select(controller.devices.first { $0.id == id })
        })
    }

    var body: some View {
        // Let the window's explicit minimum govern resizing, rather than the
        // combined ideal sizes of the sidebar, preview and inspector.
        GeometryReader { geometry in
            Group {
                if compact {
                    previewContent
                } else {
                    splitView
                        .inspector(isPresented: $showingInspector) {
                            inspector.inspectorColumnWidth(min: 280, ideal: 310, max: 360)
                        }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
        }
        .navigationTitle("Camera Live")
        // Leave room for the controls in narrow windows. Otherwise
        // AppKit competes with the title for space and overflows the action.
        .toolbar(removing: windowSize.width < 600 ? .title : nil)
        .toolbar { windowToolbar }
        // The native glass controls provide their own backgrounds. Keep
        // the full-width toolbar backdrop out of the video surface.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: compact) {
            // An open column must not pin the window at its old size.
            showingInspector = false
            compactPanel = nil
        }
        .onChange(of: narrow) {
            // Close a popover before its toolbar anchor or tabs change.
            compactPanel = nil
            if !narrow, inspectorPage == .cameras { inspectorPage = .stream }
        }
        .onChange(of: controller.selectedDevice?.id) {
            if compactPanel == .cameras || (compactPanel == .inspector && inspectorPage == .cameras) {
                compactPanel = nil
            }
        }
    }

    @ToolbarContentBuilder private var windowToolbar: some ToolbarContent {
        if compact && !narrow {
            ToolbarItem(id: "cameras", placement: .navigation) {
                Button { compactPanel = .cameras } label: { Label("Cameras", systemImage: "sidebar.left") }
                    .help("Choose a camera")
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .popover(isPresented: presenting(.cameras), arrowEdge: .bottom) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Cameras").font(.headline)
                                Spacer()
                                Button { compactPanel = nil } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.borderless).accessibilityLabel("Close cameras")
                            }.padding(16)
                            Divider()
                            cameraSidebar
                        }.frame(width: 300, height: 320)
                    }
            }
        }
        ToolbarItem(id: "stream-details", placement: .automatic) {
            Button { toggleInspector() } label: {
                Label(narrow ? "Camera and Stream Controls" : "Stream Details",
                      systemImage: narrow ? "slider.horizontal.3" : "sidebar.right")
            }
                .help(narrow ? "Camera and stream controls (⇧⌘I)" : "Stream details (⇧⌘I)")
                .accessibilityValue(showingInspector || compactPanel == .inspector ? "Shown" : "Hidden")
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .popover(isPresented: presenting(.inspector), arrowEdge: .bottom) {
                    inspector.frame(width: 360, height: 480)
                }
        }
        ToolbarItem(id: "virtual-camera", placement: .primaryAction) {
            VirtualCameraToolbarButton(controller: virtualCamera, iconOnly: windowSize.width < 600)
        }
        // The compact control draws its own standard button bezel. Avoid a
        // second, animated glass surface around it in the native toolbar.
        .sharedBackgroundVisibility(windowSize.width < 600 ? .hidden : .automatic)
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columns) {
            cameraSidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            previewContent
                .navigationTitle("Camera Live")
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var previewContent: some View {
        VStack(spacing: 0) {
            if compact && hasNotices {
                ScrollView { notices }
                    .frame(height: min(100, windowSize.height * 0.4))
            } else {
                notices
            }
            preview.frame(minWidth: 0, minHeight: 0)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    private var cameraSidebar: some View {
        List(selection: selectedID) {
            Section("Cameras") {
                ForEach(controller.devices) { camera in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(camera.displayName)
                            Text(camera.id == controller.selectedDevice?.id ? controller.state.title : "USB · Connected")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    } icon: { Image(systemName: "camera") }
                    .tag(camera.id)
                    .accessibilityElement(children: .combine)
                }
                if controller.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect your camera").font(.headline)
                        Text("Connect your camera by USB and turn it on.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            }
            Section {
                Button { controller.refresh() } label: { Label("Refresh Cameras", systemImage: "arrow.clockwise") }
                    .help("Look for connected USB cameras (⌘R)")
                if let error = controller.discoveryError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Cameras")
    }

    @ViewBuilder private var notices: some View {
        if case let .failed(message) = controller.state {
            CameraNotice(title: "Couldn’t start the camera", message: message, symbol: "exclamationmark.triangle") {
                Button("Try Again") { controller.retry() }
            }
        }
        if virtualCamera.state.needsAttention {
            CameraNotice(title: virtualCamera.state.title, message: virtualCamera.message,
                         symbol: virtualCamera.state == .waitingForExtension ? "info.circle" : "exclamationmark.triangle") {
                if virtualCamera.state == .needsApproval {
                    Button("Open System Settings") { virtualCamera.openSystemSettings() }
                } else {
                    Button("Setup Guide") { virtualCamera.openSetupGuide() }
                }
            }
        }
    }

    private var preview: some View {
        ZStack {
            Color.black
            if let frames = controller.preview, controller.statistics != nil {
                LivePreview(frames: frames, framing: virtualCamera.framing)
                    .id(ObjectIdentifier(frames))
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .accessibilityLabel("Live camera preview")
                    .accessibilityValue("\(virtualCamera.framing.canvas.title), framed for the virtual camera")
            } else {
                ViewThatFits(in: .vertical) {
                    emptyPreview
                    compactEmptyPreview
                    // Notices can leave very little height in a miniature
                    // window; keep setup and retry actions reachable.
                    ScrollView {
                        compactEmptyPreview.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var emptyPreview: some View {
        VStack(spacing: 14) {
            if controller.state == .starting || controller.state == .stopping {
                ProgressView().controlSize(.large).tint(.white)
            } else {
                Image(systemName: emptySymbol).font(.system(size: 40, weight: .light))
                    .accessibilityHidden(true)
            }
            Text(emptyTitle).font(.title2.weight(.medium))
            Text(emptyMessage).font(.callout).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            emptyPreviewAction
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 380)
        .environment(\.colorScheme, .dark)
    }

    private var compactEmptyPreview: some View {
        VStack(spacing: 8) {
            if controller.state == .starting || controller.state == .stopping {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: emptySymbol).font(.system(size: 24, weight: .light))
                    .accessibilityHidden(true)
            }
            Text(emptyTitle).font(.headline).multilineTextAlignment(.center)
            emptyPreviewAction
        }
        .foregroundStyle(.white).padding(12)
        .help(emptyMessage)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var emptyPreviewAction: some View {
        if case .failed = controller.state {
            Button("Try Again") { controller.retry() }.buttonStyle(.borderedProminent)
        } else if controller.state == .idle {
            if controller.devices.count == 1, let camera = controller.devices.first {
                Button("Start Camera") { controller.select(camera) }.buttonStyle(.borderedProminent)
            } else if !controller.devices.isEmpty {
                Button("Choose Camera") { chooseCamera() }.buttonStyle(.borderedProminent)
            } else {
                Button("Refresh Cameras") { controller.refresh() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func chooseCamera() {
        if narrow { inspectorPage = .cameras; compactPanel = .inspector }
        else if compact { compactPanel = .cameras }
        else { columns = .all }
    }

    private var emptySymbol: String {
        switch controller.state {
        case .waitingForCamera: return "cable.connector"
        case .suspended: return "moon"
        case .failed: return "exclamationmark.triangle"
        default: return "camera.viewfinder"
        }
    }
    private var emptyTitle: String {
        switch controller.state {
        case .starting: return "Opening live view…"
        case .stopping: return "Stopping camera…"
        case .waitingForCamera: return "Camera disconnected"
        case .suspended: return "Camera paused"
        case .failed: return "Camera unavailable"
        default: return controller.devices.isEmpty ? "Connect your camera" : "Start your camera"
        }
    }
    private var emptyMessage: String {
        switch controller.state {
        case .waitingForCamera: return "Reconnect your USB camera and turn it on. Your preview will resume automatically."
        case .suspended: return "The preview will resume when your Mac wakes."
        case .failed: return "Check the USB connection and close other apps using your camera, then try again."
        case .starting, .stopping: return "\(controller.selectedDevice?.displayName ?? "Your camera") will be ready shortly."
        default: return "Your live preview appears here. Connect a USB camera and select it to get started."
        }
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $inspectorPage) {
                ForEach(inspectorPages, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(16)
            Divider()
            switch inspectorPage {
            case .framing:
                VideoFramingControls(controller: virtualCamera)
            case .stream:
                streamDetails
            case .cameras:
                cameraSidebar
            }
        }
    }

    private var streamDetails: some View {
        Form {
            Section("Camera") {
                LabeledContent("Name", value: controller.selectedDevice?.displayName ?? "None selected")
                LabeledContent("Status", value: controller.state.title)
                if let stats = controller.statistics {
                    LabeledContent("Live view", value: "\(stats.width) × \(stats.height)")
                    LabeledContent("Capture rate", value: String(format: "%.1f fps", stats.framesPerSecond))
                }
                if let selected = controller.selectedDevice {
                    LabeledContent("Connection", value: selected.port)
                    Button("Stop Camera") { controller.select(nil) }
                } else if controller.devices.count == 1, let camera = controller.devices.first {
                    Button("Start Camera") { controller.select(camera) }
                } else {
                    Button("Choose Camera") { chooseCamera() }
                }
            }
            Section {
                LabeledContent("Name", value: "Camera Live")
                LabeledContent("Canvas", value: virtualCamera.framing.canvas.title)
                LabeledContent("Delivery", value: "30 fps")
                OutputStatus(state: virtualCamera.state)
            } header: { Text("Virtual camera") } footer: {
                Text("In Zoom’s video settings, choose Camera Live.")
            }
            Section {
                LabeledContent("Status", value: controller.statistics.map { $0.hasClients ? "Connected" : "Available" } ?? "Stopped")
            } header: { Text("Syphon") }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
    }

    private func toggleInspector() {
        if compact {
            if compactPanel == .inspector { compactPanel = nil }
            else { inspectorPage = .stream; compactPanel = .inspector }
        } else if showingInspector { showingInspector = false }
        else { inspectorPage = .stream; showingInspector = true }
    }
}

// Keep the toolbar control independent of the camera's frequent statistics
// updates. Constrain the icon label before AppKit measures the button so its
// hidden title cannot change the compact toolbar's layout.
private struct VirtualCameraToolbarButton: View {
    @ObservedObject var controller: VirtualCameraController
    let iconOnly: Bool

    private var title: String {
        controller.enabled ? "Stop Virtual Camera" : controller.installed ? "Start Virtual Camera" : "Enable Virtual Camera"
    }

    @ViewBuilder private var label: some View {
        if iconOnly {
            Label(title, systemImage: controller.enabled ? "video.slash" : "video")
                .labelStyle(.iconOnly)
                .frame(width: 20, height: 20)
        } else {
            Label(title, systemImage: controller.enabled ? "video.slash" : "video")
                .labelStyle(.titleAndIcon)
                .fixedSize()
        }
    }

    var body: some View {
        Group {
            if iconOnly {
                // Keep one button and one style for both Start and Stop. A
                // stable bezel avoids glass morphing over the moving preview.
                Button {
                    if controller.enabled { controller.stop() }
                    else { controller.start() }
                } label: { label }
                    .buttonStyle(.bordered)
                    .tint(controller.enabled ? Color.secondary : Color.accentColor)
                    .disabled(!controller.enabled && controller.busy)
                    .frame(width: 56, height: 40)
                    .help(controller.enabled
                          ? "Stop sending video to Zoom and other video apps (⇧⌘V)"
                          : "Make Camera Live available in Zoom and other video apps (⇧⌘V)")
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
            } else if controller.enabled {
                Button { controller.stop() } label: { label }
                    .help("Stop sending video to Zoom and other video apps (⇧⌘V)")
            } else {
                Button { controller.start() } label: { label }
                    .buttonStyle(.glassProminent)
                    .disabled(controller.busy)
                    .help("Make Camera Live available in Zoom and other video apps (⇧⌘V)")
            }
        }
        .fixedSize()
        .accessibilityLabel(title)
        .keyboardShortcut("v", modifiers: [.command, .shift])
    }
}

private struct OutputStatus: View {
    let state: VirtualCameraState
    private var symbol: String {
        switch state {
        case .broadcasting: return "checkmark.circle.fill"
        case .waitingForCamera: return "pause.circle"
        case .enabling, .removing, .waitingForExtension: return "clock"
        case .needsApproval, .needsRestart, .failed: return "exclamationmark.triangle"
        default: return "video.slash"
        }
    }
    var body: some View {
        Label {
            Text(state.title).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(state == .broadcasting ? Color.green : Color.secondary)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .help(state.message)
    }
}

private struct CameraNotice<Action: View>: View {
    let title: String
    let message: String
    let symbol: String
    @ViewBuilder let action: () -> Action
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                action().controlSize(.small)
            }.padding(14)
            Divider()
        }.background(.bar)
    }
}

private struct LivePreview: NSViewRepresentable {
    let frames: PreviewFrames
    let framing: VideoFraming
    func makeNSView(context: Context) -> NSView {
        do {
            let view = try CameraPreviewView(frames: frames)
            view.framing = framing
            return view
        } catch {
            let label = NSTextField(labelWithString: "Preview unavailable: \(error.localizedDescription)")
            label.textColor = .white
            return label
        }
    }
    func updateNSView(_ view: NSView, context: Context) { (view as? CameraPreviewView)?.framing = framing }
    static func dismantleNSView(_ view: NSView, coordinator: ()) { (view as? CameraPreviewView)?.stopDisplaying() }
}
