import Testing
import Foundation
import Kadr
import AVFoundation
import CoreMedia
import CoreGraphics

/// Public-API tests for the v0.4.0 preview surface — `Video.makePlayerItem()` and
/// `Video.thumbnail(at:)`. Uses a non-`@testable` import so a regression that demotes any
/// of these methods back to `internal` fails the build.
struct PreviewAPITests {

    // MARK: - Test helpers

    private func loadTestVideoURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "mov") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.mov"))
        }
        return url
    }

    private func loadTestImage() throws -> PlatformImage {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "png") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.png"))
        }
        #if canImport(UIKit)
        guard let image = PlatformImage(contentsOfFile: url.path) else {
            throw KadrError.invalidURL(url)
        }
        return image
        #elseif canImport(AppKit)
        guard let image = PlatformImage(contentsOf: url) else {
            throw KadrError.invalidURL(url)
        }
        return image
        #endif
    }

    // MARK: - makePlayerItem

    @Test @MainActor func playerItemFromImageClipHasExpectedDuration() async throws {
        let img = try loadTestImage()
        let video = Video {
            ImageClip(img, duration: 2.0)
        }

        let item = try await video.makePlayerItem()
        let duration = try await item.asset.load(.duration)
        // Image clips encode to a temp mp4 first, so the duration may round to the nearest
        // frame; tolerate up to one frame of drift.
        let expected = CMTime(seconds: 2.0, preferredTimescale: 600)
        let drift = abs(CMTimeGetSeconds(CMTimeSubtract(duration, expected)))
        #expect(drift < 0.05)
    }

    @Test @MainActor func playerItemFromVideoClipHasVideoComposition() async throws {
        let url = try loadTestVideoURL()
        let video = Video {
            VideoClip(url: url).trimmed(to: 0.0...1.0)
        }

        let item = try await video.makePlayerItem()
        // The simple-path videoComposition is built so playback matches preset resolution.
        #expect(item.videoComposition != nil)
        #expect(item.videoComposition?.renderSize == video.preset.resolution)
    }

    @Test @MainActor func playerItemHonorsCropRenderSize() async throws {
        let url = try loadTestVideoURL()
        let video = Video {
            VideoClip(url: url).trimmed(to: 0.0...1.0)
        }
        .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))

        let item = try await video.makePlayerItem()
        let expected = CGSize(width: video.preset.resolution.width * 0.5,
                              height: video.preset.resolution.height * 0.5)
        #expect(item.videoComposition?.renderSize == expected)
    }

    @Test @MainActor func playerItemDoesNotBakeOverlays() async throws {
        // AVVideoCompositionCoreAnimationTool is export-only — attaching it to a
        // playback videoComposition crashes AVFoundation. The preview path therefore
        // must not bake overlays in. Consumers render overlays as SwiftUI views over
        // the player using Layout.resolveFrame(...) for placement.
        let url = try loadTestVideoURL()
        let img = try loadTestImage()
        let video = Video {
            VideoClip(url: url).trimmed(to: 0.0...1.0)
        }
        .overlay(ImageOverlay(img).id("watermark"))

        let item = try await video.makePlayerItem()
        #expect(item.videoComposition?.animationTool == nil)
    }

    @Test @MainActor func playerItemHasFreshIdentityPerCall() async throws {
        let img = try loadTestImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        let a = try await video.makePlayerItem()
        let b = try await video.makePlayerItem()
        #expect(a !== b)
    }

    // MARK: - thumbnail(at:)

    @Test func thumbnailFromVideoClipReturnsImage() async throws {
        let url = try loadTestVideoURL()
        let video = Video {
            VideoClip(url: url).trimmed(to: 0.0...2.0)
        }

        let img = try await video.thumbnail(at: 0.5)
        // Non-zero dimensions confirms a real frame came back.
        #if canImport(UIKit)
        #expect(img.size.width > 0)
        #expect(img.size.height > 0)
        #elseif canImport(AppKit)
        #expect(img.size.width > 0)
        #expect(img.size.height > 0)
        #endif
    }

    @Test func thumbnailHonorsCropRenderSize() async throws {
        let url = try loadTestVideoURL()
        let video = Video {
            VideoClip(url: url).trimmed(to: 0.0...2.0)
        }
        .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))

        let img = try await video.thumbnail(at: 0.5)
        // The thumbnail's pixel size should follow the cropped renderSize, not the full
        // preset resolution. We give a small tolerance because the generator may round
        // to even pixel dimensions.
        let expectedWidth = video.preset.resolution.width * 0.5
        let expectedHeight = video.preset.resolution.height * 0.5
        let widthRatio = img.size.width / expectedWidth
        let heightRatio = img.size.height / expectedHeight
        #expect(abs(widthRatio - 1.0) < 0.05)
        #expect(abs(heightRatio - 1.0) < 0.05)
    }

    @Test func thumbnailAcceptsCMTimeAndTimeIntervalEquivalently() async throws {
        let url = try loadTestVideoURL()
        let video = Video {
            VideoClip(url: url).trimmed(to: 0.0...2.0)
        }
        // Both overloads exist and resolve to the same time. We don't compare pixels —
        // generator output isn't bit-stable — just confirm both calls succeed.
        _ = try await video.thumbnail(at: 0.5)
        _ = try await video.thumbnail(at: CMTime(seconds: 0.5, preferredTimescale: 600))
    }

}
