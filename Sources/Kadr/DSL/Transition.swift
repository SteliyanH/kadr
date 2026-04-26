import Foundation
import CoreMedia

/// Direction the **incoming** clip slides in from during a ``Transition`` `.slide`.
/// The outgoing clip slides off in the opposite direction.
public enum SlideDirection: Sendable {
    case fromLeft, fromRight, fromTop, fromBottom
}

/// A timed transition between two media clips.
///
/// Transition durations are stored as `CMTime` for frame-accurate precision.
/// `TimeInterval`-based factory overloads are provided for ergonomic call sites:
///
///     Transition.fade(duration: 0.5)                              // TimeInterval factory
///     Transition.fade(duration: CMTime(value: 1, timescale: 30))  // exact: 1 frame at 30fps
public enum Transition: Clip, Sendable {
    case fade(duration: CMTime)
    case slide(direction: SlideDirection, duration: CMTime)
    case dissolve(duration: CMTime)

    public var duration: CMTime {
        switch self {
        case .fade(let d): return d
        case .slide(_, let d): return d
        case .dissolve(let d): return d
        }
    }
}

extension Transition {
    /// Fade-through-black transition. `TimeInterval` convenience overload.
    public static func fade(duration: TimeInterval) -> Transition {
        .fade(duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Slide transition. `TimeInterval` convenience overload.
    public static func slide(direction: SlideDirection, duration: TimeInterval) -> Transition {
        .slide(direction: direction, duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Cross-dissolve transition. `TimeInterval` convenience overload.
    public static func dissolve(duration: TimeInterval) -> Transition {
        .dissolve(duration: CMTime(seconds: duration, preferredTimescale: 600))
    }
}
