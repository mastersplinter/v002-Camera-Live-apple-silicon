import AppKit
import CameraLiveCore
import MetalKit
import VirtualCameraShared

/// Observe the real MTKView delegate, including calls that submit no GPU work.
private final class PreviewDrawObserver: NSObject, MTKViewDelegate {
    weak var preview: CameraPreviewView?
    var calls = 0
    init(_ preview: CameraPreviewView) { self.preview = preview }
    func draw(in view: MTKView) { calls += 1; preview?.draw(in: view) }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        preview?.mtkView(view, drawableSizeWillChange: size)
    }
}

func verifyPreviewLifecycle() throws {
    let frames = PreviewFrames(), presented = FrameTimings(), rendered = FrameTimings()
    let window = try previewWindow(frames: frames, timings: presented, checkPattern: true)
    defer { window.close() }
    guard let view = window.contentView as? CameraPreviewView else { fail("Missing native preview") }
    let observer = PreviewDrawObserver(view)
    view.delegate = observer
    // Require both completed pixels and real presentation on an unlocked display.
    view.inspectDrawable = { texture, commands in
        verifyPreviewOrientation(texture, commands: commands)
        commands.addCompletedHandler { _ in rendered.record() }
    }
    let image = try JPEGDecoder.decode(pattern(width: 1056, height: 704)).image

    func waitForRender(after count: (rendered: Int, presented: Int), _ phase: String) {
        runLoop(until: Date().addingTimeInterval(3)) { rendered.count > count.rendered && presented.count > count.presented }
        guard rendered.count > count.rendered, presented.count > count.presented else {
            fail("Preview did not render and present after \(phase): draws=\(observer.calls), submissions=\(view.submittedFrames), presentations=\(presented.count), attached=\(view.window != nil), visible=\(window.occlusionState.contains(.visible)), size=\(view.drawableSize)")
        }
    }
    func settle(_ seconds: TimeInterval) {
        runLoop(until: Date().addingTimeInterval(seconds)) { false }
    }

    runLoop(until: Date().addingTimeInterval(3)) { window.occlusionState.contains(.visible) }
    guard window.occlusionState.contains(.visible) else {
        fail("Preview lifecycle check requires an unlocked display with its test window visible")
    }
    frames.submit(image)
    waitForRender(after: (0, 0), "initial frame")
    settle(0.3)
    let idleDraws = observer.calls
    settle(1)
    guard observer.calls == idleDraws else { fail("Held preview is still polling: \(observer.calls - idleDraws) draws/second") }

    var count = (rendered.count, presented.count)
    view.framing = VideoFraming(canvas: .hd720, zoom: 1.2)
    waitForRender(after: count, "crop change on a held frame")
    count = (rendered.count, presented.count)
    window.setContentSize(CGSize(width: 240, height: 135))
    waitForRender(after: count, "resize to minimum")

    window.orderOut(nil)
    settle(0.3)
    guard !window.occlusionState.contains(.visible) else { fail("Diagnostic window did not become hidden") }
    let hiddenDraws = observer.calls
    for _ in 0..<1000 { frames.submit(image) }
    settle(6) // Exercise restoration after hidden-preview rendering caches expire.
    guard observer.calls == hiddenDraws else { fail("Hidden preview still renders incoming frames") }
    count = (rendered.count, presented.count)
    window.makeKeyAndOrderFront(nil)
    waitForRender(after: count, "restoring a hidden window")

    window.contentView = nil
    settle(0.2)
    let detachedDraws = observer.calls
    frames.submit(image)
    settle(0.2)
    guard observer.calls == detachedDraws else { fail("Detached preview still draws") }
    count = (rendered.count, presented.count)
    window.contentView = view
    waitForRender(after: count, "reattaching the preview")

    settle(0.2)
    view.stopDisplaying()
    let stoppedDraws = observer.calls
    frames.submit(image)
    settle(0.2)
    guard observer.calls == stoppedDraws else { fail("Dismantled preview still draws") }
    withExtendedLifetime(observer) {}
    print("PASS: preview idle (zero draw callbacks), held-frame cropping/resizing, hidden/detached suppression, restoration and teardown; drawable colours/orientation and on-screen presentation verified.")
}
