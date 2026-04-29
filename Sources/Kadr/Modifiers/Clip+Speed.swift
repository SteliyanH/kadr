import Foundation

extension VideoClip {
    /// Plays this clip at the given speed multiplier. Valid range: `0.25...4.0`.
    /// `2.0` halves the clip's duration; `0.5` doubles it. Audio pitch is preserved.
    /// Out-of-range values throw `KadrError.invalidSpeed` at export time.
    ///
    /// Setting a flat speed clears any previously-set ``speed(curve:)``: the two surfaces
    /// are mutually exclusive.
    public func speed(_ rate: Double) -> VideoClip {
        VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: rate,
            filters: filters,
            filterAnimations: filterAnimations,
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: opacityAnimation,
            speedCurve: nil
        )
    }

    /// Apply a non-linear playback speed curve over clip-relative time. Values in the
    /// animation are speed multipliers (`1.0` = normal, `0.5` = half-speed, `2.0` = 2×).
    /// The engine integrates the curve into a piecewise-linear time map and applies via
    /// repeated `scaleTimeRange` segments.
    ///
    /// Animation timing is **clip-relative** to the trim range: `.at(0.0, ...)` is the
    /// first frame after trim, `.at(trimRange.duration, ...)` is the last. Composes with
    /// ``trimmed(to:)`` (trim selects the source range; the curve maps that range to the
    /// timeline), ``filter(_:animation:)``, ``transform(_:animation:)``, and
    /// ``opacity(_:animation:)``. Audio (when not muted / replaced) follows the same
    /// time map; pitch correction defaults to spectral.
    ///
    /// Setting a curve overrides the flat ``speed(_:)``. Per-sample multipliers outside
    /// `0.25...4.0` clamp at the boundaries rather than throwing — animated curves may
    /// pass through extremes briefly. Added in v0.9.
    ///
    /// ```swift
    /// VideoClip(url: clipURL)
    ///     .trimmed(to: 0...4)
    ///     .speed(curve: .keyframes([
    ///         .at(0.0, value: 1.0),
    ///         .at(1.5, value: 0.25),  // dip into slow-mo
    ///         .at(2.5, value: 0.25),  // hold
    ///         .at(4.0, value: 1.0),   // back to normal
    ///     ], timing: .easeInOut))
    /// ```
    public func speed(curve: Animation<Double>) -> VideoClip {
        VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: speedRate,
            filters: filters,
            filterAnimations: filterAnimations,
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: opacityAnimation,
            speedCurve: curve
        )
    }
}
