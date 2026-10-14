import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CameraLiveCore

struct MailboxTests {
    @Test
    func testOverloadKeepsOnlyNewestFrame() {
        let box = LatestFrameMailbox<Int>()
        #expect(box.offer(1))
        #expect(!(box.offer(2)))
        #expect(!(box.offer(3)))
        #expect(box.droppedCount == 2)
        #expect(box.take() == 3)
        #expect(box.take() == nil)
        #expect(box.offer(4))
        #expect(box.take() == 4)
    }
    @Test
    func testStopDiscardsPendingFramesAndRejectsLateCallbacks() {
        let box = LatestFrameMailbox<Int>()
        #expect(box.offer(1))
        box.close()
        #expect(!(box.offer(2)))
        #expect(box.take() == nil)
    }
    @Test
    func testConcurrentProducersStayBounded() {
        let box = LatestFrameMailbox<Int>()
        DispatchQueue.concurrentPerform(iterations: 1000) { _ = box.offer($0) }
        #expect(box.take() != nil)
        #expect(box.take() == nil)
        #expect(box.droppedCount == 999)
    }
}

struct CameraIdentityTests {
    @Test
    func testReconnectAfterUSBAddressChanges() {
        let old = CameraDevice(model: "Canon:EOS 550D", port: "usb:001,002")
        let new = CameraDevice(model: old.model, port: "usb:001,003")
        #expect(old.matching(in: [new]) == new)
    }
    @Test
    func testDoesNotGuessBetweenIdenticalCameras() {
        let old = CameraDevice(model: "Canon:EOS 550D", port: "usb:001,002")
        let one = CameraDevice(model: old.model, port: "usb:001,003")
        let two = CameraDevice(model: old.model, port: "usb:001,004")
        #expect(old.matching(in: [one, two]) == nil)
        #expect(old.matching(in: [old, two]) == old)
    }
}

func makeJPEG(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}

struct JPEGDecoderTests {
    @Test
    func testValidJPEGAndResolutionChanges() throws {
        let first = try JPEGDecoder.decode(makeJPEG(width: 1056, height: 704))
        #expect(first.width == 1056); #expect(first.height == 704)
        let second = try JPEGDecoder.decode(makeJPEG(width: 640, height: 480))
        #expect(second.width == 640); #expect(second.height == 480)
    }
    @Test
    func testRejectsEmptyGarbageAndTruncatedJPEG() {
        for data in [Data(), Data([0xff, 0xd8, 0, 0]), Data("not a frame".utf8), makeJPEG(width: 16, height: 16).prefix(30)] {
            #expect(throws: (any Error).self) { try JPEGDecoder.decode(data) }
        }
    }
    @Test
    func testRejectsExcessiveDimensionsBeforeDecodingPixels() {
        #expect(throws: CameraLiveError.imageTooLarge) { try JPEGDecoder.decode(makeJPEG(width: 8193, height: 1)) }
    }
}

struct PreviewFrameTests {
    @Test
    func testDisplayAlwaysSamplesNewestFrameWithoutAnImageQueue() throws {
        let frames = PreviewFrames()
        let first = try JPEGDecoder.decode(makeJPEG(width: 32, height: 24)).image
        let last = try JPEGDecoder.decode(makeJPEG(width: 64, height: 48)).image
        for _ in 0..<100 { frames.submit(first) }
        frames.submit(last)
        #expect(frames.snapshot()?.sequence == 101)
        #expect(frames.snapshot()?.image === last)
        // Repeated display ticks can retain the current image without redrawing.
        #expect(frames.snapshot()?.sequence == 101)
    }

    @Test
    func testClosingPreviewRejectsLateFramesFromOldSession() throws {
        let frames = PreviewFrames()
        let image = try JPEGDecoder.decode(makeJPEG(width: 32, height: 24)).image
        frames.submit(image)
        frames.close()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in frames.submit(image) }
        #expect(frames.snapshot() == nil)
    }
}

private final class FakeSource: CameraSource {
    var callback: ((CaptureEvent) -> Void)?
    var stopCallback: (() -> Void)?
    var started = false
    func start(_ receive: @escaping (CaptureEvent) -> Void) { started = true; callback = receive }
    func stop(completion: @escaping () -> Void) { stopCallback = completion }
    func finishStop() { let completion = stopCallback; stopCallback = nil; completion?() }
}
private final class FakePipeline: FramePublishing {
    var stopped = false
    var count = 0
    func submit(jpeg: Data) { if !stopped { count += 1 } }
    func stop(completion: @escaping () -> Void) { stopped = true; completion() }
}

@MainActor
struct ControllerTests {
    private let camera = CameraDevice(model: "Canon:EOS 550D", port: "usb:001,001")
    private func settle() async { try? await Task.sleep(nanoseconds: 30_000_000) }

    @Test
    func testPreviewRunsAtFrameRateWithoutWaitingForStatistics() async throws {
        let source = FakeSource()
        var previewCallback: ((CGImage) -> Void)?
        let controller = CameraController(defaults: nil, sourceFactory: { _ in source }, pipelineFactory: { _, preview, _, _ in
            previewCallback = preview
            return FakePipeline()
        })
        controller.updateDevices([camera]); controller.select(camera)
        let store = try #require(controller.preview)
        let image = try JPEGDecoder.decode(makeJPEG(width: 32, height: 24)).image
        for _ in 0..<60 { previewCallback?(image) }
        #expect(store.snapshot()?.sequence == 60)
        #expect(controller.statistics == nil)
        controller.shutdown()
        previewCallback?(image)
        #expect(store.snapshot() == nil)
        source.finishStop(); await settle()
    }

