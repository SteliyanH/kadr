import Foundation
import CoreMedia

/// A timed unit that contributes to a ``Video`` composition.
///
/// Built-in conformers: ``VideoClip``, ``ImageClip``, and ``Transition``. Conformers expose a
/// `CMTime`-typed ``duration`` so the composition's timeline math stays frame-accurate.
public protocol Clip: Sendable {
    /// The clip's contribution to the timeline, in media time. For a trimmed `VideoClip` this
    /// reflects the trim length divided by `speedRate`. For an untrimmed `VideoClip` it returns
    /// `.zero` because the source asset hasn't been loaded yet — load `VideoClip/metadata`
    /// asynchronously to read the asset's true duration.
    var duration: CMTime { get }

    /// Optional stable identifier for this clip. Set via `.id(_:)` on a media-clip type
    /// to give callers (e.g. timeline UIs) a stable reference that survives reorder and
    /// trim. Returns `nil` for unidentified clips and for ``Transition``, which isn't
    /// an addressable unit.
    var clipID: ClipID? { get }

    /// Optional explicit composition time at which this clip starts. `nil` (the default)
    /// means the clip participates in the implicit linear chain — the composition appends
    /// it after the previous clip ends. Setting a non-`nil` `startTime` opts the clip out
    /// of the chain and pins it to that time on the composition's timeline; the clip
    /// becomes its own free-floating parallel track.
    ///
    /// Set via `.at(time:)` on a media-clip type. Multiple clips can share a `startTime`
    /// or overlap; render order follows declaration order (later renders on top).
    var startTime: CMTime? { get }

    /// Optional per-clip affine transform applied in the engine's render space. `nil`
    /// (the default) leaves the clip's natural aspect-fill layout unchanged. Media clip
    /// types (``VideoClip``, ``ImageClip``, ``TitleSequence``) expose a `.transform(_:)`
    /// modifier for setting it; ``Transition`` and ``Track`` keep the default.
    /// Added in v0.8.
    var transform: Transform? { get }

    /// Optional clip-relative keyframe animation driving ``transform``. When set, the
    /// engine evaluates the animation per frame and overrides the static base. Set
    /// via `.transform(_:animation:)`. Added in v0.8.
    var transformAnimation: Animation<Transform>? { get }

    /// Optional per-clip opacity in `0...1`. `nil` (default) means fully opaque.
    /// Added in v0.8.
    var opacity: Double? { get }

    /// Optional clip-relative keyframe animation driving ``opacity``. Added in v0.8.
    var opacityAnimation: Animation<Double>? { get }
}

public extension Clip {
    /// Default: clips without an explicit ID return `nil`. The media-clip types
    /// (``VideoClip``, ``ImageClip``, ``TitleSequence``) override this with storage and
    /// expose an `.id(_:)` modifier; ``Transition`` keeps the default.
    var clipID: ClipID? { nil }

    /// Default: clips without explicit `startTime` participate in the implicit chain.
    /// Media-clip types override this with storage and expose `.at(time:)`; ``Transition``
    /// keeps the default since transitions don't make sense as free-floating tracks.
    var startTime: CMTime? { nil }

    /// Default: clips without an explicit transform return `nil`, signaling the engine to
    /// leave layout unchanged. Media-clip types override this with storage; ``Transition``
    /// and ``Track`` keep the default.
    var transform: Transform? { nil }

    /// Default: nil. Media-clip types override with storage; Transition / Track keep nil.
    var transformAnimation: Animation<Transform>? { nil }

    /// Default: nil (fully opaque). Media-clip types override with storage.
    var opacity: Double? { nil }

    /// Default: nil. Media-clip types override with storage.
    var opacityAnimation: Animation<Double>? { nil }
}

extension Clip {
    /// `true` if the clip carries any v0.8 transform / opacity / animation surface that
    /// the engine needs per-clip layer-instruction tracking for. Internal — engine uses
    /// it to skip clips that don't need any per-clip wiring.
    internal var hasAnimationOrLayout: Bool {
        transform != nil
            || transformAnimation != nil
            || opacity != nil
            || opacityAnimation != nil
    }
}
