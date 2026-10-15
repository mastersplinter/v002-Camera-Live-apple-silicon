import AVFoundation
import CameraLiveCore
import CameraLiveVirtualCamera
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import VirtualCameraShared

private func pixels(_ buffer: CVPixelBuffer) -> (top: [UInt8], bottom: [UInt8], margin: [UInt8]) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { fail("Missing video pixels.") }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
        Array(UnsafeBufferPointer(start: base + y * stride + x * 4, count: 4))
    }
    return (pixel(width / 2, height / 4), pixel(width / 2, height * 3 / 4), pixel(5, height / 4))
}
private func isPattern(_ buffer: CVPixelBuffer) -> Bool {
    guard VirtualCameraFormat.accepts(buffer) else { return false }
    let p = pixels(buffer)
    return p.top[2] > 180 && p.top[0] < 60 && p.bottom[0] > 180 && p.bottom[2] < 60 && p.margin[2] > 180 && p.margin[0] < 60
}
private func isStandby(_ buffer: CVPixelBuffer) -> Bool {
    guard VirtualCameraFormat.accepts(buffer) else { return false }
    let p = pixels(buffer)
    return p.top.prefix(3).allSatisfy { $0 < 60 } && p.bottom.prefix(3).allSatisfy { $0 < 60 }
}

func verifyVirtualFrames() throws {
    for software in [false, true] {
      for canvas in VideoCanvas.allCases {
        let renderer = try VirtualCameraRenderer(canvas: canvas, softwareRendering: software)
        for (width, height) in [(640, 480), (1056, 704)] {
            let decoded = try JPEGDecoder.decode(pattern(width: width, height: height))
            let frame = try renderer.render(decoded.image)
            guard isPattern(frame), CVPixelBufferGetWidth(frame) == canvas.width, CVPixelBufferGetHeight(frame) == canvas.height else {
                fail("Virtual camera orientation/fill failed (\(canvas.title), software=\(software)): \(pixels(frame)).")
            }
            // Retain this image while rendering the next one, as CMIO does.
            let black = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(
                CIImage(color: .black), from: CGRect(x: 0, y: 0, width: 32, height: 32))!
            let next = try renderer.render(black)
            guard isPattern(frame), isStandby(next), frame !== next else { fail("In-flight virtual camera buffer was overwritten.") }
        }
      }
    }
    let standby = try VirtualCameraFormat.placeholder()
    guard isStandby(standby) else { fail("Invalid virtual camera standby frame.") }
    if let pathIndex = CommandLine.arguments.firstIndex(of: "--standby-image"), CommandLine.arguments.count > pathIndex + 1 {
        let url = URL(fileURLWithPath: CommandLine.arguments[pathIndex + 1])
        let image = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(CIImage(cvPixelBuffer: standby), from: CGRect(x: 0, y: 0, width: 1280, height: 720))!
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("Cannot save standby image.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fail("Cannot write standby image.") }
    }
    print("PASS: 720p/1080p virtual camera GPU and CPU pixels, upright orientation, borderless fill, immutable in-flight buffers and standby frame.")
}

private final class VirtualCameraReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let canvas: VideoCanvas
    init(canvas: VideoCanvas) { self.canvas = canvas; super.init() }
    let timings = FrameTimings()
    let liveCount = Locked(0), standbyCount = Locked(0), invalidCount = Locked(0)
    let expectingStandby = Locked(false)
    private var lastTime = CMTime.invalid
    private var reportedInvalidFrame = false
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastTime.isValid, CMTimeCompare(time, lastTime) <= 0 {
            print("Non-monotonic frame timestamp: \(time), previous \(lastTime)")
            invalidCount.set(invalidCount.read() + 1)
        }
        lastTime = time
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer), VirtualCameraFormat.accepts(image),
              CVPixelBufferGetWidth(image) == canvas.width, CVPixelBufferGetHeight(image) == canvas.height else {
            if !reportedInvalidFrame, let image = CMSampleBufferGetImageBuffer(sampleBuffer) {
                print("Unexpected received format: \(CVPixelBufferGetWidth(image))x\(CVPixelBufferGetHeight(image)), expected \(canvas.title), pixel format \(CVPixelBufferGetPixelFormatType(image))")
                reportedInvalidFrame = true
            }
            invalidCount.set(invalidCount.read() + 1); return
        }
        if isPattern(image) { liveCount.set(liveCount.read() + 1); timings.record() }
        else if isStandby(image), expectingStandby.read() { standbyCount.set(standbyCount.read() + 1) }
        else if !isStandby(image) {
            if !reportedInvalidFrame { print("Unexpected received pixels: \(pixels(image))"); reportedInvalidFrame = true }
            invalidCount.set(invalidCount.read() + 1)
        }
    }
}

