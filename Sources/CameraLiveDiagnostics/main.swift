import AppKit
import CameraLiveCore
import CameraLiveNative
import Foundation
import Metal
import UniformTypeIdentifiers

final class Locked<Value> {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func read() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: Value) { lock.lock(); defer { lock.unlock() }; self.value = value }
}
func runLoop(until deadline: Date, interval: TimeInterval = 0.02, condition: () -> Bool) {
    while Date() < deadline && !condition() {
        let next = Date().addingTimeInterval(interval)
        if let app = NSApp {
            if let event = app.nextEvent(matching: .any, until: next, inMode: .default, dequeue: true) {
                app.sendEvent(event)
            }
            app.updateWindows()
        } else { RunLoop.current.run(until: next) }
    }
}
final class FrameTimings {
    private let lock = NSLock()
    private var times: [TimeInterval] = []
    var count: Int { lock.lock(); defer { lock.unlock() }; return times.count }
    func record(_ time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard time > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        times.append(time)
    }
    func summary(_ label: String) -> String {
        lock.lock(); let all = times.sorted(); lock.unlock()
        // Exclude the first two seconds of camera/GPU startup from cadence data.
        let samples = all.filter { $0 >= (all.first ?? 0) + 2 }
        guard samples.count > 1, let first = samples.first, let last = samples.last else {
            return "\(label): \(all.count) frames; too few for steady-state timing"
        }
        let gaps = zip(samples.dropFirst(), samples).map { ($0 - $1) * 1000 }.sorted()
        func percentile(_ fraction: Double) -> Double { gaps[min(gaps.count - 1, Int(Double(gaps.count - 1) * fraction))] }
        return String(format: "%@: %d frames; steady %.2f fps; gaps median %.2f / p95 %.2f / p99 %.2f / max %.2f ms; gaps >100 ms: %d",
                      label, all.count, Double(samples.count - 1) / (last - first), percentile(0.5), percentile(0.95),
                      percentile(0.99), gaps.last!, gaps.filter { $0 > 100 }.count)
    }
}
func previewWindow(frames: PreviewFrames, timings: FrameTimings, checkPattern: Bool = false) throws -> NSWindow {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let view = try CameraPreviewView(frames: frames)
    view.didPresent = { timings.record($0) }
    if checkPattern { view.inspectDrawable = verifyPreviewOrientation }
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 960, height: 640),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Camera Live — frame pacing test"
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    app.finishLaunching()
    app.activate(ignoringOtherApps: true)
    return window
}
func verifyPreviewOrientation(_ texture: MTLTexture, commands: MTLCommandBuffer) {
    guard let bytes = texture.device.makeBuffer(length: 512, options: .storageModeShared),
          let copy = commands.makeBlitCommandEncoder() else { fail("Cannot inspect preview orientation.") }
    // Sample the actual drawable, inside the fitted image for both test aspect
    // ratios. This catches destination-specific flips that a Syphon-only test misses.
    for (index, y) in [texture.height / 4, texture.height * 3 / 4].enumerated() {
        copy.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: texture.width / 2, y: y, z: 0),
                  sourceSize: MTLSize(width: 1, height: 1, depth: 1), to: bytes,
                  destinationOffset: index * 256, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
    }
    copy.endEncoding()
    commands.addCompletedHandler { commands in
        if let error = commands.error { fail(error.localizedDescription) }
        let pixel = bytes.contents().assumingMemoryBound(to: UInt8.self)
        guard pixel[2] > 180, pixel[0] < 60, pixel[256] > 180, pixel[258] < 60 else {
            fail("Preview orientation failed: upper BGRA=\(Array(UnsafeBufferPointer(start: pixel, count: 4))), lower=\(Array(UnsafeBufferPointer(start: pixel+256, count: 4))). Expected red above blue.")
        }
    }
}
func verifyPreview(_ window: NSWindow?, timings: FrameTimings, delivered: FrameTimings) {
    guard let window, let view = window.contentView as? CameraPreviewView else { return }
    print("Preview GPU submissions: \(view.submittedFrames)")
    print(timings.summary("On-screen presentation"))
    guard timings.count > delivered.count * 8 / 10 else {
        fail("Preview did not present at least 80% of delivered frames (\(timings.count)/\(delivered.count)). Keep its window visible during this test.")
    }
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}
func pattern(width: Int, height: Int) -> Data {
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            rgba[i] = y < height / 2 ? 255 : 0
            rgba[i+1] = UInt8(x * 255 / (width - 1))
            rgba[i+2] = y < height / 2 ? 0 : 255
        }
    }
    let provider = CGDataProvider(data: Data(rgba) as CFData)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fail("JPEG generation failed.") }
    return data as Data
}
func verifyPattern(_ texture: MTLTexture, device: MTLDevice) {
    let stride = (texture.width * 4 + 255) & ~255
    guard let queue = device.makeCommandQueue(), let commands = queue.makeCommandBuffer(),
          let bytes = device.makeBuffer(length: stride * texture.height, options: .storageModeShared),
          let copy = commands.makeBlitCommandEncoder() else { fail("Cannot read received Metal texture.") }
    copy.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
              sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: bytes,
              destinationOffset: 0, destinationBytesPerRow: stride, destinationBytesPerImage: stride * texture.height)
    copy.endEncoding(); commands.commit(); commands.waitUntilCompleted()
    if let error = commands.error { fail(error.localizedDescription) }
    let pixel = bytes.contents().assumingMemoryBound(to: UInt8.self)
    let top = 10 * stride + 10 * 4
    let bottom = (texture.height - 11) * stride + 10 * 4
    guard pixel[top+2] > 180, pixel[top] < 60, pixel[bottom] > 180, pixel[bottom+2] < 60 else {
        fail("Orientation/colour check failed: top BGRA=\(Array(UnsafeBufferPointer(start: pixel+top, count: 4))), bottom=\(Array(UnsafeBufferPointer(start: pixel+bottom, count: 4))).")
    }
}
let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "--help"
if mode == "--list" {
    let result = Locked<Result<[CameraDevice], Error>?>(nil)
    CameraCatalog.shared.discover { result.set($0) }
    runLoop(until: Date().addingTimeInterval(30)) { result.read() != nil }
    guard let result = result.read() else { fail("Camera discovery timed out.") }
    switch result {
    case let .success(devices):
        if devices.isEmpty { print("No supported USB cameras detected.") }
        for camera in devices { print("\(camera.displayName)\t\(camera.port)") }
    case let .failure(error): fail(error.localizedDescription)
    }
} else if mode == "--receive" {
    guard args.count >= 2, let device = MTLCreateSystemDefaultDevice() else { fail("Supply a server name; a Metal GPU is required.") }
    let name = args[1]
    let checkPattern = args.contains("--verify-pattern")
    var receiver: CLSyphonReceiver?
    var received = 0
    var sizes = Set<String>()
    let measured = args.contains("--measure")
    let timings = FrameTimings()
    runLoop(until: Date().addingTimeInterval(20), interval: measured ? 0.002 : 0.02) {
        if receiver == nil { receiver = CLSyphonReceiver(serverName: name, device: device) }
        if let receiver, receiver.hasNewFrame, let texture = receiver.newFrame() {
            received += 1
            timings.record()
            sizes.insert("\(texture.width)x\(texture.height)")
            if checkPattern { verifyPattern(texture, device: device) }
        }
        return !measured && received >= 10 && (!checkPattern || sizes.count >= 2)
    }
    receiver?.stop()
    guard received >= 10, !checkPattern || sizes.count >= 2 else { fail("Syphon receive failed: \(received) frames, sizes \(sizes).") }
    print("PASS: received \(received) Metal frames (\(sizes.sorted().joined(separator: ", "))) from \(name)\(checkPattern ? "; orientation and colour verified" : "").")
    if measured { print(timings.summary("Syphon received")) }
} else if mode == "--test-pattern" {
    let name = args.count > 1 ? args[1] : "Camera Live Test"
    let images = [pattern(width: 640, height: 480), pattern(width: 1056, height: 704)]
    let published = Locked(0)
    let failure = Locked<Error?>(nil)
    do {
        let frames = PreviewFrames(), delivered = FrameTimings(), presented = FrameTimings()
        let window = try args.contains("--preview") ? previewWindow(frames: frames, timings: presented, checkPattern: true) : nil
        defer { window?.close() }
        let pipeline = try MetalFramePipeline(name: name, preview: { frames.submit($0); delivered.record() },
            report: { stats in published.set(stats.publishedFrames) }, failure: { failure.set($0) })
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { _ in
            let index = Int((ProcessInfo.processInfo.systemUptime - start) / 2) % 2
            pipeline.submit(jpeg: images[index])
        }
        runLoop(until: Date().addingTimeInterval(25)) { failure.read() != nil }
        timer.invalidate()
        let stopped = Locked(false)
        pipeline.stop { stopped.set(true) }
        runLoop(until: Date().addingTimeInterval(5)) { stopped.read() }
        if let error = failure.read() { fail(error.localizedDescription) }
        guard published.read() > 0, stopped.read() else { fail("No frames published or shutdown failed.") }
        print("PASS: published \(published.read()) test-pattern frames via Metal/Syphon.")
        print(delivered.summary("Published/preview-ready"))
        verifyPreview(window, timings: presented, delivered: delivered)
    } catch { fail(error.localizedDescription) }
} else if mode == "--capture" {
    let discovery = Locked<Result<[CameraDevice], Error>?>(nil)
    CameraCatalog.shared.discover { discovery.set($0) }
    runLoop(until: Date().addingTimeInterval(30)) { discovery.read() != nil }
    guard let result = discovery.read() else { fail("Camera discovery timed out.") }
    let devices: [CameraDevice]
    do { devices = try result.get() } catch { fail(error.localizedDescription) }
    let port = args.dropFirst().first { $0.hasPrefix("usb:") }
    guard let camera = devices.first(where: { port == nil || $0.port == port }) else { fail("No matching camera. Use --list first.") }
    let count = Locked(0)
    let failure = Locked<Error?>(nil)
    let source = CameraCatalog.shared.source(for: camera)
    do {
        let frames = PreviewFrames(), captured = FrameTimings(), delivered = FrameTimings(), presented = FrameTimings()
        let dropped = Locked(0)
        let window = try args.contains("--preview") ? previewWindow(frames: frames, timings: presented) : nil
        defer { window?.close() }
        let pipeline = try MetalFramePipeline(name: camera.displayName, preview: { frames.submit($0); delivered.record() },
            report: { stats in count.set(stats.publishedFrames); dropped.set(stats.droppedFrames) }, failure: { failure.set($0) })
        source.start { event in
            switch event {
            case let .jpeg(data): captured.record(); pipeline.submit(jpeg: data)
            case let .failed(error): failure.set(error)
            }
        }
        runLoop(until: Date().addingTimeInterval(20)) { failure.read() != nil }
        let group = DispatchGroup()
        group.enter(); source.stop { group.leave() }
        group.enter(); pipeline.stop { group.leave() }
        guard group.wait(timeout: .now() + 15) == .success else { fail("Camera shutdown timed out.") }
        if let error = failure.read() { fail(error.localizedDescription) }
        guard count.read() >= 10 else { fail("Only \(count.read()) frames received from the camera.") }
        print("PASS: \(count.read()) live-view frames from \(camera.displayName).")
        print(captured.summary("Camera acquisition"))
        print(delivered.summary("Published/preview-ready"))
        print("Decoder/publisher dropped frames: \(dropped.read())")
        verifyPreview(window, timings: presented, delivered: delivered)
    } catch { fail(error.localizedDescription) }
} else {
    print("""
    Camera Live native diagnostics
      --list                             Discover USB PTP cameras
      --capture [usb:PORT] [--preview]      Publish a real camera and report frame timing
      --test-pattern [name] [--preview]    Publish two test resolutions for 25 seconds
      --receive SERVER [--verify-pattern]  Receive and optionally validate Syphon frames
      --receive SERVER --measure           Measure received frame timing for 20 seconds
    """)
}
