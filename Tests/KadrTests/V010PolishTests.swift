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
}
