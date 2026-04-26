import Foundation
import CoreGraphics

/// A rectangular region of the composition's render canvas to keep at export time.
///
/// You don't construct `CropRegion` directly — use ``Video/crop(at:size:anchor:)``,
/// which builds one from a ``Position`` + ``Size`` + ``Anchor``. Read the active region
/// off a ``Video`` via ``Video/crop`` for inspection or for laying out custom UI.
public struct CropRegion: Sendable, Equatable {
    /// Where the crop's ``anchor`` lands on the render canvas.
    public let position: Position

    /// The crop rectangle's size in render-canvas coordinates.
    public let size: Size

    /// Which point of the crop rectangle is placed at ``position``.
    public let anchor: Anchor

    internal init(position: Position, size: Size, anchor: Anchor) {
        self.position = position
        self.size = size
        self.anchor = anchor
    }

    /// Resolve to a render-space `CGRect` given the export's preset render size.
    /// The engine uses this to set `videoComposition.renderSize` and to translate
    /// every layer instruction by `-rect.origin`.
    internal func resolved(in renderSize: CGSize) -> CGRect {
        FrameResolver.resolve(position: position, size: size, anchor: anchor, in: renderSize)
    }
}
