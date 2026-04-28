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
/// **Optional name (v0.7).** Pass `name:` to attach a human-readable label that
/// surfaces through ``Video/clips``. Downstream tooling (kadr-ui's `TimelineView`)
/// uses it for lane labels in place of auto-generated "Track 1" / "Track 2" captions.
public struct Track: Clip, Sendable {

    /// The clips belonging to this track, in declaration order. Iterate to inspect the
    /// track's internal sub-timeline.
    public let clips: [any Clip]

    /// Composition time at which this track starts. Always non-`nil` for `Track`
    /// (defaults to `.zero` from the parameter-less init); the protocol type is
    /// `CMTime?` because the broader ``Clip/startTime`` requirement allows `nil`
    /// (`Transition` and unanchored regular clips).
    public let startTime: CMTime?

    /// Optional human-readable label for the track. Surfaced through ``Video/clips``
    /// for downstream tooling — kadr-ui's `TimelineView` uses it for lane labels in
    /// place of auto-generated "Track 1" / "Track 2" captions. `nil` by default.
    /// Added in v0.7.
    public let name: String?

    /// Build a track that starts at composition time `.zero` (composition's t=0).
    public init(name: String? = nil, @VideoBuilder _ content: () -> [any Clip]) {
        self.clips = content()
        self.startTime = .zero
        self.name = name
    }

    /// Build a track anchored at a `CMTime` start position.
    public init(at time: CMTime, name: String? = nil, @VideoBuilder _ content: () -> [any Clip]) {
        self.clips = content()
        self.startTime = time
        self.name = name
    }

    /// Build a track anchored at a `TimeInterval` start position. Convenience overload.
    public init(at time: TimeInterval, name: String? = nil, @VideoBuilder _ content: () -> [any Clip]) {
        self.init(at: CMTime(seconds: time, preferredTimescale: 600), name: name, content)
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
