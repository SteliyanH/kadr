import Foundation
import CoreGraphics
import CoreMedia

/// An image laid on top of the video composition for the entire export duration.
///
/// ```swift
/// Video {
///     VideoClip(url: clipURL).trimmed(to: 0...10)
/// }
/// .overlay(
///     ImageOverlay(logoImage)
///         .position(.topRight)
///         .size(.normalized(width: 0.2, height: 0.05))
///         .anchor(.topRight)
///         .opacity(0.8)
///         .id("watermark")
/// )
/// .export(to: outputURL)
/// ```
///
/// > Naming note: this type is `ImageOverlay` rather than `Image` to avoid colliding with
/// > SwiftUI's `Image` type, which Kadr users almost always import alongside.
public struct ImageOverlay: Overlay, Sendable {
    /// The source image rendered into the overlay layer.
    public let image: PlatformImage
    /// Where the overlay's anchor lands on the render canvas.
    public let position: Position
    /// Explicit size, or `nil` to use the image's natural pixel dimensions.
    public let size: Size?
    /// Which point on the overlay aligns to its ``position``.
    public let anchor: Anchor
    /// `0.0` invisible to `1.0` fully opaque.
    public let opacity: Double
    /// Optional stable identifier for KadrUI hit-testing in v0.4.
    public let layerID: LayerID?
    /// Composition time range during which this overlay is visible. `nil` = full composition.
    public let visibilityRange: CMTimeRange?

    /// Build an overlay with the given image. Defaults: centered, natural size, full
    /// opacity, no layer ID, visible for the entire composition.
    public init(_ image: PlatformImage) {
        self.image = image
        self.position = .center
        self.size = nil
        self.anchor = .center
        self.opacity = 1.0
        self.layerID = nil
        self.visibilityRange = nil
    }

    internal init(
        image: PlatformImage,
        position: Position,
        size: Size?,
        anchor: Anchor,
        opacity: Double,
        layerID: LayerID?,
        visibilityRange: CMTimeRange? = nil
    ) {
        self.image = image
        self.position = position
        self.size = size
        self.anchor = anchor
        self.opacity = opacity
        self.layerID = layerID
        self.visibilityRange = visibilityRange
    }

    /// Place the overlay at the given position. See ``Position`` for how render-space
    /// coordinates work.
    public func position(_ position: Position) -> ImageOverlay {
        ImageOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange)
    }

    /// Size the overlay using a ``Size``. Omit to fall back to the image's natural pixel size.
    public func size(_ size: Size) -> ImageOverlay {
        ImageOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange)
    }

    /// Choose which point on the overlay aligns to its ``position(_:)``. Default `.center`.
    public func anchor(_ anchor: Anchor) -> ImageOverlay {
        ImageOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange)
    }

    /// Set the overlay's opacity. `1.0` is fully opaque, `0.0` is invisible.
    public func opacity(_ opacity: Double) -> ImageOverlay {
        ImageOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange)
    }

    /// Tag the overlay with a stable ``LayerID`` so KadrUI (v0.4) can route gestures to it.
    public func id(_ layerID: LayerID) -> ImageOverlay {
        ImageOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange)
    }

    /// Show the overlay only during a specific composition time range, in `CMTime` for
    /// frame-accurate boundaries. Outside the range the overlay is hidden (instant
    /// transition, no fade).
    public func visible(during range: CMTimeRange) -> ImageOverlay {
        ImageOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: range)
    }

    /// Show the overlay only during a specific composition time range, in seconds.
    /// Convenience overload — converts to `CMTimeRange` at timescale 600.
    public func visible(during range: ClosedRange<TimeInterval>) -> ImageOverlay {
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        return visible(during: CMTimeRange(start: start, duration: CMTimeSubtract(end, start)))
    }
}
