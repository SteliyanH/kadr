import Foundation
import CoreGraphics
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
    public let position: Position
    public let size: Size?
    public let anchor: Anchor
    public let opacity: Double
    public let layerID: LayerID?

    /// Rotation around the sticker's center, in radians. `0` means no rotation.
    public let rotation: Double

    /// Drop shadow. `nil` means no shadow.
    public let shadow: Shadow?

    /// Drop-shadow parameters for a ``StickerOverlay``.
    public struct Shadow: Sendable, Equatable {
        public let color: PlatformColor
        public let radius: Double
        public let offset: CGSize
        public let opacity: Double

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
    }

    internal init(
        image: PlatformImage,
        position: Position,
        size: Size?,
        anchor: Anchor,
        opacity: Double,
        layerID: LayerID?,
        rotation: Double,
        shadow: Shadow?
    ) {
        self.image = image
        self.position = position
        self.size = size
        self.anchor = anchor
        self.opacity = opacity
        self.layerID = layerID
        self.rotation = rotation
        self.shadow = shadow
    }

    // MARK: - Standard layout modifiers

    public func position(_ position: Position) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow)
    }

    public func size(_ size: Size) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow)
    }

    public func anchor(_ anchor: Anchor) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow)
    }

    public func opacity(_ opacity: Double) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow)
    }

    public func id(_ layerID: LayerID) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow)
    }

    // MARK: - Sticker-specific modifiers

    /// Rotate the sticker around its center, in radians.
    public func rotation(_ radians: Double) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: radians, shadow: shadow)
    }

    /// Rotate the sticker around its center, in degrees. Convenience over ``rotation(_:)``.
    public func rotation(degrees: Double) -> StickerOverlay {
        rotation(degrees * .pi / 180)
    }

    /// Apply a drop shadow with explicit parameters.
    public func shadow(_ shadow: Shadow) -> StickerOverlay {
        StickerOverlay(image: image, position: position, size: size, anchor: anchor, opacity: opacity, layerID: layerID, rotation: rotation, shadow: shadow)
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
}
