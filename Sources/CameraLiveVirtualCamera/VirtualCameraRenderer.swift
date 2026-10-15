import CoreImage
import CoreVideo
import Metal
import VirtualCameraShared

/// A separate, bounded pool is essential: Syphon's texture is reused immediately,
/// whereas the camera service may still hold a submitted frame across processes.
public final class VirtualCameraRenderer {
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var pool: CVPixelBufferPool!
    public init(softwareRendering: Bool = false) throws {
        if !softwareRendering, let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else { context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false]) }
        let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: VirtualCameraFormat.width, kCVPixelBufferHeightKey: VirtualCameraFormat.height,
            kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true]
        let status = CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey: 2] as CFDictionary,
                                            attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess else { throw VirtualCameraError.operation("Create virtual-camera buffers", status) }
    }
    public func render(_ image: CGImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool,
            [kCVPixelBufferPoolAllocationThresholdKey: 6] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw VirtualCameraError.operation("Allocate virtual-camera frame", status) }
        let width = CGFloat(VirtualCameraFormat.width), height = CGFloat(VirtualCameraFormat.height)
        let scale = min(width / CGFloat(image.width), height / CGFloat(image.height))
        let transform = CGAffineTransform(translationX: (width - CGFloat(image.width) * scale) / 2,
            y: (height - CGFloat(image.height) * scale) / 2).scaledBy(x: scale, y: scale)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let fitted = CIImage(cgImage: image).transformed(by: transform)
            .composited(over: CIImage(color: .black).cropped(to: bounds))
        context.render(fitted, to: buffer, bounds: bounds, colorSpace: colorSpace)
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        return buffer
    }
}
