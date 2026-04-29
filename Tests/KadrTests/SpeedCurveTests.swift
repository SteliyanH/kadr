import Testing
import CoreMedia
import Foundation
@testable import Kadr

/// Tests for v0.9 Tier 1 — speed curves on `VideoClip`.
/// Coverage: pure `SpeedCurveSampler` helpers (discretization + integration), the
/// `VideoClip.speed(curve:)` modifier surface, and `VideoClip.duration` math.
struct SpeedCurveTests {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    // MARK: - SpeedCurveSampler.clampMultiplier

    @Test func clampHonorsLowerBound() {
        #expect(SpeedCurveSampler.clampMultiplier(0.1) == 0.25)
        #expect(SpeedCurveSampler.clampMultiplier(0.0) == 0.25)
        #expect(SpeedCurveSampler.clampMultiplier(-1.0) == 0.25)
    }

    @Test func clampHonorsUpperBound() {
        #expect(SpeedCurveSampler.clampMultiplier(5.0) == 4.0)
        #expect(SpeedCurveSampler.clampMultiplier(100.0) == 4.0)
    }

    @Test func clampPassesValuesInsideRange() {
        #expect(SpeedCurveSampler.clampMultiplier(0.5) == 0.5)
        #expect(SpeedCurveSampler.clampMultiplier(1.0) == 1.0)
        #expect(SpeedCurveSampler.clampMultiplier(2.0) == 2.0)
    }

    // MARK: - discretize

    @Test func discretizeZeroDurationReturnsEmpty() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 1.0)])
        #expect(SpeedCurveSampler.discretize(curve: curve, sourceDuration: .zero).isEmpty)
    }

    @Test func discretizeNegativeRateReturnsEmpty() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 1.0)])
        let segs = SpeedCurveSampler.discretize(curve: curve, sourceDuration: cmt(1.0), rateHz: 0)
        #expect(segs.isEmpty)
    }

    @Test func discretizeAtRateProducesExpectedSegmentCount() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 1.0), .at(2.0, value: 1.0)])
        let segs = SpeedCurveSampler.discretize(curve: curve, sourceDuration: cmt(2.0), rateHz: 30)
        #expect(segs.count == 60)
    }

    @Test func discretizeFlatCurveReproducesSourceDuration() {
        // A flat 1.0 curve should produce target duration == source duration.
        let curve = Animation<Double>.keyframes([
            .at(0.0, value: 1.0),
            .at(2.0, value: 1.0),
        ])
        let total = SpeedCurveSampler.integratedDuration(
            curve: curve,
            sourceDuration: cmt(2.0)
        )
        #expect(abs(total - 2.0) < 0.05)
    }

    @Test func discretizeFlatHalfSpeedDoublesOutput() {
        // 0.5x speed → output is twice the source duration.
        let curve = Animation<Double>.keyframes([
            .at(0.0, value: 0.5),
            .at(2.0, value: 0.5),
        ])
        let total = SpeedCurveSampler.integratedDuration(
            curve: curve,
            sourceDuration: cmt(2.0)
        )
        #expect(abs(total - 4.0) < 0.1)
    }

    @Test func discretizeFlatDoubleSpeedHalvesOutput() {
        // 2x speed → output is half the source duration.
        let curve = Animation<Double>.keyframes([
            .at(0.0, value: 2.0),
            .at(2.0, value: 2.0),
        ])
        let total = SpeedCurveSampler.integratedDuration(
            curve: curve,
            sourceDuration: cmt(2.0)
        )
        #expect(abs(total - 1.0) < 0.05)
    }

    @Test func discretizeOutOfRangeMultiplierClampsAtBounds() {
        // 10x curve should clamp to 4x → output = source/4.
        let curve = Animation<Double>.keyframes([
            .at(0.0, value: 10.0),
            .at(2.0, value: 10.0),
        ])
        let total = SpeedCurveSampler.integratedDuration(
            curve: curve,
            sourceDuration: cmt(2.0)
        )
        #expect(abs(total - 0.5) < 0.05)
    }

    @Test func discretizeSegmentsAreContiguous() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 1.0), .at(1.0, value: 1.0)])
        let segs = SpeedCurveSampler.discretize(curve: curve, sourceDuration: cmt(1.0), rateHz: 10)
        guard segs.count >= 2 else {
            Issue.record("expected multiple segments")
            return
        }
        for i in 1..<segs.count {
            let prevEnd = CMTimeAdd(segs[i - 1].sourceRange.start, segs[i - 1].sourceRange.duration)
            let curStart = segs[i].sourceRange.start
            // 1/600 = ~0.00167s is the timescale-quantization tolerance.
            #expect(abs(CMTimeGetSeconds(prevEnd) - CMTimeGetSeconds(curStart)) < 0.002)
        }
    }

    // MARK: - VideoClip surface

    @Test func speedCurveModifierStoresCurve() {
        let curve = Animation<Double>.keyframes([
            .at(0.0, value: 1.0),
            .at(2.0, value: 0.5),
        ])
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .trimmed(to: 0...2)
            .speed(curve: curve)
        #expect(clip.speedCurve != nil)
    }

    @Test func speedCurveModifierPreservesV08Fields() {
        // Latent-bug guard: setting a speed curve must preserve transform / opacity /
        // filters / animations carried on the clip.
        let opacityAnim = Animation<Double>.keyframes([.at(0.0, value: 0.0), .at(1.0, value: 1.0)])
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .trimmed(to: 0...2)
            .filter(.brightness(0.2))
            .opacity(0.5, animation: opacityAnim)
            .id(ClipID("c"))
            .speed(curve: .keyframes([.at(0.0, value: 1.0), .at(2.0, value: 0.5)]))
        #expect(clip.filters.count == 1)
        #expect(clip.opacity == 0.5)
        #expect(clip.opacityAnimation != nil)
        #expect(clip.clipID == ClipID("c"))
        #expect(clip.speedCurve != nil)
    }

    @Test func flatSpeedClearsCurve() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .trimmed(to: 0...2)
            .speed(curve: .keyframes([.at(0.0, value: 1.0), .at(2.0, value: 0.5)]))
            .speed(2.0)
        #expect(clip.speedCurve == nil)
        #expect(clip.speedRate == 2.0)
    }

    @Test func flatSpeedModifierPreservesV08Fields() {
        // Same latent-bug guard as the curve case — for the existing flat speed modifier.
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .trimmed(to: 0...2)
            .filter(.brightness(0.2))
            .opacity(0.5)
            .id(ClipID("c"))
            .speed(2.0)
        #expect(clip.filters.count == 1)
        #expect(clip.opacity == 0.5)
        #expect(clip.clipID == ClipID("c"))
        #expect(clip.speedRate == 2.0)
    }

    // MARK: - VideoClip.duration with speedCurve

    @Test func durationUsesIntegratedCurveWhenCurveSet() {
        // Half-speed curve → duration doubles.
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .trimmed(to: 0...2)
            .speed(curve: .keyframes([
                .at(0.0, value: 0.5),
                .at(2.0, value: 0.5),
            ]))
        #expect(abs(CMTimeGetSeconds(clip.duration) - 4.0) < 0.1)
    }

    @Test func durationUsesFlatRateWhenNoCurve() {
        // Existing v0.2 flat-speed contract still works.
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .trimmed(to: 0...2)
            .speed(2.0)
        #expect(abs(CMTimeGetSeconds(clip.duration) - 1.0) < 0.001)
    }
}
