import Foundation
import CoreGraphics

public enum VideoCanvas: String, CaseIterable, Codable, Sendable {
    // Keep 720p first for existing camera clients and saved configurations.
    case hd720, hd1080
    public var width: Int { self == .hd720 ? 1280 : 1920 }
    public var height: Int { self == .hd720 ? 720 : 1080 }
    public var size: CGSize { CGSize(width: width, height: height) }
    public var title: String { "\(width) × \(height)" }
}

/// A fill crop in source pixels. Positions run left-to-right and top-to-bottom;
/// the crop rectangle uses Core Image's bottom-left origin. At 1× the largest
/// possible 16:9 region is kept. Panning never exposes pixels outside the source.
public struct VideoFraming: Equatable, Codable, Sendable {
    public let canvas: VideoCanvas
    public let zoom: Double
    public let horizontal: Double
    public let vertical: Double

    public init(canvas: VideoCanvas = .hd720, zoom: Double = 1,
                horizontal: Double = 0.5, vertical: Double = 0.5) {
        self.canvas = canvas
        self.zoom = Self.clamp(zoom, 1...4, fallback: 1)
        self.horizontal = Self.clamp(horizontal, 0...1, fallback: 0.5)
        self.vertical = Self.clamp(vertical, 0...1, fallback: 0.5)
    }
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
    private enum CodingKeys: CodingKey { case canvas, zoom, horizontal, vertical }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(canvas: try c.decode(VideoCanvas.self, forKey: .canvas),
                  zoom: try c.decode(Double.self, forKey: .zoom),
                  horizontal: try c.decode(Double.self, forKey: .horizontal),
                  vertical: try c.decode(Double.self, forKey: .vertical))
    }
    public func crop(in source: CGSize) -> CGRect {
        guard source.width.isFinite, source.height.isFinite, source.width > 0, source.height > 0 else { return .zero }
        let aspect = CGFloat(canvas.width) / CGFloat(canvas.height)
        let width = min(source.width, source.height * aspect) / zoom
        let height = width / aspect
        return CGRect(x: (source.width - width) * horizontal,
                      y: (source.height - height) * (1 - vertical), width: width, height: height)
    }
    public func transform(source: CGSize, destination: CGRect) -> CGAffineTransform {
        let crop = crop(in: source)
        guard crop.width > 0, destination.width > 0 else { return .identity }
        let scale = destination.width / crop.width
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: destination.minX - crop.minX * scale,
                                 ty: destination.minY - crop.minY * scale)
    }
}
