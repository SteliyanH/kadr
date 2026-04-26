import Foundation
import CoreGraphics

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
    public let position: Position
    public let size: Size?
    public let anchor: Anchor
    public let opacity: Double
    public let layerID: LayerID?

    /// Build a text overlay. Defaults: full-render-area frame, centered position,
    /// `.center` anchor, full opacity, no layer ID.
    public init(_ text: String, style: TextStyle = .default) {
        self.text = text
        self.style = style
        self.position = .center
        self.size = nil
        self.anchor = .center
        self.opacity = 1.0
        self.layerID = nil
    }

    internal init(
        text: String,
        style: TextStyle,
        position: Position,
        size: Size?,
        anchor: Anchor,
        opacity: Double,
        layerID: LayerID?
    ) {
        self.text = text
        self.style = style
        self.position = position
        self.size = size
        self.anchor = anchor
        self.opacity = opacity
        self.layerID = layerID
    }

    public func position(_ position: Position) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID)
    }

    /// Constrain the text to a bounding box. Omit to let it fill the full render area
    /// (useful for headlines that should wrap edge-to-edge).
    public func size(_ size: Size) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID)
    }

    public func anchor(_ anchor: Anchor) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID)
    }

    public func opacity(_ opacity: Double) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID)
    }

    public func id(_ layerID: LayerID) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID)
    }

    /// Replace the visual style.
    public func style(_ style: TextStyle) -> TextOverlay {
        TextOverlay(text: text, style: style, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID)
    }
}
