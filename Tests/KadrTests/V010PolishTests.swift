import Testing
import CoreMedia
import Foundation
@testable import Kadr

/// Tests for v0.10 Tier 1 — Filter.withScalar public surface + ImageClip.color
/// factory.
struct V010PolishTests {

    // MARK: - Filter.withScalar (now public)

    @Test func withScalarReplacesBrightness() {
        if case .brightness(let v) = Filter.brightness(0.1).withScalar(0.7) {
            #expect(v == 0.7)
        } else {
            Issue.record("expected .brightness")
        }
    }

    @Test func withScalarReplacesGaussianBlurRadius() {
        if case .gaussianBlur(let r) = Filter.gaussianBlur(radius: 5).withScalar(20) {
            #expect(r == 20)
        } else {
            Issue.record("expected .gaussianBlur")
        }
    }

    @Test func withScalarOnNonScalarFiltersReturnsSelf() {
        // .mono / .lut / .chromaKey have no primary scalar; must return unchanged.
        if case .mono = Filter.mono.withScalar(0.5) {
            // ok
        } else {
            Issue.record("expected .mono unchanged")
        }
    }

    // MARK: - ImageClip.color factory

    @Test func colorFactoryProducesImageClipWithGivenDuration() {
        let clip = ImageClip.color(.red, duration: 2.5)
        #expect(abs(CMTimeGetSeconds(clip.duration) - 2.5) < 0.001)
    }

    @Test func colorFactoryAcceptsCMTime() {
        let cm = CMTime(seconds: 4.0, preferredTimescale: 600)
        let clip = ImageClip.color(.blue, duration: cm)
        #expect(abs(CMTimeGetSeconds(clip.duration) - 4.0) < 0.001)
    }

    @Test func colorFactoryDefaultsToThreeSeconds() {
        let clip = ImageClip.color(.green)
        #expect(abs(CMTimeGetSeconds(clip.duration) - 3.0) < 0.001)
    }

    @Test func makeSolidColorImageProducesOnePixel() {
        let img = ImageClip.makeSolidColorImage(.red)
        #expect(img.size.width == 1)
        #expect(img.size.height == 1)
    }

    // MARK: - Track.opacity (Tier 2)

    @Test func trackDefaultOpacityFactorIsOne() {
        let track = Track {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        #expect(track.opacityFactor == 1.0)
    }

    @Test func trackOpacityModifierSetsFactor() {
        let track = Track {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        .opacity(0.5)
        #expect(track.opacityFactor == 0.5)
    }

    @Test func trackOpacityPreservesClipsAndStartTime() {
        let track = Track(at: 2.0, name: "B-roll") {
            ImageClip(PlatformImage(), duration: 1.0)
            ImageClip(PlatformImage(), duration: 2.0)
        }
        .opacity(0.7)
        #expect(track.clips.count == 2)
        #expect(track.name == "B-roll")
        #expect(CMTimeGetSeconds(track.startTime ?? .zero) == 2.0)
        #expect(track.opacityFactor == 0.7)
    }

    @Test func trackOpacityChainable() {
        let track = Track {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        .opacity(0.5)
        .opacity(0.25)
        // Last call wins.
        #expect(track.opacityFactor == 0.25)
    }

    // MARK: - Engine smoke — exports without throwing under track opacity

    @Test func compositionWithTrackOpacityExports() async throws {
        // Smoke test: build a Video with a Track.opacity(0.5) and confirm export
        // doesn't throw. Uses Tier 1's ImageClip.color factory for valid 1×1
        // sources. Comprehensive multi-track and animation suites cover the
        // engine's correctness.
        let video = Video {
            ImageClip.color(.red, duration: 0.5)
            Track(at: 0.0) {
                ImageClip.color(.blue, duration: 0.5)
            }
            .opacity(0.5)
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("v010-track-opacity-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await video.export(to: tmp)
    }
}
