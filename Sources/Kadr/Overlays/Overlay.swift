import Foundation

/// A composition node drawn on top of the video. Conformers (``ImageOverlay``,
/// ``TextOverlay``, …) supply the layout properties below; the engine resolves them
/// against the export's render size and builds a `CALayer` per overlay.
///
/// You don't usually conform to this protocol yourself — use the built-in overlay
/// types and chain their layout modifiers (`.position`, `.size`, `.anchor`, `.opacity`,
/// `.id`).
public protocol Overlay: Sendable {
    /// Where the overlay's anchor point lands on the render canvas.
    var position: Position { get }

    /// Explicit size of the overlay. `nil` means use a type-specific default
    /// (image overlays use the image's natural pixel size; text overlays use the
    /// full render area for wrapping).
    var size: Size? { get }

    /// Which point on the overlay aligns to its ``position``.
    var anchor: Anchor { get }

    /// `0.0` invisible to `1.0` fully opaque.
    var opacity: Double { get }

    /// Optional stable identifier for KadrUI hit-testing in v0.4.
    var layerID: LayerID? { get }
}
