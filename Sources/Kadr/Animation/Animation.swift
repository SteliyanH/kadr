import Foundation
import CoreMedia

/// A keyframe-driven animation of an ``Animatable`` value. Pair with a clip's
/// `.transform(_:animation:)` or `.opacity(_:animation:)` modifier to animate that
/// property over the clip's lifetime.
///
/// ```swift
/// // Ken Burns zoom-pan on a still image
/// ImageClip(photo, duration: 5.0)
///     .transform(.identity, animation:
///         .keyframes([
///             .at(0.0, value: Transform(scale: 1.0, center: .normalized(x: 0.5, y: 0.5))),
///             .at(5.0, value: Transform(scale: 1.3, center: .normalized(x: 0.6, y: 0.4))),
///         ], timing: .easeInOut)
///     )
/// ```
///
/// **Timing is clip-relative.** A `.at(0.0, ...)` keyframe maps to the clip's first
/// visible frame, not composition t=0. The engine maps clip-relative keyframe times
/// to absolute composition times at evaluation. Same rule applies to chain clips,
/// `.at(time:)` free-floaters, and (in v0.8.2+) clips inside `Track {}` blocks.
///
/// **Engine evaluation.** The engine samples the animation at the composition's frame
/// rate inside the keyframes' time range. Outside the range, the value is held at the
/// nearest keyframe's value (no extrapolation). One-keyframe animations evaluate as a
/// constant; zero-keyframe animations are a no-op (engine falls back to the static
/// base value).
public struct Animation<Value: Animatable>: Sendable {

    /// Keyframes in declaration order. Evaluation expects them sorted by `time`; the
    /// `keyframes(_:timing:)` factory sorts on construction so out-of-order input is
    /// safe at the call site.
    public let keyframes: [Keyframe]

    /// Timing function applied to the linear progress between adjacent keyframes.
    public let timing: TimingFunction

    /// A single keyframe — a clip-relative time and the property's value at that time.
    public struct Keyframe: Sendable {

        /// Clip-relative time of this keyframe. `.zero` is the clip's first frame.
        public let time: CMTime

        /// Property value at this keyframe.
        public let value: Value

        public init(time: CMTime, value: Value) {
            self.time = time
            self.value = value
        }

        /// Build a keyframe from a `TimeInterval` (seconds) — convenience overload.
        public static func at(_ seconds: TimeInterval, value: Value) -> Keyframe {
            Keyframe(time: CMTime(seconds: seconds, preferredTimescale: 600), value: value)
        }

        /// Build a keyframe from a `CMTime` for frame-accurate placement.
        public static func at(_ time: CMTime, value: Value) -> Keyframe {
            Keyframe(time: time, value: value)
        }
    }

    /// Build an animation from a list of keyframes. Keyframes are sorted by `time` on
    /// construction, so out-of-order input is safe.
    public static func keyframes(
        _ keyframes: [Keyframe],
        timing: TimingFunction = .linear
    ) -> Animation<Value> {
        let sorted = keyframes.sorted { CMTimeCompare($0.time, $1.time) < 0 }
        return Animation(keyframes: sorted, timing: timing)
    }

    private init(keyframes: [Keyframe], timing: TimingFunction) {
        self.keyframes = keyframes
        self.timing = timing
    }
}

// MARK: - Evaluation (internal)

extension Animation {

    /// Earliest keyframe time. `.invalid` for an empty animation.
    internal var startTime: CMTime {
        keyframes.first?.time ?? .invalid
    }

    /// Latest keyframe time. `.invalid` for an empty animation.
    internal var endTime: CMTime {
        keyframes.last?.time ?? .invalid
    }

    /// Evaluate at clip-relative time `t`. Returns `nil` for an empty animation.
    /// Outside the keyframes' range, holds at the nearest keyframe's value.
    internal func value(at t: CMTime) -> Value? {
        guard let first = keyframes.first else { return nil }
        if keyframes.count == 1 { return first.value }
        // Hold-at-nearest outside the range
        if CMTimeCompare(t, first.time) <= 0 { return first.value }
        if CMTimeCompare(t, keyframes.last!.time) >= 0 { return keyframes.last!.value }

        // Find the bracketing pair.
        for i in 1..<keyframes.count {
            let next = keyframes[i]
            if CMTimeCompare(t, next.time) <= 0 {
                let prev = keyframes[i - 1]
                let segDur = CMTimeGetSeconds(CMTimeSubtract(next.time, prev.time))
                guard segDur > 0 else { return next.value }
                let segElapsed = CMTimeGetSeconds(CMTimeSubtract(t, prev.time))
                let linearProgress = max(0, min(1, segElapsed / segDur))
                let easedProgress = timing.apply(linearProgress)
                return Value.interpolate(prev.value, next.value, t: easedProgress)
            }
        }
        // Fallthrough — shouldn't happen given the bounds check above, but keep
        // the contract by returning the last keyframe's value.
        return keyframes.last!.value
    }
}
