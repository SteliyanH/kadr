import Foundation
import CoreMedia

/// Pure helpers for discretizing a ``Animation`` of speed multipliers into a piecewise-
/// linear time map suitable for `AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)`.
///
/// A speed curve `c(t)` returns a multiplier at clip-relative source time `t`. The output
/// (timeline) duration of a source range `[0, T]` is the integral
/// `∫₀ᵀ (1 / c(t)) dt`. The engine approximates that integral by sampling the curve at a
/// fixed rate and emitting one `scaleTimeRange` call per sample, where each segment's
/// target duration is `dt / c(midpoint)`.
///
/// All helpers are pure, deterministic, and unit-tested — no AVFoundation involvement.
enum SpeedCurveSampler {

    /// Default sampling rate in samples-per-source-second. 30 Hz matches the preview frame
    /// rate; benchmark in production whether 60 Hz produces visibly smoother slow-mo at the
    /// cost of 2× scaleTimeRange calls.
    static let defaultRateHz: Double = 30

    /// One discretized speed segment. `sourceRange` is in source-asset time (relative to
    /// the trim's lower bound, i.e. clip-relative). `targetDuration` is the timeline
    /// duration that segment should map to.
    struct Segment: Equatable {
        let sourceRange: CMTimeRange
        let targetDuration: CMTime
    }

    /// Discretize a speed curve into N piecewise-linear segments at `rateHz` samples per
    /// second. Each segment evaluates the curve at its midpoint to pick a representative
    /// multiplier. Returns an empty array for zero-or-negative `sourceDuration`.
    ///
    /// `sourceDuration` is the trim length (the source range the curve maps over).
    /// Segments are emitted relative to that range's start (`.zero`).
    static func discretize(
        curve: Animation<Double>,
        sourceDuration: CMTime,
        rateHz: Double = defaultRateHz
    ) -> [Segment] {
        let sourceSecs = CMTimeGetSeconds(sourceDuration)
        guard sourceSecs > 0, rateHz > 0 else { return [] }
        let dtSecs = 1.0 / rateHz
        let segmentCount = max(1, Int((sourceSecs * rateHz).rounded(.up)))
        var segments: [Segment] = []
        segments.reserveCapacity(segmentCount)
        var cursorSecs: Double = 0
        for _ in 0..<segmentCount {
            let segDur = min(dtSecs, sourceSecs - cursorSecs)
            if segDur <= 0 { break }
            let midSecs = cursorSecs + segDur / 2
            let midTime = CMTime(seconds: midSecs, preferredTimescale: 600)
            let multiplier = curve.value(at: midTime) ?? 1.0
            let safeMultiplier = clampMultiplier(multiplier)
            let targetSecs = segDur / safeMultiplier
            let segStart = CMTime(seconds: cursorSecs, preferredTimescale: 600)
            let segDuration = CMTime(seconds: segDur, preferredTimescale: 600)
            let segRange = CMTimeRange(start: segStart, duration: segDuration)
            let target = CMTime(seconds: targetSecs, preferredTimescale: 600)
            segments.append(Segment(sourceRange: segRange, targetDuration: target))
            cursorSecs += segDur
        }
        return segments
    }

    /// Approximate timeline duration produced by applying `curve` over a source range of
    /// length `sourceDuration`. Returns `0` for zero-or-negative input. Pure — used by
    /// ``VideoClip/duration`` so synchronous timeline math agrees with the engine's
    /// per-segment scaling.
    static func integratedDuration(
        curve: Animation<Double>,
        sourceDuration: CMTime,
        rateHz: Double = defaultRateHz
    ) -> Double {
        let segments = discretize(curve: curve, sourceDuration: sourceDuration, rateHz: rateHz)
        return segments.reduce(0) { $0 + CMTimeGetSeconds($1.targetDuration) }
    }

    /// Clamp the multiplier to the same `0.25...4.0` range that flat ``VideoClip/speed(_:)``
    /// validates. Curves that dip outside the range are silently clamped per-sample rather
    /// than throwing — the curve is animated and may pass through extreme values briefly,
    /// and clamping preserves the export rather than aborting it.
    static func clampMultiplier(_ value: Double) -> Double {
        max(0.25, min(4.0, value))
    }
}
