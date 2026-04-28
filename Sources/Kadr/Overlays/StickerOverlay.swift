import Foundation
import CoreGraphics
import CoreMedia
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A decorative image overlay (emoji, sticker pack item, badge) with sticker-specific
/// modifiers (`.shadow`, `.rotation`) on top of the standard ``Overlay`` layout chain.
///
/// Structurally similar to ``ImageOverlay``, but the type expresses intent and reserves
/// its modifier surface for sticker-character effects. Use ``ImageOverlay`` for
/// watermarks, photos, and logos; use `StickerOverlay` for decoration:
///
/// ```swift
/// Video {
///     VideoClip(url: clipURL)
/// }
/// .overlay(
///     StickerOverlay(emoji)
///         .position(.center)
///         .size(.normalized(width: 0.2, height: 0.2))
///         .rotation(degrees: -15)
///         .shadow(color: .black, radius: 12, offset: CGSize(width: 0, height: 6), opacity: 0.5)
/// )
/// .export(to: outputURL)
/// ```
public struct StickerOverlay: Overlay, Sendable {
    /// The source image rendered into the sticker layer.
    public let image: PlatformImage
    /// Where the sticker's anchor lands on the render canvas.
    public let position: Position
    /// Explicit size, or `nil` to use the image's natural pixel dimensions.
    public let size: Size?
    /// Which point on the sticker aligns to its ``position``.
    public let anchor: Anchor
    /// `0.0` invisible to `1.0` fully opaque.
    public let opacity: Double
    /// Optional stable identifier for KadrUI hit-testing in v0.4.
    public let layerID: LayerID?

    /// Rotation around the sticker's center, in radians. `0` means no rotation.
    public let rotation: Double

    /// Drop shadow. `nil` means no shadow.
    public let shadow: Shadow?

    /// Drop-shadow parameters for a ``StickerOverlay``.
    public struct Shadow: Sendable, Equatable {
        /// Shadow color.
        public let color: PlatformColor
        /// Blur radius in render-space pixels.
        public let radius: Double
        /// Pixel offset of the shadow from the sticker.
        public let offset: CGSize
        /// `0.0`...`1.0` opacity of the shadow.
        public let opacity: Double

        /// Build a drop-shadow spec. Defaults: black, 8px blur, (0, 4)px offset, 40% opacity.
        public init(
            color: PlatformColor = .black,
            radius: Double = 8,
            offset: CGSize = CGSize(width: 0, height: 4),
            opacity: Double = 0.4
        ) {
            self.color = color
            self.radius = radius
            self.offset = offset
            self.opacity = opacity
        }

        // PlatformColor isn't Equatable on AppKit; skip color when comparing.
        public static func == (lhs: Shadow, rhs: Shadow) -> Bool {
            lhs.radius == rhs.radius && lhs.offset == rhs.offset && lhs.opacity == rhs.opacity
        }
    }

    /// Build a sticker overlay. Defaults: centered, natural size, full opacity, no
    /// rotation, no shadow.
    public init(_ image: PlatformImage) {
        self.image = image
        self.position = .center
        self.size = nil
        self.anchor = .center
        self.opacity = 1.0
        self.layerID = nil
        self.rotation = 0
        self.shadow = nil
        self.visibilityRange = nil
        self.positionAnimation = nil
        self.sizeAnimation = nil
    }

    internal init(
        image: PlatformImage,
        position: Position,
        size: Size?,
        anchor: Anchor,
        opacity: Double,
        layerID: LayerID?,
        rotation: Double,
        shadow: Shadow?,
        visibilityRange: CMTimeRange? = nil,
        positionAnimation: Animation<Position>? = nil,
        sizeAnimation: Animation<Size>? = nil
    ) {
        self.image = image
        self.position = position
        self.size = size
        self.anchor = anchor
        self.opacity = opacity
        self.layerID = layerID
        self.rotation = rotation
        self.shadow = shadow
        self.visibilityRange = visibilityRange
        self.positionAnimation = positionAnimation
        self.sizeAnimation = sizeAnimation
    }

