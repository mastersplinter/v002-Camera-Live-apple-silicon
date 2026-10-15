import CoreImage
import CoreVideo
import Metal

/// A separate, bounded pool is essential: Syphon's texture is reused immediately,
/// whereas the camera service may still hold a submitted frame across processes.
public final class VideoFrameRenderer {
    public let canvas: VideoCanvas
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var pool: CVPixelBufferPool!
    public init(canvas: VideoCanvas = .hd720, softwareRendering: Bool = false) throws {
        self.canvas = canvas
        if !softwareRendering, let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else { context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false]) }
        let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: canvas.width, kCVPixelBufferHeightKey: canvas.height,
            kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true]
        let status = CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey: 2] as CFDictionary,
                                            attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess else { throw VirtualCameraError.operation("Create virtual-camera buffers", status) }
    }
    public func render(_ image: CGImage, framing: VideoFraming = VideoFraming()) throws -> CVPixelBuffer {
        try render(CIImage(cgImage: image), framing: framing)
    }
    /// The extension uses this only when a consumer requests a different output
    /// resolution from the producer. Already-cropped 16:9 pixels remain intact.
    public func resize(_ buffer: CVPixelBuffer) throws -> CVPixelBuffer {
        try render(CIImage(cvPixelBuffer: buffer), framing: VideoFraming(canvas: canvas))
    }
    private func render(_ image: CIImage, framing: VideoFraming) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool,
            [kCVPixelBufferPoolAllocationThresholdKey: 6] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw VirtualCameraError.operation("Allocate virtual-camera frame", status) }
        let bounds = CGRect(origin: .zero, size: canvas.size)
        let transform = framing.transform(source: image.extent.size, destination: bounds)
        let cropped = image.transformed(by: transform).cropped(to: bounds)
        context.render(cropped, to: buffer, bounds: bounds, colorSpace: colorSpace)
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        return buffer
    }
}
