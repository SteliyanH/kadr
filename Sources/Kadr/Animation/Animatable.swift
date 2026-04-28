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

// `Position` is interpolated internally so `Transform`'s `center` keyframes work,
// but `Position` itself isn't *publicly* `Animatable` until v0.8.1 (where overlays
// gain `.position(_:animation:)`). We keep the conformance internal here to avoid
// committing to the public contract early.
extension Position {
    /// Internal interpolation for `Transform.center` keyframes. The public
    /// `Animatable` conformance on `Position` arrives in v0.8.1.
    static func interpolate(_ a: Position, _ b: Position, t: Double) -> Position {
        // For mixed cases (e.g., normalized → pixels), we resolve both at a unit
        // canvas (1×1) and lerp the resolved points back into a normalized form.
        // For matching cases we lerp the components directly.
        switch (a, b) {
        case (.normalized(let ax, let ay), .normalized(let bx, let by)):
            return .normalized(x: Double.interpolate(ax, bx, t: t), y: Double.interpolate(ay, by, t: t))
        case (.pixels(let ax, let ay), .pixels(let bx, let by)):
            return .pixels(x: Double.interpolate(ax, bx, t: t), y: Double.interpolate(ay, by, t: t))
        case (.percent(let ax, let ay), .percent(let bx, let by)):
            return .percent(x: Double.interpolate(ax, bx, t: t), y: Double.interpolate(ay, by, t: t))
        default:
            // Mixed types: resolve both at a unit canvas and interpolate. Returns a
            // .normalized result (the canonical interchange form).
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
