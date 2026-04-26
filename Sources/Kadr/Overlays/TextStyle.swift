import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Visual style for a ``TextOverlay``.
///
/// ```swift
/// TextOverlay("HELLO", style: TextStyle(
///     fontName: "Helvetica-Bold",
///     fontSize: 72,
///     color: .white,
///     alignment: .center
/// ))
/// ```
public struct TextStyle: Sendable, Equatable {
    /// Font family name (e.g. `"Helvetica-Bold"`). `nil` selects the system font at
    /// the requested ``weight``.
    public var fontName: String?

    /// Font size in render-space points. The renderer scales for export resolution.
    public var fontSize: Double

    /// Foreground color. Cross-platform via ``PlatformColor``.
    public var color: PlatformColor

    /// Horizontal alignment within the overlay's frame.
    public var alignment: Alignment

    /// Font weight. Only consulted when ``fontName`` is `nil` (system font).
    public var weight: Weight

    public enum Alignment: String, Sendable, Equatable {
        case leading, center, trailing
    }

    public enum Weight: Sendable, Equatable {
        case regular, medium, bold
    }

    public init(
        fontName: String? = nil,
        fontSize: Double = 36,
        color: PlatformColor = .white,
        alignment: Alignment = .leading,
        weight: Weight = .regular
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.weight = weight
    }

    /// Default style: system font, 36pt, white, leading-aligned, regular weight.
    public static let `default` = TextStyle()

    // Equatable: PlatformColor isn't Equatable on AppKit; compare components manually.
    public static func == (lhs: TextStyle, rhs: TextStyle) -> Bool {
        lhs.fontName == rhs.fontName
            && lhs.fontSize == rhs.fontSize
            && lhs.alignment == rhs.alignment
            && lhs.weight == rhs.weight
        // color intentionally omitted — equality not load-bearing on the engine path
    }
}
