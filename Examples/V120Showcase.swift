import Kadr
import Foundation
import CoreMedia

/// v0.12 showcase — text effects.

// MARK: - Legible copy over busy footage

/// Outline and drop shadow, the two things that keep a caption readable when
/// the frame behind it will not cooperate.
///
/// Both fields default to `nil`, so text written before v0.12 renders exactly as
/// it did. A stroke of width 0 and a shadow with no blur or offset are treated
/// as absent by the renderer — pass `nil` rather than a zero-valued struct if
/// you mean "off", so stored state can tell the two apart.
func v120StrokeAndShadow() async throws {
    let source = URL(fileURLWithPath: "/tmp/street.mov")
    let output = URL(fileURLWithPath: "/tmp/v120_text_effects.mp4")

    _ = try await Video {
        VideoClip(url: source).trimmed(to: 0...6)
    }
    .overlay(
        TextOverlay("OPEN LATE")
            .id("headline")
            .style(TextStyle(
                fontSize: 96,
                stroke: TextStroke(width: 6, color: .black),
                shadow: TextShadow(offset: CGSize(width: 0, height: 4), blur: 12)
            ))
    )
    .export(to: output)
}

/// Stroke alone, for copy over a light background where a shadow would muddy it.
func v120StrokeOnly() -> TextOverlay {
    TextOverlay("SALE")
        .id("badge")
        .style(TextStyle(stroke: TextStroke(width: 4, color: .black)))
}
