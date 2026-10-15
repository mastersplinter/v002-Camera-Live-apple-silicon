import Testing
import Foundation
import CoreMedia
import CoreVideo
import CameraLiveCore
import VirtualCameraShared
@testable import CameraLiveVirtualCamera

private func virtualTestBuffer(width: Int = VirtualCameraFormat.width) throws -> CVPixelBuffer {
    var result: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, width, VirtualCameraFormat.height, kCVPixelFormatType_32BGRA,
                                    [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result)
    #expect(status == kCVReturnSuccess)
    return try #require(result)
}

struct VirtualCameraFormatTests {
    @Test func advertisesStandard720pAndMonotonicHostTimeSamples() throws {
        let format = try VirtualCameraFormat.description()
        #expect(CMVideoFormatDescriptionGetDimensions(format).width == 1280)
        #expect(CMVideoFormatDescriptionGetDimensions(format).height == 720)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCVPixelFormatType_32BGRA)
        let buffer = try virtualTestBuffer()
        for tick: Int64 in 0..<3 {
            let time = CMTime(value: 30_000 + tick, timescale: 30)
            let sample = try VirtualCameraFormat.sample(buffer, at: time)
            #expect(CMSampleBufferGetPresentationTimeStamp(sample) == time)
            #expect(CMSampleBufferGetDuration(sample) == VirtualCameraFormat.frameDuration)
            #expect(CMSampleBufferDataIsReady(sample))
        }
    }
    @Test func rejectsUnsupportedDimensionsAndInvalidTimestamps() throws {
        let wrong = try virtualTestBuffer(width: 640)
        #expect(!VirtualCameraFormat.accepts(wrong))
        #expect(throws: (any Error).self) { try VirtualCameraFormat.sample(wrong, at: .zero) }
        let valid = try virtualTestBuffer()
        #expect(throws: (any Error).self) { try VirtualCameraFormat.sample(valid, at: .invalid) }
    }
    @Test func staleOrStoppedSourceCannotLeavePrivateFrameFrozen() throws {
        let relay = VirtualCameraFrameRelay()
        let first = try virtualTestBuffer(), second = try virtualTestBuffer()
        #expect(relay.receive(first, at: 10))
        #expect(relay.frame(at: 10.2) === first)
        #expect(relay.receive(second, at: 10.3))
        #expect(relay.frame(at: 10.4) === second)
        #expect(relay.frame(at: 10.81) == nil)
        #expect(relay.frame(at: 11) == nil)
        relay.receive(first, at: 12)
        relay.clear()
        #expect(relay.frame(at: 12.1) == nil)
    }
    @Test func invalidFrameCannotDisplaceGoodFrame() throws {
        let relay = VirtualCameraFrameRelay()
        let valid = try virtualTestBuffer()
        relay.receive(valid, at: 10)
        #expect(!relay.receive(try virtualTestBuffer(width: 16), at: 10.1))
        #expect(relay.frame(at: 10.2) === valid)
    }
    @Test func standbyHasTheAdvertisedFormat() throws {
        let buffer = try VirtualCameraFormat.placeholder()
        #expect(VirtualCameraFormat.accepts(buffer))
        #expect(CVPixelBufferGetIOSurface(buffer) != nil)
    }
}

private final class FakeVirtualTransport: VirtualCameraTransport {
    private let lock = NSLock()
    private var active = false
    private var sent = 0
    private var starts = 0
    private var width = 0
    private var lastBuffer: CVPixelBuffer?
    func start(canvas: VideoCanvas) throws { lock.lock(); active = true; starts += 1; lock.unlock() }
    func enqueue(_ sample: CMSampleBuffer) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard active else { return false }
        lastBuffer = CMSampleBufferGetImageBuffer(sample)
        width = lastBuffer.map(CVPixelBufferGetWidth) ?? 0
        sent += 1; return true
    }
    func stop() { lock.lock(); active = false; lock.unlock() }
    var snapshot: (active: Bool, sent: Int) { lock.lock(); defer { lock.unlock() }; return (active, sent) }
    var output: (starts: Int, width: Int, buffer: CVPixelBuffer?) {
        lock.lock(); defer { lock.unlock() }; return (starts, width, lastBuffer)
    }
}

struct VirtualCameraPublisherTests {
    private func waitFor(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return predicate()
    }
    @Test func staleInputStopsSendingAndFreshInputResumes() async throws {
        let transport = FakeVirtualTransport(), frames = PreviewFrames()
        let publisher = VirtualCameraPublisher(transport: transport, report: { _ in })
        let image = try JPEGDecoder.decode(makeJPEG(width: 32, height: 24)).image
        frames.submit(image)
        publisher.setFrames(frames); publisher.setEnabled(true)
        #expect(await waitFor { transport.snapshot.sent > 0 })
        #expect(await waitFor { !transport.snapshot.active })
        let sentBeforeResume = transport.snapshot.sent
        frames.submit(image)
        #expect(await waitFor { transport.snapshot.sent > sentBeforeResume })
        frames.close()
        #expect(await waitFor { !transport.snapshot.active })
        await withCheckedContinuation { continuation in publisher.shutdown { continuation.resume() } }
        let sentAfterStop = transport.snapshot.sent
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(transport.snapshot.sent == sentAfterStop)
    }
    @Test func enableWithoutCameraDoesNotStartSending() async {
        let transport = FakeVirtualTransport()
        let publisher = VirtualCameraPublisher(transport: transport, report: { _ in })
        publisher.setEnabled(true)
        try? await Task.sleep(nanoseconds: 100_000_000)
        await withCheckedContinuation { continuation in publisher.shutdown { continuation.resume() } }
        #expect(!transport.snapshot.active)
        #expect(transport.snapshot.sent == 0)
    }
    @Test func framingChangesRefreshHeldImageAndCanvasChangesRestartTransport() async throws {
        let transport = FakeVirtualTransport(), frames = PreviewFrames()
        let publisher = VirtualCameraPublisher(transport: transport, report: { _ in })
        let image = try JPEGDecoder.decode(makeJPEG(width: 32, height: 24)).image
        frames.submit(image)
        publisher.setFrames(frames); publisher.setEnabled(true)
        defer { publisher.shutdown() }
        #expect(await waitFor { transport.output.width == 1280 })
        let first = try #require(transport.output.buffer)
        let starts = transport.output.starts
        publisher.setFraming(VideoFraming(zoom: 2, vertical: 0))
        #expect(await waitFor { transport.output.buffer !== first })
        #expect(transport.output.starts == starts)
        frames.submit(image)
        publisher.setFraming(VideoFraming(canvas: .hd1080, zoom: 2, vertical: 0))
        #expect(await waitFor { transport.output.width == 1920 })
        #expect(transport.output.starts == starts + 1)
        frames.submit(image)
        publisher.setFraming(VideoFraming())
        #expect(await waitFor { transport.output.width == 1280 })
        await withCheckedContinuation { continuation in publisher.shutdown { continuation.resume() } }
    }
}
