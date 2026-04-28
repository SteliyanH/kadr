import Foundation
import CoreGraphics

/// Maps the linear `0...1` progress of an animation to a non-linear curve, so the
/// animation eases in / out / accelerates / etc. instead of running at a constant rate.
///
/// Mirrors `CAMediaTimingFunction`'s shape — built-in named curves cover the common
/// cases, plus `cubicBezier` for matching CSS / Lottie / After Effects curves and
/// `custom` as the escape hatch.
///
/// ```swift
/// // Slow start, fast end
/// .keyframes([...], timing: .easeIn)
///
/// // Ease in then out — the most common "natural motion" feel
/// .keyframes([...], timing: .easeInOut)
///
/// // Match a CSS cubic-bezier(0.42, 0, 0.58, 1) — equivalent to easeInOut
/// .keyframes([...], timing: .cubicBezier(CGPoint(x: 0.42, y: 0), CGPoint(x: 0.58, y: 1)))
///
/// // Anything else
/// .keyframes([...], timing: .custom { t in pow(t, 3) })
/// ```
public enum TimingFunction: Sendable {
    /// `t` returned unchanged. Constant rate from start to end.
    case linear
    /// Slow start, fast end. Cubic-out shape.
    case easeIn
    /// Fast start, slow end. Cubic-in shape (yes — naming follows Apple's
    /// `kCAMediaTimingFunctionEaseOut`, which feels more natural in motion than the
    /// math-textbook convention).
    case easeOut
    /// Slow start, fast middle, slow end. The most common "natural motion" curve.
    case easeInOut
    /// Custom cubic-Bézier with two control points in `[0, 1]² `. Matches CSS
    /// `cubic-bezier(p1.x, p1.y, p2.x, p2.y)`.
    case cubicBezier(_ p1: CGPoint, _ p2: CGPoint)
    /// Arbitrary closure mapping `0...1` progress to `0...1` output. The closure is
    /// `@Sendable` because the animation engine is.
    case custom(@Sendable (Double) -> Double)

    /// Apply the timing function to a linear progress value `t` in `0...1`. Output
    /// is normally also in `0...1` but isn't clamped (a timing function might
    /// overshoot, e.g. for back-easing curves added later).
    public func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeIn:
            // Cubic ease-in: t³
            return t * t * t
        case .easeOut:
            // Cubic ease-out: 1 − (1 − t)³
            let inv = 1 - t
            return 1 - inv * inv * inv
        case .easeInOut:
            // Cubic ease-in-out: 4t³ for t < 0.5; 1 − (−2t + 2)³ / 2 for t ≥ 0.5
            if t < 0.5 {
                return 4 * t * t * t
            } else {
                let f = -2 * t + 2
                return 1 - (f * f * f) / 2
            }
        case .cubicBezier(let p1, let p2):
            return Self.cubicBezier(t: t, p1: p1, p2: p2)
        case .custom(let fn):
            return fn(t)
        }
    }

    /// Newton-Raphson cubic-bezier solver. Matches the math browsers use for
    /// `cubic-bezier(p1.x, p1.y, p2.x, p2.y)`. Pure; called from `apply(_:)`.
    /// Internal so we can test the math directly.
    internal static func cubicBezier(t input: Double, p1: CGPoint, p2: CGPoint) -> Double {
        // The cubic-bezier curve is parametric in u ∈ [0, 1]; given an x value (here
        // `input` plays the role of x), we solve for u, then evaluate y(u).
        let cx = 3 * Double(p1.x)
        let bx = 3 * (Double(p2.x) - Double(p1.x)) - cx
        let ax = 1 - cx - bx
        let cy = 3 * Double(p1.y)
        let by = 3 * (Double(p2.y) - Double(p1.y)) - cy
        let ay = 1 - cy - by

        func sampleX(_ u: Double) -> Double { ((ax * u + bx) * u + cx) * u }
        func sampleDX(_ u: Double) -> Double { (3 * ax * u + 2 * bx) * u + cx }

        // Newton-Raphson with 4 iterations is enough for visual fidelity.
        var u = input
        for _ in 0..<4 {
            let x = sampleX(u) - input
            let dx = sampleDX(u)
            if abs(dx) < 1e-6 { break }
            u -= x / dx
        }
        // Clamp u to [0, 1] in case the iteration overshot.
        u = max(0, min(1, u))
        return ((ay * u + by) * u + cy) * u
    }
}
