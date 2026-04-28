import Foundation
import CoreGraphics
import CoreMedia

/// A text label drawn on top of the video composition for the entire export duration.
///
/// ```swift
/// Video {
///     VideoClip(url: clipURL)
/// }
/// .overlay(
///     TextOverlay("HELLO", style: TextStyle(fontSize: 72, color: .white, alignment: .center))
///         .position(.bottom)
///         .anchor(.bottom)
///         .id("title")
/// )
/// .export(to: outputURL)
/// ```
///
/// > Naming note: this type is `TextOverlay` rather than `Text` to avoid colliding with
/// > SwiftUI's `Text`, which Kadr users almost always import alongside.
public struct TextOverlay: Overlay, Sendable {
    /// The string rendered into the overlay layer.
    public let text: String
    /// Visual style. Defaults to ``TextStyle/default``.
    public let style: TextStyle
    /// Where the overlay's anchor lands on the render canvas.
    public let position: Position
    /// Explicit size, or `nil` to fill the full render area for edge-to-edge wrapping.
    public let size: Size?
    /// Which point on the overlay aligns to its ``position``.
    public let anchor: Anchor
    /// `0.0` invisible to `1.0` fully opaque.
    public let opacity: Double
    /// Optional stable identifier for KadrUI hit-testing in v0.4.
    public let layerID: LayerID?
    /// Composition time range during which this overlay is visible. `nil` = full composition.
    public let visibilityRange: CMTimeRange?

    /// Optional reveal / kinetic-text animation attached via ``animation(_:)``. The
    /// engine attaches the resulting `CAAnimation` tree to the overlay's `CATextLayer`
    /// at export time (and via `AVSynchronizedLayer` at preview time, when consumers
    /// like kadr-ui v0.6 wire it up). Added in v0.8.
    public let textAnimation: (any TextAnimation)?

    /// Build a text overlay. Defaults: full-render-area frame, centered position,
    /// `.center` anchor, full opacity, no layer ID, visible for the entire composition.
    public init(_ text: String, style: TextStyle = .default) {
        self.text = text
        self.style = style
        self.position = .center
        self.size = nil
        self.anchor = .center
        self.opacity = 1.0
        self.layerID = nil
        self.visibilityRange = nil
        self.textAnimation = nil
    }

    internal init(
        text: String,
        style: TextStyle,
        position: Position,
        size: Size?,
        anchor: Anchor,
        opacity: Double,
        layerID: LayerID?,
        visibilityRange: CMTimeRange? = nil,
        textAnimation: (any TextAnimation)? = nil
    ) {
        self.text = text
        self.style = style
        self.position = position
        self.size = size
        self.anchor = anchor
        self.opacity = opacity
        self.layerID = layerID
        self.visibilityRange = visibilityRange
        self.textAnimation = textAnimation
    }

    /// Place the overlay's anchor point at the given render-space position.
    public func position(_ position: Position) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange, textAnimation: textAnimation)
    }

    /// Constrain the text to a bounding box. Omit to let it fill the full render area
    /// (useful for headlines that should wrap edge-to-edge).
    public func size(_ size: Size) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange, textAnimation: textAnimation)
    }

    /// Choose which point on the overlay aligns to its ``position(_:)``. Default `.center`.
    public func anchor(_ anchor: Anchor) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange, textAnimation: textAnimation)
    }

    /// Set the overlay's opacity. `1.0` is fully opaque, `0.0` is invisible.
    public func opacity(_ opacity: Double) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange, textAnimation: textAnimation)
    }

    /// Tag the overlay with a stable ``LayerID`` so KadrUI (v0.4) can route gestures to it.
    public func id(_ layerID: LayerID) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange, textAnimation: textAnimation)
    }

    /// Replace the visual style.
    public func style(_ style: TextStyle) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange, textAnimation: textAnimation)
    }

    /// Show the overlay only during a specific composition time range, in `CMTime` for
    /// frame-accurate boundaries.
    public func visible(during range: CMTimeRange) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: range, textAnimation: textAnimation)
    }

    /// Show the overlay only during a specific composition time range, in seconds.
    public func visible(during range: ClosedRange<TimeInterval>) -> TextOverlay {
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        return visible(during: CMTimeRange(start: start, duration: CMTimeSubtract(end, start)))
    }

    /// Attach a reveal / kinetic-text animation. Built-in recipes: ``FadeIn``,
    /// ``SlideIn``, ``ScaleUp`` (with `.fadeIn(duration:)`, `.slideIn(from:duration:)`,
    /// `.scaleUp(duration:)` factories). Pass any custom ``TextAnimation`` conformer
    /// for arbitrary `CAAnimation` trees. Added in v0.8.
    ///
    /// ```swift
    /// TextOverlay("MY MOVIE", style: titleStyle)
    ///     .position(.center)
    ///     .animation(.fadeIn(duration: 1.0))
    /// ```
    public func animation(_ animation: any TextAnimation) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, visibilityRange: visibilityRange, textAnimation: animation)
    }
}
