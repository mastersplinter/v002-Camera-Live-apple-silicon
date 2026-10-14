import Foundation

public struct CameraDevice: Identifiable, Equatable, Codable, Sendable {
    public let model: String
    public let port: String
    public var id: String { model + "@" + port }
    public var displayName: String { model.replacingOccurrences(of: "Canon:", with: "Canon ") }
    public init(model: String, port: String) { self.model = model; self.port = port }

    /// USB addresses may change on reconnect. Fall back only when the model is unique.
    public func matching(in devices: [CameraDevice]) -> CameraDevice? {
        if let exact = devices.first(where: { $0.id == id }) { return exact }
        let candidates = devices.filter { $0.model == model }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

public enum CameraLiveError: LocalizedError, Equatable {
    case camera(operation: String, code: Int32, detail: String)
    case invalidImage
    case imageTooLarge
    case metalUnavailable
    case syphonUnavailable
    case graphics(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .camera(operation, code, detail):
            let advice = code == -53 || code == -60 || code == -110
                ? " Quit EOS Utility, Photos, Image Capture and other camera apps, then reconnect the USB cable." : ""
            return "\(operation): \(detail) (\(code)).\(advice)"
        case .invalidImage: return "The camera returned an incomplete or invalid JPEG frame."
        case .imageTooLarge: return "The live-view image exceeds the supported 8192-pixel / 32-megapixel limit."
        case .metalUnavailable: return "A Metal-capable GPU is required."
        case .syphonUnavailable: return "The Syphon Metal server could not start."
        case let .graphics(detail): return "Video processing failed: \(detail)"
        case .cancelled: return "Capture was cancelled."
        }
    }
}

public enum CaptureEvent {
    case jpeg(Data)
    case failed(Error)
}

/// Implementations serialize camera operations. stop completes after the USB session closes.
public protocol CameraSource: AnyObject {
    func start(_ receive: @escaping (CaptureEvent) -> Void)
    func stop(completion: @escaping () -> Void)
}

public struct StreamStatistics: Sendable {
    public let width: Int
    public let height: Int
    public let publishedFrames: Int
    public let droppedFrames: Int
    public let framesPerSecond: Double
    public let hasClients: Bool
}
