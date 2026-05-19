import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Outline drawn around the glyphs of a ``TextOverlay`` / ``TitleSequence``.
///
/// Paired with ``TextStyle/stroke`` (nil = no stroke). The renderer wires this
/// into the text compositor via `NSAttributedString.Key.strokeWidth` +
/// `.strokeColor` — positive widths produce a stroke *plus* the original fill,
/// matching the convention CapCut / iMovie / Final Cut surface. Negative widths
/// (outline-only) are deliberately not exposed; defer to a v0.13+ ergonomic if
/// a use case appears.
///
/// ```swift
/// TextStyle(color: .white, stroke: TextStroke(width: 4, color: .black))
/// ```
///
/// Added in v0.12.
public struct TextStroke: Sendable, Equatable {

    /// Stroke width in render-space points. `0` is equivalent to `nil` —
    /// renderer skips the stroke pass. Negative values are clamped to `0` at
    /// render time (we don't expose outline-only mode through this surface).
    public var width: Double

    /// Stroke color. Cross-platform via ``PlatformColor``. Defaults to black —
    /// the most common pairing for white text on a busy frame, which is the
    /// primary use case this struct exists to support.
    public var color: PlatformColor

    public init(width: Double, color: PlatformColor = .black) {
        self.width = width
        self.color = color
    }

    // Equatable: PlatformColor isn't Equatable on AppKit (NSColor lacks
    // synthesised equality). Mirror TextStyle's convention — compare scalars,
    // skip color components. A future "real color equality" change would
    // silently flip semantics here if we synthesised it.
    public static func == (lhs: TextStroke, rhs: TextStroke) -> Bool {
        lhs.width == rhs.width
    }
}
