import Foundation
import CoreGraphics

/// A point in render space, expressed in resolution-independent or pixel-precise units.
///
/// Kadr defaults to ``normalized(x:y:)`` so a composition you build at one preset (e.g.
/// `.square`, 1080×1080) renders correctly when exported at a different preset (e.g.
/// `.reelsAndShorts`, 1080×1920) without rewriting overlay positions.
///
/// ```swift
/// .position(.center)                                  // resolution-independent
/// .position(.normalized(x: 0.5, y: 0.1))              // 10% from the top, centered
/// .position(.percent(x: 50, y: 90))                   // 50% across, 90% down
/// .position(.pixels(x: 100, y: 200))                  // exact pixel coordinates
/// ```
///
/// > Note on non-square pixels: ``pixels(x:y:)`` interprets values in the export's render
/// > space, where pixels are square by convention. Imported anamorphic assets are stretched
/// > to square pixels by AVFoundation before composition, so this rarely matters in practice.
public enum Position: Sendable, Equatable {
    /// Resolution-independent position. `0...1` in each axis. Origin is top-left.
    /// Values outside `0...1` are valid and let you place an overlay partially off-screen.
    case normalized(x: Double, y: Double)

    /// Position in render-space pixels. Origin is top-left.
    case pixels(x: Double, y: Double)

    /// Resolution-independent position in `0...100`. Equivalent to ``normalized(x:y:)`` × 100;
    /// offered because percentage values read more naturally in some call sites.
    case percent(x: Double, y: Double)

    // MARK: - Convenience anchors (resolution-independent)

    /// Top-left of the render canvas. Equivalent to `.normalized(x: 0, y: 0)`.
    public static let topLeft     = Position.normalized(x: 0,   y: 0)
    /// Top-center of the render canvas.
    public static let top         = Position.normalized(x: 0.5, y: 0)
    /// Top-right of the render canvas.
    public static let topRight    = Position.normalized(x: 1,   y: 0)
    /// Left-center of the render canvas.
    public static let left        = Position.normalized(x: 0,   y: 0.5)
    /// Center of the render canvas.
    public static let center      = Position.normalized(x: 0.5, y: 0.5)
    /// Right-center of the render canvas.
    public static let right       = Position.normalized(x: 1,   y: 0.5)
    /// Bottom-left of the render canvas.
    public static let bottomLeft  = Position.normalized(x: 0,   y: 1)
    /// Bottom-center of the render canvas.
    public static let bottom      = Position.normalized(x: 0.5, y: 1)
    /// Bottom-right of the render canvas. Equivalent to `.normalized(x: 1, y: 1)`.
    public static let bottomRight = Position.normalized(x: 1,   y: 1)

    // MARK: - Resolution

    /// Resolve to a render-space pixel point given the export's render size.
    /// Internal — the engine calls this when laying out a `CALayer` for an overlay.
    internal func resolved(in renderSize: CGSize) -> CGPoint {
        switch self {
        case .normalized(let x, let y):
            return CGPoint(x: x * renderSize.width, y: y * renderSize.height)
        case .pixels(let x, let y):
            return CGPoint(x: x, y: y)
        case .percent(let x, let y):
            return CGPoint(x: (x / 100.0) * renderSize.width, y: (y / 100.0) * renderSize.height)
        }
    }
}
