import Foundation
import CoreImage
import CoreGraphics

/// Built-in ``Compositor`` that crops a clip to a rectangular region resolved against
/// each frame's extent and scales the result back to fill the original frame.
///
/// **Semantic:** "reframe / zoom-in" — the cropped region replaces the full clip frame.
/// If the crop's aspect ratio doesn't match the frame's, the cropped pixels are stretched
/// to fill (consistent with how typical editor "Reframe" tools behave). For aspect-
/// preserved cropping with letterbox, prefer the composition-wide ``Video/crop(at:size:anchor:)``
/// or compose with explicit overlays.
///
/// Used by ``VideoClip/crop(at:size:anchor:)`` — it's `internal` because users shouldn't
/// construct it directly; the modifier wraps it.
internal struct CropCompositor: Compositor {
    let position: Position
    let size: Size
    let anchor: Anchor

    func process(image: CIImage, context: CompositorContext) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        // Resolve against the source frame's extent (each clip's natural size), not the
        // composition's renderSize — per-clip crop operates in source-asset space and
        // the output replaces the per-clip frame.
        let cropRect = Layout.resolveFrame(
            position: position,
            size: size,
            anchor: anchor,
            in: extent.size
        )

        // CIImage extents are in image-bottom-up coordinates by default; Layout produces
        // rectangles in top-left-origin pixel space. Account for the y-flip.
        let flippedRect = CGRect(
            x: cropRect.origin.x,
            y: extent.height - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )

        // Clamp to the actual extent in case the user requested an out-of-bounds region.
        let clamped = flippedRect.intersection(extent)
        guard !clamped.isEmpty else { return image }

        // Crop, then translate the cropped image back to the origin so it starts at
        // (0, 0) for downstream scaling.
        let cropped = image
            .cropped(to: clamped)
            .transformed(by: CGAffineTransform(translationX: -clamped.origin.x, y: -clamped.origin.y))

        // Scale to fill the original extent. Aspect-preserved letterbox is intentionally
        // not provided here — users wanting that compose with the composition-level crop.
        let scaleX = extent.width / clamped.width
        let scaleY = extent.height / clamped.height
        return cropped.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
}
