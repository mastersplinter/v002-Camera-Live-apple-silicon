import Foundation
import CoreMedia
import CoreVideo
import CoreGraphics
import CoreText

public enum VirtualCameraFormat {
    public static let name = "Camera Live"
    public static let appIdentifier = "info.v002.CameraLive.AppleSilicon"
    public static let extensionIdentifier = "info.v002.CameraLive.AppleSilicon.CameraExtension"
    public static let diagnosticsIdentifier = "info.v002.CameraLive.AppleSilicon.Diagnostics"
    public static let deviceID = UUID(uuidString: "A762DEAB-F634-4327-93E4-647D935AC833")!
    public static let sourceID = UUID(uuidString: "94281CE9-ED75-4E03-B2CE-293408860358")!
    public static let sinkID = UUID(uuidString: "8A40CFCA-D80B-45BE-9BAC-09293DD3DFF7")!
    public static let width = 1280
    public static let height = 720
    public static let framesPerSecond: Int32 = 30
    public static let frameDuration = CMTime(value: 1, timescale: framesPerSecond)
    public static let staleInterval: TimeInterval = 0.5
    public static let queueSize = 3

    public static func description(canvas: VideoCanvas = .hd720) throws -> CMVideoFormatDescription {
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA, width: Int32(canvas.width), height: Int32(canvas.height),
            extensions: nil, formatDescriptionOut: &description)
        guard status == noErr, let description else { throw VirtualCameraError.operation("Create video format", status) }
        return description
    }

    public static func accepts(_ buffer: CVPixelBuffer) -> Bool {
        VideoCanvas.allCases.contains { CVPixelBufferGetWidth(buffer) == $0.width && CVPixelBufferGetHeight(buffer) == $0.height } &&
        CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA
    }

    public static func sample(_ buffer: CVPixelBuffer, at time: CMTime) throws -> CMSampleBuffer {
        guard accepts(buffer), time.isNumeric else { throw VirtualCameraError.invalidFrame }
        var format: CMVideoFormatDescription?
        var result: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: frameDuration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: buffer, formatDescriptionOut: &format)
        guard formatStatus == noErr, let format else { throw VirtualCameraError.operation("Describe video frame", formatStatus) }
        let status = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &result)
        guard status == noErr, let result else { throw VirtualCameraError.operation("Create video frame", status) }
        return result
    }

    public static func placeholder(canvas: VideoCanvas = .hd720) throws -> CVPixelBuffer {
        let width = canvas.width, height = canvas.height
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true]
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw VirtualCameraError.operation("Create standby frame", status) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw VirtualCameraError.invalidFrame
        }
        context.setFillColor(CGColor(gray: 0.07, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / 1280
        context.scaleBy(x: scale, y: scale)
        // The bitmap's rows already match the CVPixelBuffer destination. An
        // additional Y flip here inverts the text delivered to camera clients.
        for (text, size, y) in [("Camera Live", 48.0, 380.0), ("Start your camera in Camera Live", 24.0, 320.0)] {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.85, alpha: 1)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: (1280 - lineWidth) / 2, y: y)
            CTLineDraw(line, context)
        }
        return buffer
    }
}

public enum VirtualCameraError: Error, LocalizedError {
    case notInstalled, invalidFrame, operation(String, OSStatus)
    public var errorDescription: String? {
        switch self {
        case .notInstalled: return "Enable the Camera Live virtual camera first."
        case .invalidFrame: return "The virtual camera received an unsupported video frame."
        case let .operation(name, status): return "\(name) failed (\(status))."
        }
    }
}

/// Queue-confined state shared with the extension's tests. A stalled or stopped
/// producer must reveal the standby image instead of freezing a private frame.
public final class VirtualCameraFrameRelay {
    private var latest: CVPixelBuffer?
    private var receivedAt: TimeInterval = -.infinity
    public init() {}
    @discardableResult public func receive(_ buffer: CVPixelBuffer, at time: TimeInterval) -> Bool {
        guard VirtualCameraFormat.accepts(buffer), time.isFinite else { return false }
        latest = buffer; receivedAt = time
        return true
    }
    public func frame(at time: TimeInterval) -> CVPixelBuffer? {
        guard time >= receivedAt, time - receivedAt < VirtualCameraFormat.staleInterval else { clear(); return nil }
        return latest
    }
    public func clear() { latest = nil; receivedAt = -.infinity }
}
