import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia

/// Pixel-level regression tests for multi-track stacking.
///
/// - https://github.com/SteliyanH/kadr/issues/205 — a parallel `Track { }` must draw
///   *over* the implicit main chain. AVFoundation reads `layerInstructions[0]` as the
///   topmost layer, and the builder used to emit them in declaration order, so the
///   main chain always covered every overlay.
/// - https://github.com/SteliyanH/kadr/issues/206 — a track whose content ends before
///   the composition does must stop rendering. AVFoundation otherwise holds the
///   track's last frame for the rest of the instruction.
///
/// Each test exports a red main chain with a shorter green overlay, then reads the
/// centre pixel of frames grabbed during and after the overlay.
struct MultiTrackLayeringTests {

    private enum Color { case red, green, blue }

    private let preset: Preset = .custom(width: 320, height: 320, frameRate: 30, codec: .h264)

    private func solidImage(_ color: Color) throws -> PlatformImage {
        let size = CGSize(width: 320, height: 320)
        guard let context = CGContext(
            data: nil, width: 320, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw KadrError.unsupportedFormat("Could not create a bitmap context") }
        switch color {
        case .red: context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        case .green: context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        case .blue: context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        }
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

    /// The dominant colour of the centre pixel of the frame at `seconds`.
    private func dominantColor(of url: URL, at seconds: Double) async throws -> Color {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw KadrError.unsupportedFormat("Could not create a 1×1 context") }
        // Draw the frame so its centre lands on the single destination pixel.
        let w = CGFloat(image.width), h = CGFloat(image.height)
        context.draw(image, in: CGRect(x: -w / 2 + 0.5, y: -h / 2 + 0.5, width: w, height: h))

        let (r, g, b) = (pixel[0], pixel[1], pixel[2])
        if r >= g && r >= b { return .red }
        if g >= r && g >= b { return .green }
        return .blue
    }

    // MARK: - Default AVFoundation compositor

    @Test func parallelTrackDrawsOverMainChain() async throws {
        let red = try solidImage(.red), green = try solidImage(.green)
        let url = try await Video {
            ImageClip(red, duration: 3.0)
            Track(at: 0) { ImageClip(green, duration: 1.0) }
        }
        .preset(preset)
        .export(to: outputURL("layer_order"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await dominantColor(of: url, at: 0.5) == .green)
    }

    @Test func freeFloatingClipDrawsOverMainChain() async throws {
        let red = try solidImage(.red), green = try solidImage(.green)
        let url = try await Video {
            ImageClip(red, duration: 3.0)
            ImageClip(green, duration: 1.0).at(time: 1.0)
        }
        .preset(preset)
        .export(to: outputURL("free_floating_order"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await dominantColor(of: url, at: 0.5) == .red)
        #expect(try await dominantColor(of: url, at: 1.5) == .green)
    }

    @Test func laterParallelTracksStackAboveEarlierOnes() async throws {
        let red = try solidImage(.red), green = try solidImage(.green), blue = try solidImage(.blue)
        let url = try await Video {
            ImageClip(red, duration: 3.0)
            Track(at: 0) { ImageClip(green, duration: 2.0) }
            Track(at: 0) { ImageClip(blue, duration: 1.0) }
        }
        .preset(preset)
        .export(to: outputURL("three_tracks"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await dominantColor(of: url, at: 0.5) == .blue)
        #expect(try await dominantColor(of: url, at: 1.5) == .green)
        #expect(try await dominantColor(of: url, at: 2.5) == .red)
    }

    @Test func earlyEndingTrackStopsRendering() async throws {
        let red = try solidImage(.red), green = try solidImage(.green)
        let url = try await Video {
            ImageClip(red, duration: 3.0)
            Track(at: 0) { ImageClip(green, duration: 1.0) }
        }
        .preset(preset)
        .export(to: outputURL("frame_hold"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await dominantColor(of: url, at: 2.0) == .red)
    }

    @Test func earlyEndingAnimatedTrackStopsRendering() async throws {
        // An opacity-bearing overlay goes through the per-clip animation branch of the
        // layer-instruction builder; the hide must still win after the content ends.
        let red = try solidImage(.red), green = try solidImage(.green)
        let url = try await Video {
            ImageClip(red, duration: 3.0)
            Track(at: 0) { ImageClip(green, duration: 1.0).opacity(0.99) }
        }
        .preset(preset)
        .export(to: outputURL("frame_hold_animated"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await dominantColor(of: url, at: 0.5) == .green)
        #expect(try await dominantColor(of: url, at: 2.0) == .red)
    }

    // MARK: - Custom compositor (KadrVideoCompositor)

    @Test func earlyEndingTrackIsDroppedFromCustomCompositorInputs() async throws {
        // A compositor that shows only the topmost input makes a held frame visible:
        // if the ended green track still contributed an image, it would win at t=2.
        let red = try solidImage(.red), green = try solidImage(.green)
        let url = try await Video {
            ImageClip(red, duration: 3.0)
            Track(at: 0) { ImageClip(green, duration: 1.0) }
        }
        .compositor { images, context in
            images.last ?? CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: context.renderSize))
        }
        .preset(preset)
        .export(to: outputURL("custom_frame_hold"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await dominantColor(of: url, at: 0.5) == .green)
        #expect(try await dominantColor(of: url, at: 2.0) == .red)
    }
}
