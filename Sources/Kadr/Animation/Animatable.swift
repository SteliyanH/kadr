import Foundation
import CoreGraphics

/// A type whose values can be smoothly interpolated between keyframes.
///
/// Conform a type to `Animatable` to make it animatable through ``Animation``. The
/// only requirement is `interpolate(_:_:t:)` — given two values and a fraction `t`
/// in `0...1`, return the interpolated value. The engine drives `t` from the current
/// composition time mapped through the animation's ``TimingFunction``.
///
/// Built-in conformers in v0.8: ``Transform``, `Double` (for opacity / filter
/// intensity). v0.8.1 adds ``Position`` and ``Size`` for animated overlay layout.
public protocol Animatable: Sendable {
    /// Interpolate between `a` (at `t == 0`) and `b` (at `t == 1`). Conformers should
    /// produce sensible results for `t` in the open `(0, 1)` interval; values outside
    /// that range are clamped by the engine before this is called.
    static func interpolate(_ a: Self, _ b: Self, t: Double) -> Self
}

// MARK: - Built-in conformances

extension Double: Animatable {
    public static func interpolate(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * t
    }
}

extension Transform: Animatable {
    public static func interpolate(_ a: Transform, _ b: Transform, t: Double) -> Transform {
        Transform(
            center: Position.interpolate(a.center, b.center, t: t),
            rotation: Double.interpolate(a.rotation, b.rotation, t: t),
            scale: Double.interpolate(a.scale, b.scale, t: t),
            anchor: t < 0.5 ? a.anchor : b.anchor
        )
    }
}

/// `Position` is `Animatable` so it can drive `Transform.center` keyframes and (as
/// of v0.8.1) overlay `.position(_:animation:)` modifiers. Mixed-type pairs
/// (e.g. `.normalized` → `.pixels`) resolve at a unit canvas and lerp the resolved
/// points; matching-type pairs lerp components directly.
extension Position: Animatable {
    public static func interpolate(_ a: Position, _ b: Position, t: Double) -> Position {
        switch (a, b) {
        case (.normalized(let ax, let ay), .normalized(let bx, let by)):
            return .normalized(x: Double.interpolate(ax, bx, t: t), y: Double.interpolate(ay, by, t: t))
        case (.pixels(let ax, let ay), .pixels(let bx, let by)):
            return .pixels(x: Double.interpolate(ax, bx, t: t), y: Double.interpolate(ay, by, t: t))
        case (.percent(let ax, let ay), .percent(let bx, let by)):
            return .percent(x: Double.interpolate(ax, bx, t: t), y: Double.interpolate(ay, by, t: t))
        default:
            // Mixed types: resolve both at a unit canvas (1×1) and interpolate. Returns
            // a `.normalized` result (the canonical interchange form).
            let unitSize = CGSize(width: 1, height: 1)
            let resolvedA = a.resolved(in: unitSize)
            let resolvedB = b.resolved(in: unitSize)
            return .normalized(
                x: Double.interpolate(Double(resolvedA.x), Double(resolvedB.x), t: t),
                y: Double.interpolate(Double(resolvedA.y), Double(resolvedB.y), t: t)
            )
        }
    }
}

/// `Size` is `Animatable` for overlay `.size(_:animation:)` modifiers.
///
/// Like `Position`, matching-type pairs lerp components directly; mixed-type pairs
/// (and the `.aspectFit` / `.aspectFill` cases, which are computed from a bounding
/// size at render time) resolve at a unit canvas and lerp into a `.normalized` form.
/// The unit-canvas approach means animated `aspectFit` / `aspectFill` interpolation
/// produces visually-reasonable in-between sizes but doesn't preserve the aspect
/// constraint mid-animation. Authors that care should switch to `.normalized` /
/// `.pixels` / `.percent` for the keyframe values.
extension Size: Animatable {
    public static func interpolate(_ a: Size, _ b: Size, t: Double) -> Size {
        switch (a, b) {
        case (.normalized(let aw, let ah), .normalized(let bw, let bh)):
            return .normalized(width: Double.interpolate(aw, bw, t: t), height: Double.interpolate(ah, bh, t: t))
        case (.pixels(let aw, let ah), .pixels(let bw, let bh)):
            return .pixels(width: Double.interpolate(aw, bw, t: t), height: Double.interpolate(ah, bh, t: t))
        case (.percent(let aw, let ah), .percent(let bw, let bh)):
            return .percent(width: Double.interpolate(aw, bw, t: t), height: Double.interpolate(ah, bh, t: t))
        default:
            // Mixed types or aspect cases: resolve at a unit canvas and lerp into
            // a `.normalized` result.
            let unitSize = CGSize(width: 1, height: 1)
            let resolvedA = a.resolved(in: unitSize)
            let resolvedB = b.resolved(in: unitSize)
            return .normalized(
                width: Double.interpolate(Double(resolvedA.width), Double(resolvedB.width), t: t),
                height: Double.interpolate(Double(resolvedA.height), Double(resolvedB.height), t: t)
            )
        }
    }
}
