import Foundation
import CoreGraphics

/// Internal helper that resolves a `Position` + `Size` + `Anchor` triplet into a final
/// pixel-space `CGRect` for a given render size.
///
/// The overlay engine (landing in v0.3.x) calls this when laying out a `CALayer` for each
/// overlay in the composition.
internal enum FrameResolver {

    /// Resolve a layout triplet to a render-space `CGRect`.
    ///
    /// - Parameters:
    ///   - position: where on the render canvas the overlay's anchor point should land
    ///   - size: the overlay's size in render space
    ///   - anchor: which point on the overlay aligns to `position` (default `.center`)
    ///   - renderSize: the export's render size in pixels
    static func resolve(
        position: Position,
        size: Size,
        anchor: Anchor = .center,
        in renderSize: CGSize
    ) -> CGRect {
        let resolvedSize = size.resolved(in: renderSize)
        let anchorPoint = position.resolved(in: renderSize)
        let anchorOffset = anchor.normalizedOffset
        let origin = CGPoint(
            x: anchorPoint.x - resolvedSize.width * anchorOffset.x,
            y: anchorPoint.y - resolvedSize.height * anchorOffset.y
        )
        return CGRect(origin: origin, size: resolvedSize)
    }
}
