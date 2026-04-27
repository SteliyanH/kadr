import Foundation
import CoreGraphics
import CoreMedia
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A title clip — a colored background with centered text — placed in a composition like
/// any other ``Clip``.
///
/// ```swift
/// Video {
///     TitleSequence("MY MOVIE",
///                   duration: 3.0,
///                   style: TextStyle(fontSize: 96, weight: .bold))
///     VideoClip(url: clipURL).trimmed(to: 0...10)
/// }
/// .export(to: outputURL)
/// ```
///
/// Internally renders a `PlatformImage` at the export's render size when the engine
/// consumes the clip, then composites it like an ``ImageClip``. Multi-line text is
/// supported via `\n` in the input string.
///
/// Image-based titles (your own pre-rendered title card) — use ``ImageClip`` directly:
/// `ImageClip(titleImage, duration: 3.0)`.
public struct TitleSequence: Clip, Sendable {
    /// The string rendered into the title image.
    public let text: String
    /// Visual style applied to the rendered text.
    public let style: TextStyle
    /// Solid color filling the area behind the text.
    public let backgroundColor: PlatformColor
    private let _duration: CMTime

    /// Stable identifier for addressing this clip across reorders or trims, set via
    /// ``id(_:)``. `nil` if no ID has been assigned.
    public let clipID: ClipID?

    public var duration: CMTime { _duration }

    /// Title with a `TimeInterval` duration.
    public init(
        _ text: String,
        duration: TimeInterval = 3.0,
        style: TextStyle = .default,
        background: PlatformColor = .black
    ) {
        self.init(
            text,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            style: style,
            background: background
        )
    }

    /// Title with a `CMTime` duration for frame-accurate placement.
    public init(
        _ text: String,
        duration: CMTime,
        style: TextStyle = .default,
        background: PlatformColor = .black
    ) {
        self.text = text
        self.style = style
        self.backgroundColor = background
        self._duration = duration
        self.clipID = nil
    }

    internal init(
        text: String,
        duration: CMTime,
        style: TextStyle,
        backgroundColor: PlatformColor,
        clipID: ClipID?
    ) {
        self.text = text
        self.style = style
        self.backgroundColor = backgroundColor
        self._duration = duration
        self.clipID = clipID
    }

    /// Assign a stable identifier so callers can address this clip by ID across reorders
    /// or trims. See ``ClipID`` for guidelines on choosing IDs.
    public func id(_ id: ClipID) -> TitleSequence {
        TitleSequence(text: text, duration: _duration, style: style, backgroundColor: backgroundColor, clipID: id)
    }

    /// Render the title to a `PlatformImage` at the given render size.
    /// The engine calls this when consuming the clip.
    internal func render(at renderSize: CGSize) -> PlatformImage {
        let bounds = CGRect(origin: .zero, size: renderSize)

        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        return renderer.image { ctx in
            backgroundColor.setFill()
            ctx.fill(bounds)
            let attrString = makeAttributedString()
            let textRect = centeredRect(for: attrString, in: bounds)
            attrString.draw(in: textRect)
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: renderSize)
        image.lockFocus()
        backgroundColor.setFill()
        bounds.fill()
        let attrString = makeAttributedString()
        let textRect = centeredRect(for: attrString, in: bounds)
        attrString.draw(in: textRect)
        image.unlockFocus()
        return image
        #endif
    }

    private func makeAttributedString() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = nsAlignment(style.alignment)

        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: style.color,
            .paragraphStyle: paragraph,
        ]
        attributes[.font] = font(for: style)
        return NSAttributedString(string: text, attributes: attributes)
    }

    private func nsAlignment(_ alignment: TextStyle.Alignment) -> NSTextAlignment {
        switch alignment {
        case .leading:  return .left
        case .center:   return .center
        case .trailing: return .right
        }
    }

    private func centeredRect(for attrString: NSAttributedString, in bounds: CGRect) -> CGRect {
        let constrained = CGSize(width: bounds.width * 0.9, height: bounds.height)
        let textBounds = attrString.boundingRect(
            with: constrained,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let x = (bounds.width - textBounds.width) / 2
        let y = (bounds.height - textBounds.height) / 2
        return CGRect(x: x, y: y, width: textBounds.width, height: textBounds.height)
    }

    #if canImport(UIKit)
    private func font(for style: TextStyle) -> UIFont {
        if let name = style.fontName, let custom = UIFont(name: name, size: CGFloat(style.fontSize)) {
            return custom
        }
        return UIFont.systemFont(ofSize: CGFloat(style.fontSize), weight: uiWeight(style.weight))
    }
    private func uiWeight(_ weight: TextStyle.Weight) -> UIFont.Weight {
        switch weight {
        case .regular: return .regular
        case .medium:  return .medium
        case .bold:    return .bold
        }
    }
    #elseif canImport(AppKit)
    private func font(for style: TextStyle) -> NSFont {
        if let name = style.fontName, let custom = NSFont(name: name, size: CGFloat(style.fontSize)) {
            return custom
        }
        return NSFont.systemFont(ofSize: CGFloat(style.fontSize), weight: nsWeight(style.weight))
    }
    private func nsWeight(_ weight: TextStyle.Weight) -> NSFont.Weight {
        switch weight {
        case .regular: return .regular
        case .medium:  return .medium
        case .bold:    return .bold
        }
    }
    #endif
}
