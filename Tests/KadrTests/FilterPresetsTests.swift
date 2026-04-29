import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreImage
import CoreMedia

/// Tests for v0.8.4 — new filter presets (gaussianBlur, vignette, sharpen, zoomBlur,
/// glow). Coverage focuses on the public surface contract:
/// - Each preset constructs at its default scalar
/// - Each preset's `withScalar(_:)` rebuilds with the new scalar (so animation works)
/// - Each preset maps to the correct underlying CIFilter name
/// - Each preset can be applied to a CIImage without throwing
struct FilterPresetsTests {

    // MARK: - Default constructors

    @Test func gaussianBlurDefaultRadius() {
        if case .gaussianBlur(let r) = Filter.gaussianBlur() {
            #expect(r == 10)
        } else {
            Issue.record("expected .gaussianBlur")
        }
    }

    @Test func vignetteDefaultIntensity() {
        if case .vignette(let i) = Filter.vignette() {
            #expect(i == 1.0)
        } else {
            Issue.record("expected .vignette")
        }
    }

    @Test func sharpenDefaultAmount() {
        if case .sharpen(let a) = Filter.sharpen() {
            #expect(a == 0.4)
        } else {
            Issue.record("expected .sharpen")
        }
    }

    @Test func zoomBlurDefaultAmount() {
        if case .zoomBlur(let a) = Filter.zoomBlur() {
            #expect(a == 20)
        } else {
            Issue.record("expected .zoomBlur")
        }
    }

    @Test func glowDefaultIntensity() {
        if case .glow(let i) = Filter.glow() {
            #expect(i == 1.0)
        } else {
            Issue.record("expected .glow")
        }
    }

    // MARK: - withScalar (animation hook)

    @Test func gaussianBlurWithScalarReplacesRadius() {
        if case .gaussianBlur(let r) = Filter.gaussianBlur(radius: 5).withScalar(20) {
            #expect(r == 20)
        } else {
            Issue.record("expected .gaussianBlur")
        }
    }

    @Test func vignetteWithScalarReplacesIntensity() {
        if case .vignette(let i) = Filter.vignette(intensity: 0).withScalar(0.7) {
            #expect(i == 0.7)
        } else {
            Issue.record("expected .vignette")
        }
    }

    @Test func sharpenWithScalarReplacesAmount() {
        if case .sharpen(let a) = Filter.sharpen(amount: 0.4).withScalar(1.0) {
            #expect(a == 1.0)
        } else {
            Issue.record("expected .sharpen")
        }
    }

    @Test func zoomBlurWithScalarReplacesAmount() {
        if case .zoomBlur(let a) = Filter.zoomBlur(amount: 10).withScalar(50) {
            #expect(a == 50)
        } else {
            Issue.record("expected .zoomBlur")
        }
    }

    @Test func glowWithScalarReplacesIntensity() {
        if case .glow(let i) = Filter.glow(intensity: 0.5).withScalar(1.0) {
            #expect(i == 1.0)
        } else {
            Issue.record("expected .glow")
        }
    }

    // MARK: - CIFilter name mapping

    @Test func ciFilterNameMappingsAreCorrect() {
        #expect(Filter.gaussianBlur().ciFilterName == "CIGaussianBlur")
        #expect(Filter.vignette().ciFilterName == "CIVignetteEffect")
        #expect(Filter.sharpen().ciFilterName == "CISharpenLuminance")
        #expect(Filter.zoomBlur().ciFilterName == "CIZoomBlur")
        #expect(Filter.glow().ciFilterName == "CIBloom")
    }

    // MARK: - Application smoke (CIImage in → CIImage out)

    @Test func presetsApplyToCIImageWithoutThrowing() {
        let source = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let presets: [Filter] = [
            .gaussianBlur(radius: 5),
            .vignette(intensity: 0.5),
            .sharpen(amount: 0.5),
            .zoomBlur(amount: 10),
            .glow(intensity: 0.8),
        ]
        for preset in presets {
            // Should produce a non-nil output image (even if the same when CI fails to
            // initialize, the apply contract returns the input unchanged rather than
            // throwing).
            let output = preset.apply(to: source)
            _ = output  // Force evaluation
        }
    }

    // MARK: - Modifier chain integration

    @Test func newPresetsParticipateInChainableFilterModifier() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.gaussianBlur(radius: 8), .vignette(intensity: 0.7))
            .filter(.sharpen(amount: 0.5))
        #expect(clip.filters.count == 3)
        #expect(clip.filterAnimations.count == 3)
        #expect(clip.filterAnimations.allSatisfy { $0 == nil })
    }

    @Test func newPresetsParticipateInAnimatedFilterModifier() {
        let anim = Animation<Double>.keyframes([
            .at(0.0, value: 0),
            .at(2.0, value: 20),
        ])
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.gaussianBlur(radius: 0), animation: anim)
        #expect(clip.filters.count == 1)
        #expect(clip.filterAnimations[0] != nil)
    }
}
