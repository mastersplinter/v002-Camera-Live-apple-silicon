import CoreImage
import MetalKit
import VirtualCameraShared

/// Display-synchronised preview, independent of SwiftUI's status updates. The
/// same decoded image is reused; no second JPEG decode or main-thread USB work.
public final class CameraPreviewView: MTKView, MTKViewDelegate {
    public let frames: PreviewFrames
    /// Nil retains the uncropped preview used by the capture diagnostics.
    public var framing: VideoFraming?
    /// Optional presentation timing for the desktop performance diagnostic.
    public var didPresent: ((CFTimeInterval) -> Void)?
    /// Optional diagnostic hook to inspect the actual drawable before presentation.
    public var inspectDrawable: ((MTLTexture, MTLCommandBuffer) -> Void)?
    public private(set) var submittedFrames = 0
    private let commands: MTLCommandQueue
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let inFlight = DispatchSemaphore(value: 2)
    private var lastSequence: UInt64 = 0
    private var lastSize = CGSize.zero
    private var lastFraming: VideoFraming?

    public init(frames: PreviewFrames) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw CameraLiveError.metalUnavailable
        }
        self.frames = frames
        self.commands = queue
        self.context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        preferredFramesPerSecond = NSScreen.main?.maximumFramesPerSecond ?? 60
        enableSetNeedsDisplay = false
        isPaused = false
        delegate = self
        setAccessibilityLabel("Camera live view")
    }

    required init(coder: NSCoder) { fatalError("Use init(frames:)") }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        // Use the current monitor's cadence, including ProMotion, and adapt
        // when the window moves between displays. Unchanged frames need no GPU work.
        let refreshRate = window?.screen?.maximumFramesPerSecond ?? 60
        if preferredFramesPerSecond != refreshRate { preferredFramesPerSecond = refreshRate }
        guard let frame = frames.snapshot(), drawableSize.width > 0, drawableSize.height > 0,
              frame.sequence != lastSequence || drawableSize != lastSize || framing != lastFraming,
              inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = currentDrawable, let buffer = commands.makeCommandBuffer() else {
            inFlight.signal(); return
        }
        let size = drawableSize
        let width = CGFloat(frame.image.width), height = CGFloat(frame.image.height)
        let scale = min(size.width / width, size.height / height)
        // Core Image handles the drawable's display orientation. An additional
        // negative Y scale here would invert the preview. Fit in Core Image
        // coordinates, with black letterboxing around mismatched aspect ratios.
        let transform = CGAffineTransform(translationX: (size.width - width * scale) / 2,
                                           y: (size.height - height * scale) / 2)
            .scaledBy(x: scale, y: scale)
        let bounds = CGRect(origin: .zero, size: size)
        let source = CIImage(cgImage: frame.image)
        let presented: CIImage
        if let framing {
            let canvasScale = min(size.width / framing.canvas.size.width, size.height / framing.canvas.size.height)
            let canvasSize = CGSize(width: framing.canvas.size.width * canvasScale, height: framing.canvas.size.height * canvasScale)
            let canvas = CGRect(x: (size.width - canvasSize.width) / 2, y: (size.height - canvasSize.height) / 2,
                                width: canvasSize.width, height: canvasSize.height)
            presented = source.transformed(by: framing.transform(source: source.extent.size, destination: canvas)).cropped(to: canvas)
        } else { presented = source.transformed(by: transform) }
        let image = presented
            .composited(over: CIImage(color: .black).cropped(to: bounds))
        context.render(image, to: drawable.texture, commandBuffer: buffer, bounds: bounds, colorSpace: colorSpace)
        inspectDrawable?(drawable.texture, buffer)
        if let didPresent {
            drawable.addPresentedHandler { didPresent($0.presentedTime) }
        }
        let semaphore = inFlight
        buffer.addCompletedHandler { _ in semaphore.signal() }
        buffer.present(drawable)
        buffer.commit()
        submittedFrames += 1
        lastSequence = frame.sequence
        lastSize = size
        lastFraming = framing
    }
}