func verifyInstalledVirtualCamera() throws {
    func requestedCanvas(_ option: String, fallback: VideoCanvas) -> VideoCanvas {
        guard let index = CommandLine.arguments.firstIndex(of: option) else { return fallback }
        guard CommandLine.arguments.count > index + 1 else { fail("\(option) requires 720p or 1080p.") }
        switch CommandLine.arguments[index + 1] {
        case "720p": return .hd720
        case "1080p": return .hd1080
        default: fail("\(option) requires 720p or 1080p.")
        }
    }
    let canvas = requestedCanvas("--canvas", fallback: .hd720)
    let receiveCanvas = requestedCanvas("--receive-canvas", fallback: canvas)
    // This check intentionally fails if signing/activation has not happened.
    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.externalUnknown], mediaType: .video, position: .unspecified).devices
    guard let device = devices.first(where: { $0.uniqueID.caseInsensitiveCompare(VirtualCameraFormat.deviceID.uuidString) == .orderedSame }) else {
        fail("Camera Live is not installed as a system camera. Complete signing and activation first.")
    }
    if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
        let permitted = Locked<Bool?>(nil)
        AVCaptureDevice.requestAccess(for: .video) { permitted.set($0) }
        runLoop(until: Date().addingTimeInterval(60)) { permitted.read() != nil }
    }
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { fail("Allow camera access for the diagnostic in System Settings.") }
    let broadcasting = Locked(false)
    let frames = PreviewFrames(), publisher = VirtualCameraPublisher { status in
        if status == .broadcasting { broadcasting.set(true) }
        if case let .failed(message) = status { print("Virtual camera publisher: \(message)") }
    }
    let receiver = VirtualCameraReceiver(canvas: receiveCanvas), capture = AVCaptureSession(), output = AVCaptureVideoDataOutput()
    let input = try AVCaptureDeviceInput(device: device)
    // On macOS a session preset alone does not constrain video-data output
    // dimensions, particularly while another app is also using the device.
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: receiveCanvas.width, kCVPixelBufferHeightKey as String: receiveCanvas.height]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(receiver, queue: DispatchQueue(label: "info.v002.CameraLive.diagnostic-receiver"))
    guard capture.canAddInput(input), capture.canAddOutput(output) else { fail("Cannot configure Camera Live capture.") }
    capture.addInput(input); capture.addOutput(output)
    let preset: AVCaptureSession.Preset = receiveCanvas == .hd1080 ? .hd1920x1080 : .hd1280x720
    guard capture.canSetSessionPreset(preset) else { fail("The installed extension does not support \(receiveCanvas.title).") }
    capture.sessionPreset = preset
    let image = try JPEGDecoder.decode(pattern(width: 1056, height: 704)).image
    frames.submit(image)
    publisher.setFraming(VideoFraming(canvas: canvas))
    publisher.setFrames(frames); publisher.setEnabled(true)
    let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in frames.submit(image) }
    defer { timer.invalidate(); publisher.shutdown(); capture.stopRunning() }
    runLoop(until: Date().addingTimeInterval(5)) { broadcasting.read() }
    guard broadcasting.read() else { fail("Publisher did not connect. Stop the app's virtual camera before running this diagnostic.") }
    guard let format = device.formats.first(where: {
        let size = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
        return size.width == receiveCanvas.width && size.height == receiveCanvas.height
    }) else { fail("The installed extension does not advertise \(receiveCanvas.title). Update the extension first.") }
    try device.lockForConfiguration()
    device.activeFormat = format
    device.unlockForConfiguration()
    capture.startRunning()
    runLoop(until: Date().addingTimeInterval(10)) { receiver.liveCount.read() >= 180 || receiver.invalidCount.read() > 0 }
    guard receiver.liveCount.read() >= 180, receiver.invalidCount.read() == 0 else {
        fail("Installed virtual camera failed: \(receiver.liveCount.read()) valid frames, \(receiver.invalidCount.read()) invalid frames.")
    }
    timer.invalidate(); frames.close()
    let stopped = Locked(false)
    publisher.shutdown { stopped.set(true) }
    runLoop(until: Date().addingTimeInterval(2)) { stopped.read() }
    receiver.expectingStandby.set(true)
    runLoop(until: Date().addingTimeInterval(3)) { receiver.standbyCount.read() >= 30 }
    guard stopped.read(), receiver.standbyCount.read() >= 30 else { fail("Stopped publisher did not produce a continuing standby feed.") }
    print("PASS: installed Camera Live extension \(canvas.title) → AVFoundation \(receiveCanvas.title): \(receiver.liveCount.read()) correctly oriented, borderless frames; \(receiver.standbyCount.read()) standby frames after stop.")
    print(receiver.timings.summary("Virtual camera received"))
}
