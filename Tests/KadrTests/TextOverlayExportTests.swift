import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreGraphics
import CoreMedia

/// Pixel-level check that overlays reach the exported frames.
///
/// https://github.com/SteliyanH/kadr/issues/202 — on macOS, a `TextOverlay` exported
/// outside an app produced no pixels: `CATextLayer` draws its content lazily, and
/// nothing asked it to draw before `AVVideoCompositionCoreAnimationTool` rendered the
/// tree. Image overlays carry their pixels in `contents` up front, so they were
/// unaffected.
///
/// Each test exports a black clip with a white overlay and measures how much of a
/// grabbed frame is bright. Every check has an upper bound too: a frame that is
/// entirely white is a failure, not an overlay.
struct TextOverlayExportTests {

    private static let side = 640
    private let preset: Preset = .custom(width: side, height: side, frameRate: 30, codec: .h264)

    private func solidImage(white: Bool) throws -> PlatformImage {
        let side = Self.side
        let size = CGSize(width: side, height: side)
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw KadrError.unsupportedFormat("Could not create a bitmap context") }
        let v: CGFloat = white ? 1 : 0
        context.setFillColor(CGColor(red: v, green: v, blue: v, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        guard let cg = context.makeImage() else {
            throw KadrError.unsupportedFormat("Could not render the test image")
        }
        #if canImport(UIKit)
        return PlatformImage(cgImage: cg)
        #else
        return PlatformImage(cgImage: cg, size: size)
        #endif
    }

    private func outputURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    /// Fraction of pixels in the frame at `seconds` whose average channel value is
    /// clearly above black.
    private func brightFraction(of url: URL, at seconds: Double = 0.5) async throws -> Double {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw KadrError.unsupportedFormat("Could not create a frame context") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var bright = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let value = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
            if value > 128 { bright += 1 }
        }
        return Double(bright) / Double(width * height)
    }

    private func export(_ overlay: any Overlay, name: String) async throws -> URL {
        let black = try solidImage(white: false)
        return try await Video { ImageClip(black, duration: 1.0) }
            .preset(preset)
            .overlay(overlay)
            .export(to: outputURL(name))
    }

    /// Control: the measuring harness sees an overlay that was never affected.
    @Test func imageOverlayReachesTheExport() async throws {
        let url = try await export(
            ImageOverlay(try solidImage(white: true)).position(.center).size(.pixels(width: 100, height: 100)),
            name: "image_overlay"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        // 100×100 of 640×640 ≈ 0.024.
        let fraction = try await brightFraction(of: url)
        #expect(fraction > 0.015 && fraction < 0.035, "bright fraction \(fraction)")
    }

    @Test func textOverlayReachesTheExport() async throws {
        let url = try await export(
            TextOverlay("hello", style: TextStyle(fontSize: 64)),
            name: "text_overlay"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let fraction = try await brightFraction(of: url)
        #expect(fraction > 0.001 && fraction < 0.1, "bright fraction \(fraction)")
    }

    @Test func positionedTextOverlayReachesTheExport() async throws {
        let url = try await export(
            TextOverlay("MMM", style: TextStyle(fontSize: 96, alignment: .center, weight: .bold))
                .position(.center)
                .size(.pixels(width: 400, height: 140)),
            name: "positioned_text_overlay"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let fraction = try await brightFraction(of: url)
        #expect(fraction > 0.005 && fraction < 0.1, "bright fraction \(fraction)")
    }

    @Test func strokedTextOverlayReachesTheExport() async throws {
        // Stroke routes the string through NSAttributedString — a separate draw path.
        var style = TextStyle(fontSize: 96, alignment: .center, weight: .bold)
        style.stroke = TextStroke(width: 4, color: .white)
        let url = try await export(
            TextOverlay("MMM", style: style).position(.center).size(.pixels(width: 400, height: 140)),
            name: "stroked_text_overlay"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let fraction = try await brightFraction(of: url)
        #expect(fraction > 0.005 && fraction < 0.1, "bright fraction \(fraction)")
    }
}