    /// Composition time range during which this sticker is visible. `nil` = full composition.
    public let visibilityRange: CMTimeRange?

    /// Optional keyframe animation driving ``position`` over composition-relative time.
    /// Set via ``position(_:animation:)``. Added in v0.8.1.
    public let positionAnimation: Animation<Position>?

    /// Optional keyframe animation driving ``size`` over composition-relative time.
    /// Set via ``size(_:animation:)``. Added in v0.8.1.
    public let sizeAnimation: Animation<Size>?

    // MARK: - Standard layout modifiers

    /// Place the sticker's anchor point at the given render-space position.
    public func position(_ position: Position) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow, visibilityRange: visibilityRange, positionAnimation: positionAnimation, sizeAnimation: sizeAnimation)
    }

    /// Animate the sticker's position with composition-relative keyframes. Added in v0.8.1.
    public func position(_ base: Position, animation: Animation<Position>) -> StickerOverlay {
        StickerOverlay(image: image, position: base, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow, visibilityRange: visibilityRange, positionAnimation: animation, sizeAnimation: sizeAnimation)
    }

    /// Size the sticker using a ``Size``. Omit to fall back to the image's natural pixel size.
    public func size(_ size: Size) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow, visibilityRange: visibilityRange, positionAnimation: positionAnimation, sizeAnimation: sizeAnimation)
    }

    /// Animate the sticker's size with composition-relative keyframes. Added in v0.8.1.
    public func size(_ base: Size, animation: Animation<Size>) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: base, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow, visibilityRange: visibilityRange, positionAnimation: positionAnimation, sizeAnimation: animation)
    }

    /// Choose which point on the sticker aligns to its ``position(_:)``. Default `.center`.
    public func anchor(_ anchor: Anchor) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow, visibilityRange: visibilityRange, positionAnimation: positionAnimation, sizeAnimation: sizeAnimation)
    }

    /// Set the sticker's opacity. `1.0` is fully opaque, `0.0` is invisible.
    public func opacity(_ opacity: Double) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow, visibilityRange: visibilityRange, positionAnimation: positionAnimation, sizeAnimation: sizeAnimation)
    }

    /// Tag the sticker with a stable ``LayerID`` so KadrUI (v0.4) can route gestures to it.
    public func id(_ layerID: LayerID) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow, visibilityRange: visibilityRange, positionAnimation: positionAnimation, sizeAnimation: sizeAnimation)
    }

    // MARK: - Sticker-specific modifiers

    /// Rotate the sticker around its center, in radians.
    public func rotation(_ radians: Double) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: radians, shadow: shadow, visibilityRange: visibilityRange, positionAnimation: positionAnimation, sizeAnimation: sizeAnimation)
    }

    /// Rotate the sticker around its center, in degrees. Convenience over ``rotation(_:)``.
    public func rotation(degrees: Double) -> StickerOverlay {
        rotation(degrees * .pi / 180)
    }

    /// Apply a drop shadow with explicit parameters.
    public func shadow(_ shadow: Shadow) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow, visibilityRange: visibilityRange, positionAnimation: positionAnimation, sizeAnimation: sizeAnimation)
    }

    /// Apply a drop shadow with inline parameters. Convenience over ``shadow(_:)``.
    public func shadow(
        color: PlatformColor = .black,
        radius: Double = 8,
        offset: CGSize = CGSize(width: 0, height: 4),
        opacity: Double = 0.4
    ) -> StickerOverlay {
        shadow(Shadow(color: color, radius: radius, offset: offset, opacity: opacity))
    }

    /// Show the sticker only during a specific composition time range, in `CMTime` for
    /// frame-accurate boundaries.
    public func visible(during range: CMTimeRange) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow, visibilityRange: range)
    }

    /// Show the sticker only during a specific composition time range, in seconds.
    public func visible(during range: ClosedRange<TimeInterval>) -> StickerOverlay {
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        return visible(during: CMTimeRange(start: start, duration: CMTimeSubtract(end, start)))
    }
}
