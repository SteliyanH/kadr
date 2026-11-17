import CoreGraphics
import CoreText
import Foundation

extension TextOverlay {

    /// The size this text takes up when the canvas is `renderSize`: as wide as its
    /// longest line, wrapping at the canvas width, and as tall as its lines.
    ///
    /// A text overlay without an explicit ``size(_:)`` is laid out at this size, so
    /// ``position(_:)`` and ``anchor(_:)`` place the text itself. Before 1.2 the
    /// default box was the whole canvas and the text was drawn at its top, so
    /// `.position(.bottom)` still showed the text at the top.
    ///
    /// Public so a preview (kadr-ui's `OverlayHost`) can lay text out exactly as the
    /// export does.
    public func naturalSize(in renderSize: CGSize) -> CGSize {
        TextMetrics.naturalSize(of: text, style: style, maxWidth: renderSize.width)
    }
}

/// Font and measurement shared by layout and rendering, so the box the text is
/// placed in is the box it is drawn in.
enum TextMetrics {

    /// The font a ``TextStyle`` renders with: the named font, or the system font
    /// at the style's weight.
    static func font(for style: TextStyle) -> CTFont {
        let size = CGFloat(style.fontSize)
        if let name = style.fontName {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: [kCTFontWeightTrait: weight(style.weight)],
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// Values of `kCTFontWeightRegular`, `…Medium` and `…Bold`.
    static func weight(_ weight: TextStyle.Weight) -> CGFloat {
        switch weight {
        case .regular: return 0.0
        case .medium:  return 0.23
        case .bold:    return 0.4
        }
    }

    static func naturalSize(of text: String, style: TextStyle, maxWidth: CGFloat) -> CGSize {
        guard !text.isEmpty, maxWidth > 0 else { return .zero }
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font(for: style),
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil
        )
        // A stroke is drawn centred on the glyph outline, so half of it sits outside
        // the measured glyphs. The extra points also keep CATextLayer, which lays out
        // independently, from wrapping a line that CoreText fitted exactly.
        let strokeWidth = CGFloat(max(0, style.stroke?.width ?? 0))
        let slack = 2 + strokeWidth
        return CGSize(
            width: min(maxWidth, ceil(fitted.width) + slack),
            height: ceil(fitted.height) + slack
        )
    }
}
