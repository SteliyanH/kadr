import Foundation
import CoreMedia
import QuartzCore
import AVFoundation

/// A reveal / kinetic-text animation attached to a ``TextOverlay``. Apply via
/// ``TextOverlay/animation(_:)``.
///
/// Built-in recipes ship in v0.8: ``FadeIn``, ``SlideIn``, ``ScaleUp``. Conform a
/// custom type to drive any other Core-Animation effect on the underlying
/// `CATextLayer`.
///
/// ```swift
/// .overlay(
///     TextOverlay("MY MOVIE", style: titleStyle)
///         .position(.center)
///         .animation(.fadeIn(duration: 1.0))
/// )
/// ```
///
/// **Timing.** Conformers return one or more `CAAnimation` instances ready to be
/// attached to the layer. The animations should set `beginTime` themselves (typically
/// `AVCoreAnimationBeginTimeAtZero` for composition t=0 or a positive offset). The
/// engine adds them to the overlay's `CATextLayer` via `add(_:forKey:)`.
///
/// **Interaction with `.visible(during:)`.** When an overlay carries both a
/// visibility range and an animation, the engine drives visibility separately via a
/// discrete-mode keyframe animation (see `OverlayRenderer.applyVisibilityTiming`).
/// Animations that target `opacity` will compose with that — typically the visibility
/// gate wins (it's the outer shell). For best results, scope the reveal animation's
/// `beginTime` to the overlay's visibility window if you care about exact timing.
public protocol TextAnimation: Sendable {

    /// Build the Core-Animation tree to attach to the overlay's text layer. The engine
    /// adds each returned animation to `layer` via `add(_:forKey:)`. Conformers should
    /// set each animation's `beginTime`, `duration`, `fillMode`, and
    /// `isRemovedOnCompletion` properties as appropriate.
    func makeAnimations(for layer: CALayer) -> [CAAnimation]
}

// MARK: - Built-in recipes

/// Whole-text fade-in: opacity ramps from 0 to the overlay's base opacity over `duration`.
public struct FadeIn: TextAnimation {

    /// Duration of the fade.
    public let duration: CMTime

    /// Starting opacity. Default `0` (fully transparent).
    public let from: Float

    /// Begin time, in composition time. Default `AVCoreAnimationBeginTimeAtZero`
    /// (composition t=0). Set to a positive value to delay the reveal.
    public let beginTime: CFTimeInterval

    public init(
        duration: CMTime,
        from: Float = 0,
        beginTime: CFTimeInterval = AVCoreAnimationBeginTimeAtZero
    ) {
        self.duration = duration
        self.from = from
        self.beginTime = beginTime
    }

    public init(
        duration: TimeInterval,
        from: Float = 0,
        beginTime: CFTimeInterval = AVCoreAnimationBeginTimeAtZero
    ) {
        self.init(
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            from: from,
            beginTime: beginTime
        )
    }

    public func makeAnimations(for layer: CALayer) -> [CAAnimation] {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = from
        anim.toValue = layer.opacity
        anim.duration = CMTimeGetSeconds(duration)
        anim.beginTime = beginTime
        anim.fillMode = .both
        anim.isRemovedOnCompletion = false
        return [anim]
    }
}

extension TextAnimation where Self == FadeIn {

    /// Convenience: `.fadeIn(duration: 1.0)` builds a ``FadeIn`` with the given duration.
    public static func fadeIn(duration: CMTime) -> FadeIn { FadeIn(duration: duration) }

    /// Convenience overload accepting `TimeInterval`.
    public static func fadeIn(duration: TimeInterval) -> FadeIn { FadeIn(duration: duration) }
}

/// Slides the text in from an edge of the render canvas to its resting position
/// over `duration`. The slide direction is named relative to where the text *comes
/// from* — `.fromLeft` enters from off-screen left and lands at its layout position.
public struct SlideIn: TextAnimation {

    /// Where the text slides in from.
    public enum Direction: Sendable {
        case fromLeft, fromRight, fromTop, fromBottom
    }

    public let direction: Direction
    public let duration: CMTime
    public let beginTime: CFTimeInterval

    public init(
        from direction: Direction,
        duration: CMTime,
        beginTime: CFTimeInterval = AVCoreAnimationBeginTimeAtZero
    ) {
        self.direction = direction
        self.duration = duration
        self.beginTime = beginTime
    }

    public init(
        from direction: Direction,
        duration: TimeInterval,
        beginTime: CFTimeInterval = AVCoreAnimationBeginTimeAtZero
    ) {
        self.init(
            from: direction,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            beginTime: beginTime
        )
    }

    public func makeAnimations(for layer: CALayer) -> [CAAnimation] {
        // Off-screen offset large enough to clear any reasonable layer width/height.
        // The layer's superlayer (the parent) has the render-size frame; using its
        // bounds for the offset would require a backref. Use a generous fixed offset.
        let offset: CGFloat = 4000
        let anim = CABasicAnimation()
        switch direction {
        case .fromLeft:
            anim.keyPath = "position.x"
            anim.fromValue = layer.position.x - offset
            anim.toValue = layer.position.x
        case .fromRight:
            anim.keyPath = "position.x"
            anim.fromValue = layer.position.x + offset
            anim.toValue = layer.position.x
        case .fromTop:
            anim.keyPath = "position.y"
            anim.fromValue = layer.position.y - offset
            anim.toValue = layer.position.y
        case .fromBottom:
            anim.keyPath = "position.y"
            anim.fromValue = layer.position.y + offset
            anim.toValue = layer.position.y
        }
        anim.duration = CMTimeGetSeconds(duration)
        anim.beginTime = beginTime
        anim.fillMode = .both
        anim.isRemovedOnCompletion = false
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return [anim]
    }
}

extension TextAnimation where Self == SlideIn {

    /// Convenience: `.slideIn(from: .fromLeft, duration: 0.5)`.
    public static func slideIn(from direction: SlideIn.Direction, duration: CMTime) -> SlideIn {
        SlideIn(from: direction, duration: duration)
    }

    public static func slideIn(from direction: SlideIn.Direction, duration: TimeInterval) -> SlideIn {
        SlideIn(from: direction, duration: duration)
    }
}

/// Scales the text up from a starting scale to its resting size over `duration`.
public struct ScaleUp: TextAnimation {

    public let from: CGFloat
    public let duration: CMTime
    public let beginTime: CFTimeInterval

    public init(
        from: CGFloat = 0.0,
        duration: CMTime,
        beginTime: CFTimeInterval = AVCoreAnimationBeginTimeAtZero
    ) {
        self.from = from
        self.duration = duration
        self.beginTime = beginTime
    }

    public init(
        from: CGFloat = 0.0,
        duration: TimeInterval,
        beginTime: CFTimeInterval = AVCoreAnimationBeginTimeAtZero
    ) {
        self.init(
            from: from,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            beginTime: beginTime
        )
    }

    public func makeAnimations(for layer: CALayer) -> [CAAnimation] {
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = from
        anim.toValue = 1.0
        anim.duration = CMTimeGetSeconds(duration)
        anim.beginTime = beginTime
        anim.fillMode = .both
        anim.isRemovedOnCompletion = false
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return [anim]
    }
}

extension TextAnimation where Self == ScaleUp {

    /// Convenience: `.scaleUp(duration: 0.5)`.
    public static func scaleUp(duration: CMTime) -> ScaleUp { ScaleUp(duration: duration) }

    public static func scaleUp(duration: TimeInterval) -> ScaleUp { ScaleUp(duration: duration) }
}
