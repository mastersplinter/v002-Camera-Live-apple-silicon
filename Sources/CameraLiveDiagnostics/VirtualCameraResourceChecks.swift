import AVFoundation
import CameraLiveCore
import CameraLiveVirtualCamera
import Foundation
import VirtualCameraShared

/// Real CMIO sender/receiver exercise with marked phases for external profiling.
/// The same decoded test image is submitted at 30 Hz; USB/JPEG decode and the UI
/// are excluded by default to isolate sender scheduling and retained buffers.
/// --syphon-source also exercises JPEG decoding and concurrent Syphon consumers.
func profileVirtualCameraResources() throws {
    func argument(_ name: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }
    let canvasName = argument("--canvas") ?? "720p"
    guard ["720p", "1080p"].contains(canvasName) else { fail("Canvas must be 720p or 1080p") }
    let canvas: VideoCanvas = canvasName == "1080p" ? .hd1080 : .hd720
    let seconds = Double(argument("--stream-seconds") ?? "20") ?? 0
    guard seconds >= 5, seconds <= 3600 else { fail("Stream duration must be 5–3600 seconds") }
    let receive = CommandLine.arguments.contains("--receive-output")
    let frames = PreviewFrames(), status = Locked(VirtualCameraOutputStatus.stopped)
    let publisher = VirtualCameraPublisher { status.set($0) }
    let image = try JPEGDecoder.decode(pattern(width: 1056, height: 704)).image
    let pipelineError = Locked<Error?>(nil)
    let syphonName = argument("--syphon-source")
    let jpegs = syphonName == nil ? [] : [pattern(width: 640, height: 480), pattern(width: 1056, height: 704)]
    let pipeline = try syphonName.map { name in
        try MetalFramePipeline(name: name, preview: { frames.submit($0) },
            report: { _ in }, failure: { pipelineError.set($0) })
    }
    let receiver = VirtualCameraReceiver(canvas: canvas)
    var capture: AVCaptureSession?
    var feeder: Timer?
    // A sparse main-loop source keeps Foundation running during idle phases,
    // without the 50 Hz polling used by short correctness diagnostics.
    let heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }
    defer { feeder?.invalidate(); heartbeat.invalidate(); publisher.shutdown(); capture?.stopRunning(); pipeline?.stop() }

    @discardableResult func phase(_ name: String, duration: TimeInterval) -> TimeInterval {
        let start = ProcessInfo.processInfo.systemUptime
        let marker: [String: Any] = ["phase": name, "uptime_seconds": start]
        let line = try! JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
        FileHandle.standardOutput.write(line + Data([10]))
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
        return start
    }
    func startFeeding() {
        let start = ProcessInfo.processInfo.systemUptime
        let submit = {
            if let pipeline {
                let index = Int((ProcessInfo.processInfo.systemUptime - start) / 2) % jpegs.count
                pipeline.submit(jpeg: jpegs[index])
            } else { frames.submit(image) }
        }
        submit()
        feeder = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in submit() }
    }
    func checkLive(since count: Int, startedAt: TimeInterval) {
        if let error = pipelineError.read() { fail(error.localizedDescription) }
        guard status.read() == .broadcasting else { fail("Sender did not broadcast: \(status.read())") }
        if receive {
            let received = receiver.liveCount.read() - count
            guard received >= Int(seconds * 30 * 0.9), receiver.invalidCount.read() == 0 else {
                fail("Resource test lost output: \(received) live frames, \(receiver.invalidCount.read()) invalid")
            }
            print("Live phase: \(received) valid \(canvas.title) frames")
            print(receiver.timings.summary("Virtual camera received", since: startedAt))
        }
    }

    publisher.setFraming(VideoFraming(canvas: canvas))
    publisher.setFrames(frames)
    publisher.setEnabled(true)
    phase("waiting", duration: 8)
    guard status.read() == .waitingForCamera else { fail("Sender did not enter its waiting state") }

    if receive {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            fail("Allow camera access using --virtual-camera-test before profiling")
        }
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
        guard let device = devices.first(where: { $0.uniqueID.caseInsensitiveCompare(VirtualCameraFormat.deviceID.uuidString) == .orderedSame }) else {
            fail("The Camera Live extension is unavailable")
        }
        let session = AVCaptureSession(), output = AVCaptureVideoDataOutput()
        let input = try AVCaptureDeviceInput(device: device)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                               kCVPixelBufferWidthKey as String: canvas.width, kCVPixelBufferHeightKey as String: canvas.height]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(receiver, queue: DispatchQueue(label: "info.v002.CameraLive.resource-receiver"))
        guard session.canAddInput(input), session.canAddOutput(output) else { fail("Cannot configure resource-test receiver") }
        session.addInput(input); session.addOutput(output)
        let preset: AVCaptureSession.Preset = canvas == .hd1080 ? .hd1920x1080 : .hd1280x720
        guard session.canSetSessionPreset(preset) else { fail("Requested canvas is unavailable") }
        session.sessionPreset = preset
        receiver.expectingStandby.set(true)
        session.startRunning(); capture = session
    }

    var count = receiver.liveCount.read()
    startFeeding()
    let liveStart = phase("live", duration: seconds)
    checkLive(since: count, startedAt: liveStart)
    feeder?.invalidate(); feeder = nil
    let standbyBefore = receiver.standbyCount.read()
    phase("stale", duration: 8)
    guard status.read() == .waitingForCamera else { fail("Stale input did not disconnect the sender") }
    if receive, receiver.standbyCount.read() - standbyBefore < 150 { fail("Stale input did not produce standby output") }

    count = receiver.liveCount.read()
    startFeeding()
    let resumedAt = phase("resumed", duration: seconds)
    checkLive(since: count, startedAt: resumedAt)
    feeder?.invalidate(); feeder = nil
    publisher.setEnabled(false)
    phase("stopped", duration: 8)
    guard status.read() == .stopped else { fail("Sender did not stop") }
    let stopped = Locked(false)
    publisher.shutdown { stopped.set(true) }
    runLoop(until: Date().addingTimeInterval(3)) { stopped.read() }
    guard stopped.read() else { fail("Publisher shutdown timed out") }
    if let pipeline {
        let pipelineStopped = Locked(false)
        pipeline.stop { pipelineStopped.set(true) }
        runLoop(until: Date().addingTimeInterval(3)) { pipelineStopped.read() }
        guard pipelineStopped.read() else { fail("Source pipeline shutdown timed out") }
    }
    print("PASS: resource phases, stale-input recovery and stop; canvas=\(canvas.title), receiver=\(receive), Syphon source=\(syphonName != nil)")
}
