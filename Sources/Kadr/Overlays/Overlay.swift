import Foundation
import CoreMedia

/// A composition node drawn on top of the video. Conformers (``ImageOverlay``,
/// ``TextOverlay``, …) supply the layout properties below; the engine resolves them
/// against the export's render size and builds a `CALayer` per overlay.
///
/// You don't usually conform to this protocol yourself — use the built-in overlay
/// types and chain their layout modifiers (`.position`, `.size`, `.anchor`, `.opacity`,
/// `.id`, `.visible(during:)`).
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

    /// Composition time range during which this overlay is visible. `nil` (the default)
    /// means the overlay is visible for the entire composition. Set via
    /// ``visible(during:)-(CMTimeRange)`` or ``visible(during:)-(ClosedRange<TimeInterval>)``
    /// on the concrete overlay types.
    ///
    /// Outside the range the overlay's CALayer renders at zero opacity (transition is
    /// instant, not faded). Range is clamped to `[0, composition.duration]` at render time.
    var visibilityRange: CMTimeRange? { get }
}

public extension Overlay {
    /// Default: overlays are visible for the entire composition unless overridden.
    var visibilityRange: CMTimeRange? { nil }
}
