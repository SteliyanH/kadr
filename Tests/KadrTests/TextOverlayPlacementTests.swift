import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Text lands where `.position` and `.anchor` put it.
///
/// Before 1.2, a text overlay without an explicit size was laid out in a box the
/// size of the whole canvas, and Core Animation draws text at the top of its box.
/// So `.position(.bottom).anchor(.bottom)` (the example in `TextOverlay`'s own
/// docs) put the text at the top, and so did `.position(.center)`. These tests
/// export white text on black and find where the white pixels actually are.
///
/// Overlay export needs Core Animation, which the iOS Simulator cannot run (see
/// Known Platform Issues), so these are macOS-only.
#if os(macOS)
@Suite(.timeLimit(.minutes(1)))
struct TextOverlayPlacementTests {

    private let width = 320, height = 180
    private var preset: Preset { .custom(width: width, height: height, frameRate: 30, codec: .h264) }
    private let style = TextStyle(fontSize: 36, color: .white, weight: .bold)

    private var black: PlatformImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
    }

    /// The bounding box of the bright pixels, with (0, 0) the top-left corner.
    private func textBox(_ overlay: TextOverlay) async throws -> CGRect {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("text_place_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        _ = try await Video { ImageClip(black, duration: 1) }
            .overlay(overlay)
            .preset(preset)
            .export(to: output)

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                if pixels[i] > 160 && pixels[i + 1] > 160 && pixels[i + 2] > 160 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        try #require(maxX >= 0, "no text pixels found")
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @Test func defaultPlacementIsCentred() async throws {
        let box = try await textBox(TextOverlay("Hello", style: style))
        #expect(abs(box.midX - CGFloat(width) / 2) < 12, "text centre x \(box.midX)")
        #expect(abs(box.midY - CGFloat(height) / 2) < 12, "text centre y \(box.midY)")
    }

    /// `TextOverlay`'s documented example.
    @Test func bottomAnchoredTextSitsAtTheBottom() async throws {
        let box = try await textBox(TextOverlay("Hello", style: style).position(.bottom).anchor(.bottom))
        #expect(box.maxY > CGFloat(height) - 20, "text bottom \(box.maxY)")
        #expect(box.minY > CGFloat(height) / 2, "text top \(box.minY) should be in the lower half")
    }

    @Test func topLeftAnchoredTextSitsTopLeft() async throws {
        let box = try await textBox(TextOverlay("Hello", style: style).position(.topLeft).anchor(.topLeft))
        #expect(box.minX < 20, "text left \(box.minX)")
        #expect(box.minY < 20, "text top \(box.minY)")
        #expect(box.maxX < CGFloat(width) / 2, "text should stay left, right edge \(box.maxX)")
    }

    /// "Jumpy" has descenders, so its pixels reach the bottom of the text box.
    @Test func normalizedPositionPlacesTheAnchor() async throws {
        let box = try await textBox(
            TextOverlay("Jumpy", style: style).position(.normalized(x: 0.05, y: 0.9)).anchor(.bottomLeft)
        )
        #expect(abs(box.minX - CGFloat(width) * 0.05) < 10, "text left \(box.minX)")
        #expect(abs(box.maxY - CGFloat(height) * 0.9) < 8, "text bottom \(box.maxY)")
    }

    /// An explicit size keeps its old meaning: the text is laid out in that box.
    @Test func explicitSizeIsHonoured() async throws {
        let box = try await textBox(
            TextOverlay("Hello", style: style).size(.normalized(width: 1, height: 1)).position(.center)
        )
        #expect(box.minY < 30, "a full-canvas box draws its text at the top, got top \(box.minY)")
    }

    // MARK: - Visibility window with a text animation

    /// Bright pixels in the frame at `seconds`, on a 4 s black composition.
    private func brightPixels(_ overlay: TextOverlay, at times: [Double]) async throws -> [Int] {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("text_vis_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        _ = try await Video { ImageClip(black, duration: 4) }
            .overlay(overlay)
            .preset(preset)
            .export(to: output)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var counts: [Int] = []
        for seconds in times {
            let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            counts.append(stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 160 }.count)
        }
        return counts
    }

    /// Before 1.2 this text never appeared: the fade was built after the window
    /// had set the layer's opacity to 0, so it faded from 0 to 0.
    @Test func fadeInInsideAVisibilityWindow() async throws {
        let overlay = TextOverlay("Hello", style: style)
            .visible(during: 1.0...3.0)
            .animation(.fadeIn(duration: 0.5))
        let counts = try await brightPixels(overlay, at: [0.5, 1.05, 2.0, 3.5])
        #expect(counts[0] == 0, "hidden before the window")
        #expect(counts[2] > 100, "shown in the window, got \(counts[2]) bright pixels")
        #expect(counts[1] < counts[2] / 2, "fading in when it appears, not at zero: \(counts[1]) vs \(counts[2])")
        #expect(counts[3] == 0, "hidden after the window")
    }

    @Test func slideInInsideAVisibilityWindow() async throws {
        let overlay = TextOverlay("Hello", style: style)
            .visible(during: 1.0...3.0)
            .animation(.slideIn(from: .fromLeft, duration: 0.4))
        let counts = try await brightPixels(overlay, at: [0.5, 2.0, 3.5])
        #expect(counts[0] == 0)
        #expect(counts[1] > 100)
        #expect(counts[2] == 0)
    }

    @Test func fadeInWithoutAWindowIsUnchanged() async throws {
        let counts = try await brightPixels(TextOverlay("Hello", style: style).animation(.fadeIn(duration: 0.5)),
                                            at: [0.05, 2.0])
        #expect(counts[0] < counts[1] / 2)
        #expect(counts[1] > 100)
    }

    // MARK: - naturalSize

    @Test func naturalSizeFitsOneLine() {
        let canvas = CGSize(width: 1920, height: 1080)
        let short = TextOverlay("Hi", style: style).naturalSize(in: canvas)
        let long = TextOverlay("Hello there", style: style).naturalSize(in: canvas)
        #expect(short.width > 0 && short.height > 0)
        #expect(long.width > short.width)
        #expect(abs(long.height - short.height) < 1, "one line each")
        #expect(short.height < 36 * 2, "one line of 36 pt text, got \(short.height)")
    }

    @Test func naturalSizeWrapsAtTheCanvasWidth() {
        let canvas = CGSize(width: 200, height: 1080)
        let text = String(repeating: "word ", count: 30)
        let size = TextOverlay(text, style: style).naturalSize(in: canvas)
        #expect(size.width <= canvas.width)
        #expect(size.height > 36 * 3, "should wrap to several lines, got \(size.height)")
    }

    @Test func strokeWidensTheBox() {
        let canvas = CGSize(width: 1920, height: 1080)
        let plain = TextOverlay("Hello", style: style).naturalSize(in: canvas)
        let stroked = TextOverlay("Hello", style: TextStyle(fontSize: 36, weight: .bold, stroke: TextStroke(width: 6)))
            .naturalSize(in: canvas)
        #expect(stroked.width > plain.width)
    }

    /// `.bold` and `.medium` render at their weight, in the system font. Before
    /// 1.2 every weight came out as Helvetica Regular.
    @Test(arguments: [(TextStyle.Weight.regular, 0.0), (.medium, 0.23), (.bold, 0.4)])
    func weightIsHonoured(_ weight: TextStyle.Weight, _ expected: Double) {
        let font = TextMetrics.font(for: TextStyle(fontSize: 40, weight: weight))
        let traits = CTFontCopyTraits(font) as NSDictionary
        let actual = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? -1
        #expect(abs(actual - expected) < 0.05, "weight \(weight) rendered at \(actual)")
        #expect(!(CTFontCopyFamilyName(font) as String).contains("Helvetica"))
    }

    @Test func emptyTextHasNoSize() {
        #expect(TextOverlay("", style: style).naturalSize(in: CGSize(width: 100, height: 100)) == .zero)
    }
}
#endif
