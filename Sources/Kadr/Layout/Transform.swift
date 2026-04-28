import Foundation
import CoreGraphics

/// An affine transform applied to a clip in the composition's render space.
///
/// `Transform` describes where a clip's content lands on the render canvas after the
/// engine's built-in aspect-fill scaling. It composes with the existing per-clip
/// `Position`-and-`Anchor` model used elsewhere in kadr — the same coordinate vocabulary
/// (normalized / pixels / percent + nine named anchors) that overlays use.
///
/// ```swift
/// // Picture-in-picture: scale a clip down and pin it to the top-right corner
/// VideoClip(url: pip)
///     .trimmed(to: 0...3)
///     .transform(Transform(
///         center: .topRight,
///         scale: 0.4,
///         anchor: .topRight
///     ))
/// ```
///
/// Apply via ``Kadr/VideoClip/transform(_:)``, ``Kadr/ImageClip/transform(_:)``, or
/// ``Kadr/TitleSequence/transform(_:)``. Identity (no transform) is the default; clips
/// without an explicit `Transform` retain pre-v0.8 layout behavior.
///
/// **Coordinate space.** The transform's `center` and `anchor` resolve in the engine's
/// render space (post-aspect-fill, pre-crop). A clip's natural content fills the render
/// canvas after aspect-fill; rotation and scale pivot around the `anchor`-resolved point
/// of that filled canvas, then the result is moved so the pivot lands on `center`.
///
/// **Animation.** Static `Transform`s apply uniformly across the clip's duration. To
/// animate the transform over time, pair it with an ``Animation`` and use
/// ``Kadr/VideoClip/transform(_:animation:)`` (added in v0.8 Tier 2).
public struct Transform: Sendable, Equatable {

    /// Where the transform's pivot (resolved from `anchor`) lands on the render canvas.
    /// Default: `.normalized(x: 0.5, y: 0.5)` — the canvas center.
    public var center: Position

    /// Rotation around the pivot in radians. Positive values rotate counter-clockwise
    /// (standard math convention). Default: `0`.
    public var rotation: Double

    /// Uniform scale around the pivot. `1.0` leaves the clip at its natural rendered
    /// size; `0.5` halves it; `2.0` doubles it. Default: `1.0`.
    public var scale: Double

    /// Pivot point on the clip itself, expressed as one of nine named anchors.
    /// Rotation and scale operate around this point, and `center` describes where this
    /// point lands on the canvas. Default: `.center`.
    public var anchor: Anchor

    /// Build a transform with explicit values. All parameters have sensible defaults so
    /// you only spell out what you actually want to change.
    public init(
        center: Position = .normalized(x: 0.5, y: 0.5),
        rotation: Double = 0,
        scale: Double = 1,
        anchor: Anchor = .center
    ) {
        self.center = center
        self.rotation = rotation
        self.scale = scale
        self.anchor = anchor
    }

    /// The no-op transform: clip's natural anchor stays at the canvas center, no rotation,
    /// scale `1.0`. Use as the static base when you want only an animation to drive
    /// the clip's appearance.
    public static let identity = Transform()
}

// MARK: - Engine bridge

extension Transform {

    /// Resolve to a `CGAffineTransform` in the render space. Composes with the engine's
    /// existing aspect-fill base transform via `concatenating(_:)` at the layer-instruction
    /// site. Internal — the engine calls this; consumers don't.
    ///
    /// The math is the standard transform-around-pivot pattern:
    ///   `T(center) · R(rotation) · S(scale) · T(-pivot)`
    /// applied right-to-left in CGAffineTransform builder syntax.
    internal func resolved(in renderSize: CGSize) -> CGAffineTransform {
        let centerPoint = center.resolved(in: renderSize)
        let pivotOffset = anchor.normalizedOffset
        let pivotX = pivotOffset.x * renderSize.width
        let pivotY = pivotOffset.y * renderSize.height
        return CGAffineTransform.identity
            .translatedBy(x: centerPoint.x, y: centerPoint.y)
            .rotated(by: CGFloat(rotation))
            .scaledBy(x: CGFloat(scale), y: CGFloat(scale))
            .translatedBy(x: -pivotX, y: -pivotY)
    }
}
