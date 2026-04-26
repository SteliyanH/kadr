import Foundation
import CoreGraphics

/// A rectangular region of the composition's render canvas to keep at export time.
///
/// You don't construct `CropRegion` directly — use ``Video/crop(at:size:anchor:)``,
/// which builds one from a ``Position`` + ``Size`` + ``Anchor``.
internal struct CropRegion: Sendable, Equatable {
    let position: Position
    let size: Size
    let anchor: Anchor

    /// Resolve to a render-space `CGRect` given the export's preset render size.
    /// The engine uses this to set `videoComposition.renderSize` and to translate
    /// every layer instruction by `-rect.origin`.
    func resolved(in renderSize: CGSize) -> CGRect {
        FrameResolver.resolve(position: position, size: size, anchor: anchor, in: renderSize)
    }
}
