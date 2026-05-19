import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Drop shadow rendered behind a ``TextOverlay`` / ``TitleSequence``'s glyph
/// layer.
///
/// Paired with ``TextStyle/shadow`` (nil = no shadow). Painted via
/// `CGContext.setShadow(offset:blur:color:)` *before* the text draw call so
/// the shadow lands behind every glyph and behind the optional stroke.
///
/// ```swift
/// TextStyle(
///     color: .white,
///     shadow: TextShadow(offset: CGSize(width: 2, height: 4), blur: 6)
/// )
/// ```
///
/// Added in v0.12.
public struct TextShadow: Sendable, Equatable {

    /// Shadow displacement in render-space points. Positive `width` shifts
    /// right; positive `height` shifts down (UIKit / iOS convention; AppKit's
    /// flipped Y is normalised by the compositor before paint).
    public var offset: CGSize

    /// Gaussian blur radius in render-space points. `0` produces a hard-edged
    /// drop. Clamped to non-negative at render time.
    public var blur: Double

    /// Shadow color. Cross-platform via ``PlatformColor``. Defaults to black at
    /// 50% alpha — the most common drop-shadow tone; consumers wanting a
    /// hard-black shadow pass it explicitly.
    public var color: PlatformColor

    public init(
        offset: CGSize = CGSize(width: 0, height: 2),
        blur: Double = 4,
        color: PlatformColor = .platformShadowDefault
    ) {
        self.offset = offset
        self.blur = blur
        self.color = color
    }

    // Equatable: same convention as TextStroke / TextStyle — compare scalars,
    // skip color components (PlatformColor isn't Equatable on AppKit).
    public static func == (lhs: TextShadow, rhs: TextShadow) -> Bool {
        lhs.offset == rhs.offset && lhs.blur == rhs.blur
    }
}

extension PlatformColor {
    /// Black at 50% alpha — the default ``TextShadow/color``. Hoisted to a
    /// `PlatformColor` static so it builds on both UIKit and AppKit without a
    /// `#if` at every call site.
    public static var platformShadowDefault: PlatformColor {
        #if canImport(UIKit)
        return UIColor(white: 0, alpha: 0.5)
        #else
        return NSColor(white: 0, alpha: 0.5)
        #endif
    }
}
