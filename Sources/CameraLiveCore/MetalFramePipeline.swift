import Foundation
import CoreImage
import CoreVideo
import ImageIO
import Metal
import CameraLiveNative

public struct DecodedFrame {
    public let image: CGImage
    public var width: Int { image.width }
    public var height: Int { image.height }
}

public enum JPEGDecoder {
    public static func decode(_ data: Data) throws -> DecodedFrame {
        guard data.count >= 4, data.count <= 32 * 1024 * 1024,
              data.first == 0xff, data.dropFirst().first == 0xd8,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else {
            throw CameraLiveError.invalidImage
        }
        guard width <= 8192, height <= 8192, width * height <= 32_000_000 else { throw CameraLiveError.imageTooLarge }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw CameraLiveError.invalidImage
        }
        return DecodedFrame(image: image)
    }
}

/// ImageIO decodes JPEG; Core Image renders on Metal into an IOSurface-backed
/// pixel buffer. Syphon publishes that Metal texture. No Intel code or OpenGL
/// context is involved in the application's video path.
public final class MetalFramePipeline {
    public let device: MTLDevice
    private var commandQueue: MTLCommandQueue?
    private var context: CIContext?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let server: CLSyphonPublisher
    private let queue = DispatchQueue(label: "info.v002.CameraLive.video", qos: .userInitiated)
    private let mailbox = LatestFrameMailbox<Data>()
    private var textureCache: CVMetalTextureCache!
    private var pixelBuffer: CVPixelBuffer?
    private var metalImage: CVMetalTexture?
    private var texture: MTLTexture?
    private var frames = 0
    private var failures = 0
    private var recentFrames: [TimeInterval] = []
    private var lastReport = 0.0
    private let report: (StreamStatistics) -> Void
    private let preview: (CGImage) -> Void
    private let failure: (Error) -> Void

    public init(name: String, preview: @escaping (CGImage) -> Void = { _ in },
                report: @escaping (StreamStatistics) -> Void,
                failure: @escaping (Error) -> Void) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CameraLiveError.metalUnavailable
        }
        guard let server = CLSyphonPublisher(name: name, device: device) else { throw CameraLiveError.syphonUnavailable }
        self.device = device
        self.server = server
        self.report = report
        self.preview = preview
        self.failure = failure
    }

    public func submit(jpeg: Data) {
        if mailbox.offer(jpeg) { queue.async { self.drain() } }
    }

    private func drain() {
        while let data = mailbox.take() {
            autoreleasepool {
                do {
                    let decoded = try JPEGDecoder.decode(data)
                    try publish(decoded)
                    failures = 0
                } catch {
                    failures += 1
                    // A damaged USB frame should not interrupt a healthy stream.
                    if failures >= 5 { mailbox.close(); failure(error) }
                }
            }
        }
    }

    private func prepareTexture(width: Int, height: Int) throws -> MTLTexture {
        if let texture, texture.width == width, texture.height == height { return texture }
        texture = nil; metalImage = nil; pixelBuffer = nil
        if let textureCache { CVMetalTextureCacheFlush(textureCache, 0) }
        else if CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache) != kCVReturnSuccess {
            throw CameraLiveError.graphics("Could not create a Metal texture cache.")
        }
        let attributes: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true,
                                         kCVPixelBufferIOSurfacePropertiesKey: [:]]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer,
              CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer,
                [kCVMetalTextureUsage: MTLTextureUsage.shaderRead.rawValue | MTLTextureUsage.shaderWrite.rawValue | MTLTextureUsage.renderTarget.rawValue] as CFDictionary,
                .bgra8Unorm, width, height, 0, &metalImage) == kCVReturnSuccess,
              let metalImage, let created = CVMetalTextureGetTexture(metalImage) else {
            throw CameraLiveError.graphics("Could not allocate a shared video texture.")
        }
        texture = created
        return created
    }

    private func publish(_ decoded: DecodedFrame) throws {
        // Keep the server discoverable, but only render when a Syphon viewer
        // exists. Preview and virtual-camera consumers use the decoded image.
        let hasClients = server.hasClients
        if hasClients {
            if commandQueue == nil { commandQueue = device.makeCommandQueue() }
            guard let commandQueue else { throw CameraLiveError.graphics("No command queue.") }
            if context == nil { context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
            let texture = try prepareTexture(width: decoded.width, height: decoded.height)
            guard let commands = commandQueue.makeCommandBuffer() else { throw CameraLiveError.graphics("No command buffer.") }
            // Core Image's origin is bottom-left; Metal/Syphon use top-left texture rows.
            let image = CIImage(cgImage: decoded.image).transformed(by:
                CGAffineTransform(translationX: 0, y: CGFloat(decoded.height)).scaledBy(x: 1, y: -1))
            context!.render(image, to: texture, commandBuffer: commands,
                           bounds: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height), colorSpace: colorSpace)
            server.publishTexture(texture, commandBuffer: commands)
            commands.commit()
            // Exactly one GPU frame in flight; texture storage cannot be overwritten
            // before Syphon's copy completes. Camera acquisition remains independent.
            commands.waitUntilCompleted()
            if let error = commands.error { throw CameraLiveError.graphics(error.localizedDescription) }
        } else {
            releaseSyphonResources()
        }
        frames += 1
        let now = ProcessInfo.processInfo.systemUptime
        // Video must never share the status display's 5 Hz throttle.
        preview(decoded.image)
        recentFrames.append(now)
        recentFrames.removeAll { $0 < now - 2 }
        if frames == 1 || now - lastReport >= 0.2 {
            lastReport = now
            report(StreamStatistics(width: decoded.width, height: decoded.height, publishedFrames: frames,
                droppedFrames: mailbox.droppedCount,
                framesPerSecond: Double(recentFrames.count - 1) / max(0.001, now - (recentFrames.first ?? now)),
                hasClients: hasClients))
        }
    }

    private func releaseSyphonResources() {
        // Every submission waits for completion, so no GPU work still uses these.
        texture = nil; metalImage = nil; pixelBuffer = nil
        textureCache = nil; context = nil; commandQueue = nil
    }

    public func stop(completion: @escaping () -> Void = {}) {
        mailbox.close()
        queue.async {
            self.server.stop()
            self.releaseSyphonResources()
            completion()
        }
    }
}
