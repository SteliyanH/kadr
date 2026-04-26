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
}
