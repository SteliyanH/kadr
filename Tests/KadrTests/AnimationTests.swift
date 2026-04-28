import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia
import CoreGraphics

/// Tests for v0.8 Tier 2 — keyframe Animation system.
///
/// Pure tests cover the value type math (Animatable conformances, TimingFunction
/// curves, Animation.value(at:) bracketing). Engine tests verify routing + that
/// animation-bearing clips produce a videoComposition.
struct AnimationTests {

    private let preset: Preset = .auto

    private func loadTestImage() throws -> PlatformImage {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "png") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.png"))
        }
        #if canImport(UIKit)
        guard let image = PlatformImage(contentsOfFile: url.path) else { throw KadrError.invalidURL(url) }
        return image
        #elseif canImport(AppKit)
        guard let image = PlatformImage(contentsOf: url) else { throw KadrError.invalidURL(url) }
        return image
        #endif
    }

    // MARK: - Animatable conformances

    @Test func doubleInterpolatesLinearly() {
        #expect(Double.interpolate(0, 10, t: 0.0) == 0)
        #expect(Double.interpolate(0, 10, t: 0.5) == 5)
        #expect(Double.interpolate(0, 10, t: 1.0) == 10)
    }

    @Test func transformInterpolatesEachComponent() {
        let a = Transform(scale: 1.0, anchor: .center)
        let b = Transform(scale: 2.0, anchor: .center)
        let mid = Transform.interpolate(a, b, t: 0.5)
        #expect(mid.scale == 1.5)
    }

    @Test func transformAnchorSnapsAtMidpoint() {
        let a = Transform(anchor: .topLeft)
        let b = Transform(anchor: .bottomRight)
        // Anchors don't lerp continuously (they're discrete enum cases). Snap convention:
        // first half holds `a`, second half holds `b`.
        #expect(Transform.interpolate(a, b, t: 0.4).anchor == .topLeft)
        #expect(Transform.interpolate(a, b, t: 0.6).anchor == .bottomRight)
    }

    // MARK: - TimingFunction curves

    @Test func linearTimingIsIdentity() {
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(abs(TimingFunction.linear.apply(t) - t) < 0.0001)
        }
    }

    @Test func easeInIsCubicIn() {
        // Cubic: 0³=0, 0.5³=0.125, 1³=1
        #expect(TimingFunction.easeIn.apply(0) == 0)
        #expect(abs(TimingFunction.easeIn.apply(0.5) - 0.125) < 0.0001)
        #expect(TimingFunction.easeIn.apply(1) == 1)
    }

    @Test func easeOutIsCubicOut() {
        // 1 - (1 - 0.5)³ = 1 - 0.125 = 0.875
        #expect(TimingFunction.easeOut.apply(0) == 0)
        #expect(abs(TimingFunction.easeOut.apply(0.5) - 0.875) < 0.0001)
        #expect(TimingFunction.easeOut.apply(1) == 1)
    }

    @Test func easeInOutIsSymmetric() {
        // f(0.5) should be 0.5; f(t) + f(1-t) should equal 1 for any t.
        #expect(abs(TimingFunction.easeInOut.apply(0.5) - 0.5) < 0.0001)
        for t in [0.1, 0.2, 0.3, 0.4] {
            let sum = TimingFunction.easeInOut.apply(t) + TimingFunction.easeInOut.apply(1 - t)
            #expect(abs(sum - 1) < 0.0001)
        }
    }

    @Test func cubicBezierMatchesLinearForControlPoints33And66() {
        // Cubic-bezier(1/3, 1/3, 2/3, 2/3) is the linear curve.
        let f = TimingFunction.cubicBezier(CGPoint(x: 1.0/3.0, y: 1.0/3.0),
                                            CGPoint(x: 2.0/3.0, y: 2.0/3.0))
        for t in stride(from: 0.0, through: 1.0, by: 0.2) {
            #expect(abs(f.apply(t) - t) < 0.01)
        }
    }

    @Test func customClosureRoundtrips() {
        let f = TimingFunction.custom { t in t * t }  // quadratic ease-in
        #expect(abs(f.apply(0.5) - 0.25) < 0.0001)
        #expect(abs(f.apply(0.8) - 0.64) < 0.0001)
    }

    // MARK: - Animation.value(at:)

    @Test func emptyAnimationReturnsNil() {
        let anim = Animation<Double>.keyframes([])
        #expect(anim.value(at: .zero) == nil)
    }

    @Test func singleKeyframeReturnsConstant() {
        let anim = Animation<Double>.keyframes([.at(1.0, value: 0.5)])
        #expect(anim.value(at: .zero) == 0.5)
        #expect(anim.value(at: CMTime(seconds: 5, preferredTimescale: 600)) == 0.5)
    }

    @Test func twoKeyframesLerpLinearly() {
        let anim = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(2.0, value: 1.0),
        ])
        #expect(anim.value(at: CMTime(seconds: 0, preferredTimescale: 600)) == 0.0)
        #expect(anim.value(at: CMTime(seconds: 1, preferredTimescale: 600)) == 0.5)
        #expect(anim.value(at: CMTime(seconds: 2, preferredTimescale: 600)) == 1.0)
    }

    @Test func valueHoldsAtNearestKeyframeOutsideRange() {
        let anim = Animation<Double>.keyframes([
            .at(1.0, value: 0.2),
            .at(3.0, value: 0.8),
        ])
        // Before first keyframe → first value
        #expect(anim.value(at: .zero) == 0.2)
        // After last keyframe → last value
        #expect(anim.value(at: CMTime(seconds: 5, preferredTimescale: 600)) == 0.8)
    }

    @Test func keyframesAreSortedOnConstruction() {
        // Pass out of order → engine sorts internally so evaluation works.
        let anim = Animation<Double>.keyframes([
            .at(2.0, value: 1.0),
            .at(0.0, value: 0.0),
        ])
        #expect(CMTimeGetSeconds(anim.keyframes[0].time) == 0.0)
        #expect(CMTimeGetSeconds(anim.keyframes[1].time) == 2.0)
    }

    @Test func easeInOutTimingChangesIntermediateValues() {
        let linear = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(2.0, value: 1.0),
        ], timing: .linear)
        let eased = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(2.0, value: 1.0),
        ], timing: .easeInOut)
        let t = CMTime(seconds: 0.5, preferredTimescale: 600)
        // At 25% progress through the keyframes, linear gives 0.25; easeInOut gives less.
        #expect(linear.value(at: t)! == 0.25)
        #expect(eased.value(at: t)! < 0.25)
    }

    // MARK: - Modifier composition

    @Test func transformAnimationDefaultsToNil() {
        let img = PlatformImage()
        #expect(VideoClip(url: URL(fileURLWithPath: "/dev/null")).transformAnimation == nil)
        #expect(ImageClip(img, duration: 1.0).transformAnimation == nil)
        #expect(TitleSequence("hi", duration: 1.0).transformAnimation == nil)
    }

    @Test func opacityDefaultsToNil() {
        let img = PlatformImage()
        #expect(VideoClip(url: URL(fileURLWithPath: "/dev/null")).opacity == nil)
        #expect(ImageClip(img, duration: 1.0).opacity == nil)
    }

    @Test func transformWithAnimationStoresBothFields() {
        let base = Transform(scale: 1.0)
        let anim = Animation<Transform>.keyframes([
            .at(0.0, value: Transform(scale: 1.0)),
            .at(2.0, value: Transform(scale: 1.5)),
        ])
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .transform(base, animation: anim)
        #expect(clip.transform == base)
        #expect(clip.transformAnimation != nil)
    }

    @Test func opacityWithAnimationStoresBothFields() {
        let anim = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(0.5, value: 1.0),
        ])
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .opacity(1.0, animation: anim)
        #expect(clip.opacity == 1.0)
        #expect(clip.opacityAnimation != nil)
    }

    @Test func animationFieldsPreservedThroughModifierChain() {
        let anim = Animation<Transform>.keyframes([
            .at(0.0, value: .identity),
            .at(1.0, value: Transform(scale: 0.5)),
        ])
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .transform(.identity, animation: anim)
            .opacity(0.8)
            .trimmed(to: 0...3)
            .id(ClipID("hero"))
        #expect(clip.transformAnimation != nil)
        #expect(clip.opacity == 0.8)
        #expect(clip.clipID == ClipID("hero"))
    }

    // MARK: - Engine integration

    @Test func transformAnimationRoutesThroughMultiTrackPath() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 2.0)
                    .transform(.identity, animation: .keyframes([
                        .at(0.0, value: Transform(scale: 1.0)),
                        .at(2.0, value: Transform(scale: 1.5)),
                    ])),
            ],
            audioTracks: [],
            preset: preset
        )
        // Animation-bearing single-track composition routes through buildMultiTrack
        // to get a videoComposition with layer instructions for setTransform calls.
        #expect(result.videoComposition != nil)
    }

    @Test func opacityAnimationRoutesThroughMultiTrackPath() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 1.0)
                    .opacity(1.0, animation: .keyframes([
                        .at(0.0, value: 0.0),
                        .at(1.0, value: 1.0),
                    ])),
            ],
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition != nil)
    }

    @Test func staticOpacityRoutesThroughMultiTrackPath() async throws {
        // Opacity (static or animated) is a v0.8 surface that requires layer-instruction
        // tracking — same routing rule as Transform.
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [ImageClip(img, duration: 1.0).opacity(0.5)],
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition != nil)
    }

    @Test func clipsWithoutV08SurfaceStillTakeFastPath() async throws {
        // Sanity: pre-v0.8 compositions still route through buildSimple (returns
        // videoComposition: nil). The v0.8 routing rule only triggers when a clip
        // actually carries v0.8 surface.
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [ImageClip(img, duration: 1.0)],
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition == nil)
    }
}
