import Foundation
import CoreGraphics

/// Public namespace for layout helpers that mirror the engine's coordinate math.
///
/// Use these from custom UI (e.g. [`kadr-ui`](https://github.com/SteliyanH/kadr-ui))
/// when you need pixel-exact alignment between an overlay's on-screen rectangle and
/// the rectangle the engine renders during export — for example, drawing a hit-test
/// region around a `TextOverlay` so a SwiftUI tap can map back to the overlay's
/// ``LayerID``.
public enum Layout {

    /// Resolve a ``Position`` + ``Size`` + ``Anchor`` triplet to a render-space `CGRect`.
    ///
    /// This is the same math the export engine uses to lay out overlays and crops, so a
    /// rectangle returned here will exactly match the rectangle the engine renders.
    ///
    /// ```swift
    /// // In a SwiftUI overlay sized to the video's render canvas:
    /// let frame = Layout.resolveFrame(
    ///     position: overlay.position,
    ///     size: overlay.size ?? .normalized(width: 1, height: 1),
    ///     anchor: overlay.anchor,
    ///     in: video.preset.resolution
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - position: Where on the render canvas the overlay's `anchor` point lands.
    ///   - size: The overlay's size in render space.
    ///   - anchor: Which point on the overlay aligns to `position`. Defaults to `.center`.
    ///   - renderSize: The render canvas size, in pixels — typically ``Preset/resolution``.
    /// - Returns: The overlay's pixel-space rectangle on the render canvas.
    public static func resolveFrame(
        position: Position,
        size: Size,
        anchor: Anchor = .center,
        in renderSize: CGSize
    ) -> CGRect {
        FrameResolver.resolve(position: position, size: size, anchor: anchor, in: renderSize)
    }
}
