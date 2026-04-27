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
}

public extension Clip {
    /// Default: clips without an explicit ID return `nil`. The media-clip types
    /// (``VideoClip``, ``ImageClip``, ``TitleSequence``) override this with storage and
    /// expose an `.id(_:)` modifier; ``Transition`` keeps the default.
    var clipID: ClipID? { nil }
}
