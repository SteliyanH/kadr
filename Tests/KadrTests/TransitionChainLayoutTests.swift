import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A transformed or animated clip in a chain that also has a transition.
///
/// This is the most ordinary shape there is (a Ken Burns slideshow with
/// dissolves), and before 1.2 it never finished exporting. A transform sends
/// the chain down the multi-track path, which pre-renders a chain that has
/// transitions by building the same clips again, which takes the multi-track
/// path again, forever.
///
/// Time-limited: the failure mode is a hang, and a hang must fail by name.
@Suite(.timeLimit(.minutes(1)))
struct TransitionChainLayoutTests {

    private let preset: Preset = .custom(width: 128, height: 64, frameRate: 30, codec: .h264)

    private func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> PlatformImage {
        let context = CGContext(data: nil, width: 128, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
        let image = context.makeImage()!
        #if canImport(UIKit)
        return UIImage(cgImage: image)
        #else
        return NSImage(cgImage: image, size: NSSize(width: 128, height: 64))
        #endif
    }

    private var red: PlatformImage { solid(1, 0, 0) }
    private var blue: PlatformImage { solid(0, 0, 1) }

    private func export(_ video: Video) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transition_layout_\(UUID().uuidString).mp4")
        return try await video.preset(preset).export(to: url)
    }

    private func duration(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// RGB at (x, y), with (0, 0) the top-left corner.
    private func pixel(_ url: URL, at seconds: Double, x: Int, y: Int) async throws -> [Int] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let i = (y * width + x) * 4
        return [Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]
    }

    private func isClose(_ rgb: [Int], to target: [Int], tolerance: Int = 60) -> Bool {
        zip(rgb, target).allSatisfy { abs($0 - $1) < tolerance }
    }

    // MARK: - It finishes

    @Test func staticTransformInATransitionChain() async throws {
        let url = try await export(Video {
            ImageClip(red, duration: 1).transform(Transform(scale: 0.5))
            Transition.dissolve(duration: 0.3)
            ImageClip(blue, duration: 1)
        })
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(abs(try await duration(url) - 1.7) < 0.1)
    }

    @Test func kenBurnsInATransitionChain() async throws {
        let url = try await export(Video {
            ImageClip(red, duration: 1).transform(.identity, animation: .keyframes([
                .at(0.0, value: Transform(scale: 1.0)),
                .at(1.0, value: Transform(scale: 1.3)),
            ]))
            Transition.dissolve(duration: 0.3)
            ImageClip(blue, duration: 1).transform(.identity, animation: .keyframes([
                .at(0.0, value: Transform(scale: 1.0)),
                .at(1.0, value: Transform(scale: 1.3)),
            ]))
        })
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(abs(try await duration(url) - 1.7) < 0.1)
    }

    @Test func transformedClipInATrackWithATransition() async throws {
        let url = try await export(Video {
            ImageClip(blue, duration: 2)
            Track(at: 0) {
                ImageClip(red, duration: 1).transform(Transform(scale: 0.5))
                Transition.dissolve(duration: 0.3)
                ImageClip(red, duration: 1)
            }
        })
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(abs(try await duration(url) - 2.0) < 0.1)
    }

    /// The README hero's shape: Ken Burns, a dissolve, and a free-floating clip.
    @Test func animatedChainWithTransitionAndAFloatingClip() async throws {
        let url = try await export(Video {
            ImageClip(red, duration: 1).transform(.identity, animation: .keyframes([
                .at(0.0, value: Transform(scale: 1.0)),
                .at(1.0, value: Transform(scale: 1.2)),
            ]))
            Transition.dissolve(duration: 0.3)
            ImageClip(blue, duration: 1)
            ImageClip(red, duration: 0.5).at(time: 0.5)
                .transform(Transform(center: .topRight, scale: 0.3, anchor: .topRight))
        })
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(abs(try await duration(url) - 1.7) < 0.1)
    }

    // MARK: - It is right

    /// The transform still applies: a half-size red clip leaves black corners.
    @Test func transformIsApplied() async throws {
        let url = try await export(Video {
            ImageClip(red, duration: 1).transform(Transform(scale: 0.5))
            Transition.dissolve(duration: 0.3)
            ImageClip(blue, duration: 1)
        })
        defer { try? FileManager.default.removeItem(at: url) }
        let corner = try await pixel(url, at: 0.2, x: 4, y: 4)
        let centre = try await pixel(url, at: 0.2, x: 64, y: 32)
        #expect(isClose(corner, to: [0, 0, 0]), "outside the half-size clip should be black, got \(corner)")
        #expect(isClose(centre, to: [255, 0, 0]), "the clip's centre should be red, got \(centre)")
    }

    /// The transition still blends the two clips.
    @Test func transitionStillBlends() async throws {
        let url = try await export(Video {
            ImageClip(red, duration: 1).transform(.identity, animation: .keyframes([
                .at(0.0, value: Transform(scale: 1.0)),
                .at(1.0, value: Transform(scale: 1.1)),
            ]))
            Transition.dissolve(duration: 0.4)
            ImageClip(blue, duration: 1)
        })
        defer { try? FileManager.default.removeItem(at: url) }
        // Mid-dissolve: some of each.
        let mid = try await pixel(url, at: 0.8, x: 64, y: 32)
        #expect(mid[0] > 50 && mid[2] > 50, "mid-dissolve should mix red and blue, got \(mid)")
        // After the dissolve: blue.
        let after = try await pixel(url, at: 1.4, x: 64, y: 32)
        #expect(isClose(after, to: [0, 0, 255]), "after the dissolve should be blue, got \(after)")
    }

    /// Preview goes through the same builder, so it hung too. Getting an item
    /// back at all is the assertion; `AVPlayerItem` is main-actor bound.
    @MainActor
    @Test func previewOfAKenBurnsSlideshow() async throws {
        let item = try await Video {
            ImageClip(red, duration: 1).transform(.identity, animation: .keyframes([
                .at(0.0, value: Transform(scale: 1.0)),
                .at(1.0, value: Transform(scale: 1.2)),
            ]))
            Transition.dissolve(duration: 0.3)
            ImageClip(blue, duration: 1)
        }
        .preset(preset)
        .makePlayerItem()
        #expect(item.status != .failed)
        #expect(item.asset is AVComposition)
    }

    /// The backstop: a pre-render nested past the limit throws instead of
    /// recursing. Simulated by starting already at the limit.
    @Test func runawayPreRenderThrowsInsteadOfHanging() async throws {
        let video = Video {
            ImageClip(red, duration: 1)
            Transition.dissolve(duration: 0.3)
            ImageClip(blue, duration: 1)
            ImageClip(red, duration: 0.5).at(time: 0.2)
        }
        .preset(preset)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("runaway_\(UUID().uuidString).mp4")
        await #expect(throws: KadrError.self) {
            try await CompositionBuilder.$preRenderDepth.withValue(CompositionBuilder.maxPreRenderDepth) {
                _ = try await video.export(to: output)
            }
        }
    }
}
