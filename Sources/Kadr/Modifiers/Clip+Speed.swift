import Foundation

/// Canonical representation of a clip's playback speed. v0.11 collapse of
/// the two-method ``VideoClip/speed(_:)`` / ``VideoClip/speed(curve:)``
/// pair into a single enum, making the previously-documented
/// mutual-exclusion compile-time-checked.
///
/// `.flat(Double)` and `.curved(Animation<Double>)` are not composable —
/// a clip is one or the other at any time. The legacy `speed(_:)` and
/// `speed(curve:)` overloads stay deprecated for one minor and dispatch
/// through ``VideoClip/speed(_:)-(Speed)``.
public enum Speed: Sendable {
    /// Constant playback multiplier. `1.0` = normal, `0.5` = half-speed,
    /// `2.0` = 2×. Engine-side validation throws `KadrError.invalidSpeed`
    /// at export time if outside `0.25...4.0`.
    case flat(Double)

    /// Non-linear playback speed expressed as an animation over
    /// clip-relative time. Per-sample multipliers outside `0.25...4.0`
    /// clamp at the boundaries (animated curves can pass through extremes
    /// briefly without throwing).
    case curved(Animation<Double>)
}

extension VideoClip {

    // MARK: - Canonical surface (v0.11+)

    /// Apply a playback speed (flat multiplier or animated curve). Replaces
    /// the v0.2 ``speed(_:)-(Double)`` and v0.9 ``speed(curve:)`` overloads
    /// with a single setter that makes flat-vs-curved exclusivity type-level.
    ///
    /// ```swift
    /// VideoClip(url: u).speed(.flat(2.0))                  // 2× playback
    /// VideoClip(url: u).speed(.curved(animation))          // animated curve
    /// ```
    ///
    /// - Parameter value: `.flat(rate)` or `.curved(animation)`.
    /// - Returns: A new clip with the speed applied. The other speed slot is
    ///   cleared, matching the documented mutual exclusion.
    @available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
    public func speed(_ value: Speed) -> VideoClip {
        switch value {
        case .flat(let rate):
            return VideoClip(
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
        case .curved(let curve):
            return VideoClip(
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

    /// Canonical read surface for the clip's current speed. `.curved` wins
    /// over `.flat` when both stored fields are non-default — matching the
    /// engine's existing precedence (the curve takes priority when set).
    @available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
    public var speed: Speed {
        if let speedCurve {
            return .curved(speedCurve)
        }
        return .flat(speedRate)
    }

    // MARK: - Deprecated legacy overloads (kept for one minor)

    /// Plays this clip at the given speed multiplier. Valid range: `0.25...4.0`.
    /// `2.0` halves the clip's duration; `0.5` doubles it. Audio pitch is preserved.
    /// Out-of-range values throw `KadrError.invalidSpeed` at export time.
    ///
    /// Setting a flat speed clears any previously-set ``speed(curve:)``: the two surfaces
    /// are mutually exclusive.
    @available(*, deprecated, message: "Use speed(.flat(rate)) — the v0.11 Speed enum makes flat/curved exclusivity type-level. Removal target: v0.12.")
    public func speed(_ rate: Double) -> VideoClip {
        speed(.flat(rate))
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
    @available(*, deprecated, message: "Use speed(.curved(animation)) — the v0.11 Speed enum makes flat/curved exclusivity type-level. Removal target: v0.12.")
    public func speed(curve: Animation<Double>) -> VideoClip {
        speed(.curved(curve))
    }
}
