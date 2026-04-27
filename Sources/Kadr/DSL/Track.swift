import Foundation
import CoreMedia

/// A parallel sub-timeline anchored at an explicit composition time. Tracks let you
/// group multiple clips that should play together as a unit alongside the main
/// timeline — e.g. a sequence of picture-in-picture clips, or a multi-clip overlay
/// with its own internal transitions.
///
/// ```swift
/// Video {
///     VideoClip(url: main).trimmed(to: 0...20)            // main timeline
///
///     Track(at: 2.0) {                                     // PiP track from t=2s
///         VideoClip(url: pipA).trimmed(to: 0...3)
///         Transition.dissolve(duration: 0.5)
///         VideoClip(url: pipB).trimmed(to: 0...3)
///     }
/// }
/// ```
///
/// **Always parallel.** A `Track` always has a `startTime` (defaults to `.zero` if you
/// use the parameter-less init); it does not participate in the implicit linear chain.
/// Use bare clips at the top level for the main timeline; use `Track {}` (or
/// ``VideoClip/at(time:)-(CMTime)``) for parallel content.
///
/// **Inside a Track, clips chain.** The contents of a `Track {}` block follow the
/// regular implicit-chain semantic in *track-relative* time — the first clip starts at
/// the track's `startTime`, the next picks up where the previous ended, and so on.
/// Transitions and the v0.6 single-track timeline rules apply within the track.
///
/// > **v0.6 Tier 2 status:** the surface is in place but engine wiring lands with the
/// > multi-track engine PR (Tier 4). Tracks declared in v0.6.0-pre builds compile and
/// > read back through ``Video/clips``, but the engine still treats them like other
/// > clips in the implicit chain. Final behavior arrives with Tier 4.
public struct Track: Clip, Sendable {

    /// The clips belonging to this track, in declaration order. Iterate to inspect the
    /// track's internal sub-timeline.
    public let clips: [any Clip]

    /// Composition time at which this track starts. Always non-`nil` for `Track`
    /// (defaults to `.zero` from the parameter-less init); the protocol type is
    /// `CMTime?` because the broader ``Clip/startTime`` requirement allows `nil`
    /// (`Transition` and unanchored regular clips).
    public let startTime: CMTime?

    /// Build a track that starts at composition time `.zero` (composition's t=0).
    public init(@VideoBuilder _ content: () -> [any Clip]) {
        self.clips = content()
        self.startTime = .zero
    }

    /// Build a track anchored at a `CMTime` start position.
    public init(at time: CMTime, @VideoBuilder _ content: () -> [any Clip]) {
        self.clips = content()
        self.startTime = time
    }

    /// Build a track anchored at a `TimeInterval` start position. Convenience overload.
    public init(at time: TimeInterval, @VideoBuilder _ content: () -> [any Clip]) {
        self.init(at: CMTime(seconds: time, preferredTimescale: 600), content)
    }

    /// Sum of the track's inner clip durations (in track-relative time). For untrimmed
    /// `VideoClip`s the contribution is `.zero` synchronously — load
    /// ``VideoClip/metadata`` to read the asset's true duration.
    public var duration: CMTime {
        clips.reduce(CMTime.zero) { CMTimeAdd($0, $1.duration) }
    }

    /// Tracks themselves don't carry a ``ClipID``. The clips *inside* a track are
    /// individually addressable via their own `.id(_:)` modifiers.
    public var clipID: ClipID? { nil }
}
