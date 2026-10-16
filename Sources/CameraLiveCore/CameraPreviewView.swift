import CoreImage
import MetalKit
import VirtualCameraShared

/// Display-synchronised preview, independent of SwiftUI's status updates. The
/// same decoded image is reused; no second JPEG decode or main-thread USB work.
public final class CameraPreviewView: MTKView, MTKViewDelegate {
    public let frames: PreviewFrames
    /// Nil retains the uncropped preview used by the capture diagnostics.
    public var framing: VideoFraming? {
        didSet { if framing != oldValue { requestDraw() } }
    }
    /// Optional presentation timing for the desktop performance diagnostic.
    public var didPresent: ((CFTimeInterval) -> Void)?
    /// Optional diagnostic hook to inspect the actual drawable before presentation.
    public var inspectDrawable: ((MTLTexture, MTLCommandBuffer) -> Void)?
    public private(set) var submittedFrames = 0
    private let commands: MTLCommandQueue
    private var context: CIContext?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let inFlight = DispatchSemaphore(value: 2)
    private var lastSequence: UInt64 = 0
    private var lastSize = CGSize.zero
    private var lastFraming: VideoFraming?
    private var observation: PreviewFrames.Observation?
    private var visibilityObserver: NSObjectProtocol?
    private var stopped = false
    private var deferredDraw = false
    private var drawRequested = false
    private var releaseResources: DispatchWorkItem?

    public init(frames: PreviewFrames) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw CameraLiveError.metalUnavailable
        }
        self.frames = frames
        self.commands = queue
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        // Only submit new content; Metal still presents on the display cadence.
        // Avoid both display-link polling and invalidating the surrounding UI.
        enableSetNeedsDisplay = false
        isPaused = true
        delegate = self
        setAccessibilityLabel("Camera live view")
    }

    required init(coder: NSCoder) { fatalError("Use init(frames:)") }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
        if let window {
            visibilityObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.updateObservation() }
        }
        updateObservation()
    }

    private func updateObservation() {
        releaseResources?.cancel(); releaseResources = nil
        guard !stopped, window?.occlusionState.contains(.visible) == true else {
            observation = nil
            if stopped || window == nil {
                context = nil
            } else if context != nil {
                // Keep quick hide/show transitions warm, but don't retain Core
                // Image's caches throughout a meeting with the preview hidden.
                let release = DispatchWorkItem { [weak self] in
                    guard let self, self.window?.occlusionState.contains(.visible) != true else { return }
                    self.context = nil
                    self.releaseResources = nil
                }
                releaseResources = release
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: release)
            }
            return
        }
        if observation == nil {
            lastSize = .zero // Redraw after reattachment, even for a held frame.
            observation = frames.observe { [weak self] in self?.requestDraw() }
        }
        requestDraw()
    }

    private func requestDraw() {
        guard !stopped, !drawRequested else { return }
        drawRequested = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.drawRequested = false
            guard !self.stopped, self.window?.occlusionState.contains(.visible) == true else { return }
            // Bound temporary images/drawables to each explicit draw instead
            // of the surrounding app run-loop iteration.
            autoreleasepool { self.draw() }
        }
    }

    public func stopDisplaying() {
        stopped = true
        observation = nil
        releaseResources?.cancel(); releaseResources = nil
        context = nil
        isPaused = true
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { requestDraw() }

    public func draw(in view: MTKView) {
        guard !stopped, let frame = frames.snapshot(), drawableSize.width > 0, drawableSize.height > 0,
              frame.sequence != lastSequence || drawableSize != lastSize || framing != lastFraming else { return }
        guard inFlight.wait(timeout: .now()) == .success else {
            // Retry a resize/crop of a held frame after GPU backpressure, even
            // if no further camera frame arrives. At most one retry is queued.
            if !deferredDraw {
                deferredDraw = true
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) { [weak self] in
                    guard let self else { return }
                    self.deferredDraw = false
                    self.requestDraw()
                }
            }
            return
        }
        guard let drawable = currentDrawable, let buffer = commands.makeCommandBuffer(), let device else {
            inFlight.signal(); return
        }
        if context == nil { context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
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
        context!.render(image, to: drawable.texture, commandBuffer: buffer, bounds: bounds, colorSpace: colorSpace)
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

    deinit {
        releaseResources?.cancel()
        observation?.cancel()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }
}
