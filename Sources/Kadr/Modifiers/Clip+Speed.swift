import Foundation

/// Canonical representation of a clip's playback speed. v0.11 collapse of
/// the two-method ``VideoClip/speed(_:)`` / ``VideoClip/speed(curve:)``
/// pair into a single enum, making the previously-documented
/// mutual-exclusion compile-time-checked.
///
/// `.flat(Double)` and `.curved(Animation<Double>)` are not composable —
/// a clip is one or the other at any time. The legacy `speed(_:)-(Double)`
/// and `speed(curve:)` overloads this enum replaced were removed in v0.14.
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
    /// the v0.2 `speed(_:)` (`Double`) and v0.9 `speed(curve:)` overloads
    /// (removed in v0.14) with a single setter that makes flat-vs-curved
    /// exclusivity type-level.
    ///
    /// ```swift
    /// VideoClip(url: u).speed(.flat(2.0))                  // 2× playback
    /// VideoClip(url: u).speed(.curved(animation))          // animated curve
    /// ```
    ///
    /// - Parameter value: `.flat(rate)` or `.curved(animation)`.
    /// - Returns: A new clip with the speed applied. The other speed slot is
    ///   cleared, matching the documented mutual exclusion.
    public func speed(_ value: Speed) -> VideoClip {
        switch value {
        case .flat(let rate):
            return with {
    $0.speedRate = rate
    $0.speedCurve = nil
}
        case .curved(let curve):
            return with {
    $0.speedCurve = curve
}
        }
    }

    /// Canonical read surface for the clip's current speed. `.curved` wins
    /// over `.flat` when both stored fields are non-default — matching the
    /// engine's existing precedence (the curve takes priority when set).
    public var speed: Speed {
        if let speedCurve {
            return .curved(speedCurve)
        }
        return .flat(speedRate)
    }
}
