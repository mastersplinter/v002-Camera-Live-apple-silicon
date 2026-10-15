import Testing
import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import VirtualCameraShared

private func gradient(width: Int, height: Int) -> CGImage {
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            rgba[i] = UInt8(x * 255 / (width - 1))
            rgba[i + 1] = UInt8(y * 255 / (height - 1))
            rgba[i + 2] = 90
        }
    }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: CGDataProvider(data: Data(rgba) as CFData)!, decode: nil,
        shouldInterpolate: true, intent: .defaultIntent)!
}

struct VideoFramingTests {
    @Test func defaultCanonCropFillsCanvasWithoutDistortion() {
        for canvas in VideoCanvas.allCases {
            let framing = VideoFraming(canvas: canvas)
            let crop = framing.crop(in: CGSize(width: 1056, height: 704))
            #expect(crop == CGRect(x: 0, y: 55, width: 1056, height: 594))
            let transform = framing.transform(source: CGSize(width: 1056, height: 704), destination: CGRect(origin: .zero, size: canvas.size))
            #expect(abs(transform.a - transform.d) < 0.000001)
            let result = crop.applying(transform)
            #expect(abs(result.width - canvas.size.width) < 0.000001)
            #expect(abs(result.height - canvas.size.height) < 0.000001)
            #expect(abs(result.minX) < 0.000001 && abs(result.minY) < 0.000001)
        }
    }

    @Test func cropStaysInsidePortraitWideAndCanonSourcesAtEveryLimit() {
        for source in [CGSize(width: 1056, height: 704), CGSize(width: 600, height: 1200), CGSize(width: 2000, height: 600)] {
            for zoom in [1.0, 2, 4] {
                for x in [0.0, 0.5, 1] {
                    for y in [0.0, 0.5, 1] {
                        let crop = VideoFraming(zoom: zoom, horizontal: x, vertical: y).crop(in: source)
                        #expect(crop.minX >= -0.000001 && crop.minY >= -0.000001)
                        #expect(crop.maxX <= source.width + 0.000001 && crop.maxY <= source.height + 0.000001)
                        #expect(abs(crop.width / crop.height - 16.0 / 9.0) < 0.000001)
                    }
                }
            }
        }
        #expect(VideoFraming(vertical: 0).crop(in: CGSize(width: 1056, height: 704)).maxY == 704)
        #expect(VideoFraming(vertical: 1).crop(in: CGSize(width: 1056, height: 704)).minY == 0)
        #expect(VideoFraming().crop(in: .zero) == .zero)
    }

    @Test func persistedSettingsRoundTripAndClampInvalidValues() throws {
        let value = VideoFraming(canvas: .hd1080, zoom: 2.4, horizontal: 0.2, vertical: 0.9)
        #expect(try JSONDecoder().decode(VideoFraming.self, from: JSONEncoder().encode(value)) == value)
        let outside = Data(#"{"canvas":"hd720","zoom":0,"horizontal":-10,"vertical":20}"#.utf8)
        #expect(try JSONDecoder().decode(VideoFraming.self, from: outside) == VideoFraming(zoom: 1, horizontal: 0, vertical: 1))
        #expect(VideoFraming(zoom: .nan, horizontal: .infinity, vertical: -.infinity) == VideoFraming())
    }

    @Test func renderedPixelsMatchCropAtBothResolutionsAndAllEdges() throws {
        let image = gradient(width: 320, height: 240)
        for canvas in VideoCanvas.allCases {
            let renderer = try VideoFrameRenderer(canvas: canvas, softwareRendering: true)
            for framing in [VideoFraming(canvas: canvas), VideoFraming(canvas: canvas, zoom: 2, horizontal: 0, vertical: 0),
                            VideoFraming(canvas: canvas, zoom: 4, horizontal: 1, vertical: 1)] {
                let buffer = try renderer.render(image, framing: framing)
                #expect(CVPixelBufferGetWidth(buffer) == canvas.width && CVPixelBufferGetHeight(buffer) == canvas.height)
                let crop = framing.crop(in: CGSize(width: image.width, height: image.height))
                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                let bytes = try #require(CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self))
                for (x, y) in [(0, 0), (canvas.width - 1, 0), (0, canvas.height - 1),
                               (canvas.width - 1, canvas.height - 1), (canvas.width / 2, canvas.height / 2)] {
                    let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                    let sourceX = crop.minX + (Double(x) + 0.5) / Double(canvas.width) * crop.width
                    let sourceY = Double(image.height) - crop.maxY + (Double(y) + 0.5) / Double(canvas.height) * crop.height
                    #expect(abs(Double(bytes[offset + 2]) - sourceX / Double(image.width - 1) * 255) < 4)
                    #expect(abs(Double(bytes[offset + 1]) - sourceY / Double(image.height - 1) * 255) < 4)
                    #expect(abs(Int(bytes[offset]) - 90) < 3)
                    #expect(bytes[offset + 3] == 255)
                }
            }
        }
    }

    @Test func supports1080pSamplesStandbyAndConsumerResizing() throws {
        let renderer = try VideoFrameRenderer(canvas: .hd1080, softwareRendering: true)
        let full = try renderer.render(gradient(width: 160, height: 90))
        let sample = try VirtualCameraFormat.sample(full, at: .zero)
        #expect(CMVideoFormatDescriptionGetDimensions(try #require(CMSampleBufferGetFormatDescription(sample))).width == 1920)
        #expect(VirtualCameraFormat.accepts(try VirtualCameraFormat.placeholder(canvas: .hd1080)))
        let smaller = try VideoFrameRenderer(canvas: .hd720, softwareRendering: true).resize(full)
        #expect(CVPixelBufferGetWidth(smaller) == 1280 && CVPixelBufferGetHeight(smaller) == 720)
    }
}
