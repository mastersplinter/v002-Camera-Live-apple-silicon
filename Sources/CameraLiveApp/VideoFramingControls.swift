import SwiftUI
import CameraLiveVirtualCamera
import VirtualCameraShared

struct VideoFramingControls: View {
    @ObservedObject var controller: VirtualCameraController
    private var framing: VideoFraming { controller.framing }
    private var canvas: Binding<VideoCanvas> {
        Binding(get: { framing.canvas }, set: {
            controller.framing = VideoFraming(canvas: $0, zoom: framing.zoom, horizontal: framing.horizontal, vertical: framing.vertical)
        })
    }
    private var zoom: Binding<Double> {
        Binding(get: { framing.zoom }, set: {
            controller.framing = VideoFraming(canvas: framing.canvas, zoom: $0, horizontal: framing.horizontal, vertical: framing.vertical)
        })
    }
    private var horizontal: Binding<Double> {
        Binding(get: { framing.horizontal }, set: {
            controller.framing = VideoFraming(canvas: framing.canvas, zoom: framing.zoom, horizontal: $0, vertical: framing.vertical)
        })
    }
    private var vertical: Binding<Double> {
        Binding(get: { framing.vertical }, set: {
            controller.framing = VideoFraming(canvas: framing.canvas, zoom: framing.zoom, horizontal: framing.horizontal, vertical: $0)
        })
    }
    var body: some View {
        Form {
            Section {
                Picker("Resolution", selection: canvas) {
                    ForEach(VideoCanvas.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                LabeledContent("Aspect ratio", value: "16:9 · Fill")
            } header: { Text("Canvas") }
            Section("Crop") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Zoom")
                        Spacer()
                        Text(String(format: "%.2f×", framing.zoom)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: zoom, in: 1...4)
                        .accessibilityLabel("Crop zoom")
                        .accessibilityValue(String(format: "%.2f times", framing.zoom))
                }.padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Horizontal position")
                    Slider(value: horizontal, in: 0...1)
                        .accessibilityLabel("Horizontal crop position")
                        .accessibilityValue("\(Int(framing.horizontal * 100)) percent from left")
                    HStack { Text("Left"); Spacer(); Text("Right") }
                        .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }.padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vertical position")
                    Slider(value: vertical, in: 0...1)
                        .accessibilityLabel("Vertical crop position")
                        .accessibilityValue("\(Int(framing.vertical * 100)) percent from top")
                    HStack { Text("Top"); Spacer(); Text("Bottom") }
                        .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }.padding(.vertical, 4)
            }
            Section {
                Button("Reset Framing") { controller.framing = VideoFraming(canvas: framing.canvas) }
                    .help("Centre the crop and reset zoom, keeping the selected canvas")
            } footer: {
                Text("Changes save automatically and apply to the preview and virtual camera.")
            }
        }
        .formStyle(.grouped)
    }
}