    @Test
    func testAutomaticDiscoveryDoesNotInterruptLiveViewAndResumesWhenIdle() async {
        let source = FakeSource()
        var discoveries = 0
        let controller = CameraController(defaults: nil, sourceFactory: { _ in source },
            pipelineFactory: { _, _, _, _ in FakePipeline() }, discovery: { completion in
                discoveries += 1; completion(.success([camera]))
            })
        controller.updateDevices([camera]); controller.select(camera)
        controller.refresh(automatically: true)
        #expect(discoveries == 0)
        controller.shutdown()
        controller.refresh(automatically: true)
        #expect(discoveries == 0)
        source.finishStop(); await settle()
        controller.refresh(automatically: true); await settle()
        #expect(discoveries == 1)
    }

    @Test
    func testSwitchWaitsForOldUSBSessionAndIgnoresStaleError() async {
        let first = FakeSource(); let second = FakeSource()
        let other = CameraDevice(model: "Canon:EOS R", port: "usb:001,002")
        let controller = CameraController(defaults: nil, sourceFactory: { $0 == self.camera ? first : second },
                                           pipelineFactory: { _, _, _, _ in FakePipeline() })
        controller.updateDevices([camera, other])
        controller.select(camera)
        #expect(first.started)
        controller.select(other)
        #expect(!(second.started))
        #expect(controller.state == .stopping)
        first.callback?(.failed(CameraLiveError.invalidImage))
        first.finishStop()
        await settle()
        #expect(second.started)
        #expect(controller.state == .starting)
        controller.shutdown(); second.finishStop(); await settle()
        #expect(controller.state == .idle)
    }

    @Test
    func testRapidSelectionChangesStartOnlyLatestChoice() async {
        var sources: [FakeSource] = []
        let other = CameraDevice(model: "Canon:EOS R", port: "usb:001,002")
        let controller = CameraController(defaults: nil, sourceFactory: { _ in
            let source = FakeSource(); sources.append(source); return source
        }, pipelineFactory: { _, _, _, _ in FakePipeline() })
        controller.updateDevices([camera, other]); controller.select(camera)
        controller.select(other); controller.select(camera); controller.select(nil)
        #expect(sources.count == 1)
        sources[0].finishStop(); await settle()
        #expect(sources.count == 1)
        #expect(controller.state == .idle)
    }

    @Test
    func testSleepAndWakeNeverOverlapSessions() async {
        var sources: [FakeSource] = []
        let controller = CameraController(defaults: nil, sourceFactory: { _ in
            let source = FakeSource(); sources.append(source); return source
        }, pipelineFactory: { _, _, _, _ in FakePipeline() })
        controller.updateDevices([camera]); controller.select(camera)
        controller.setSleeping(true); controller.setSleeping(false)
        #expect(sources.count == 1)
        sources[0].finishStop(); await settle()
        #expect(sources.count == 2)
        controller.shutdown(); sources[1].finishStop(); await settle()
    }

    @Test
    func testDisconnectReconnectAndStopWhileDisconnected() async {
        var sources: [FakeSource] = []
        let controller = CameraController(defaults: nil, sourceFactory: { _ in
            let source = FakeSource(); sources.append(source); return source
        }, pipelineFactory: { _, _, _, _ in FakePipeline() })
        controller.updateDevices([camera]); controller.select(camera)
        controller.updateDevices([]); sources[0].finishStop(); await settle()
        #expect(controller.state == .waitingForCamera)
        let reconnected = CameraDevice(model: camera.model, port: "usb:001,009")
        controller.updateDevices([reconnected])
        #expect(sources.count == 2)
        #expect(controller.selectedDevice == reconnected)
        controller.updateDevices([]); controller.select(nil)
        sources[1].finishStop(); await settle()
        controller.updateDevices([reconnected])
        #expect(sources.count == 2)
        #expect(controller.state == .idle)
    }

    @Test
    func testFailureReleasesSessionAndRequiresRetry() async {
        var sources: [FakeSource] = []
        let controller = CameraController(defaults: nil, sourceFactory: { _ in
            let source = FakeSource(); sources.append(source); return source
        }, pipelineFactory: { _, _, _, _ in FakePipeline() })
        controller.updateDevices([camera]); controller.select(camera)
        sources[0].callback?(.failed(CameraLiveError.invalidImage)); await settle()
        sources[0].finishStop(); await settle()
        #expect(controller.state == .failed(CameraLiveError.invalidImage.localizedDescription))
        controller.updateDevices([camera]); #expect(sources.count == 1)
        controller.retry(); #expect(sources.count == 2)
        controller.shutdown(); sources[1].finishStop(); await settle()
    }

    @Test
    func testShutdownCompletionWaitsForCameraClose() async {
        let source = FakeSource()
        let controller = CameraController(defaults: nil, sourceFactory: { _ in source }, pipelineFactory: { _, _, _, _ in FakePipeline() })
        controller.updateDevices([camera]); controller.select(camera)
        var stopped = false
        controller.shutdown { stopped = true }
        #expect(!(stopped))
        source.finishStop(); await settle()
        #expect(stopped)
    }
}
