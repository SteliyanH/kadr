import Kadr
import Foundation
import CoreMedia

/// v0.3.0 showcase — overlays, filters, crop, and sugar working together.
///
/// Each function below is a self-contained recipe demonstrating one or more v0.3 features.
/// All function bodies use placeholder URLs — wire them to real assets to run.

// MARK: - 1. Overlays — image, text, sticker, watermark

/// Lays an image, a text caption, a rotated sticker, and a corner watermark on top of a clip.
@available(iOS 16, macOS 13, *)
func v030OverlayShowcase() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let logo = PlatformImage()
    let sticker = PlatformImage()
    let outputURL = URL(fileURLWithPath: "/tmp/v030_overlays.mp4")

    _ = try await Video {
        VideoClip(url: videoURL).trimmed(to: 0...8)
    }
    // Image overlay — full image at the top center
    .overlay(
        ImageOverlay(logo)
            .position(.top)
            .anchor(.top)
            .size(.normalized(width: 0.3, height: 0.1))
            .opacity(0.9)
    )
    // Text caption at the bottom
    .overlay(
        TextOverlay("LIVE FROM HQ",
                    style: TextStyle(fontSize: 56, color: .white, alignment: .center, weight: .bold))
            .position(.bottom)
            .anchor(.bottom)
            .size(.normalized(width: 1.0, height: 0.15))
            .id("caption")
    )
    // Decorative sticker — rotated and shadowed
    .overlay(
        StickerOverlay(sticker)
            .position(.center)
            .size(.normalized(width: 0.2, height: 0.2))
            .rotation(degrees: -12)
            .shadow(color: .black, radius: 16, offset: CGSize(width: 0, height: 8), opacity: 0.5)
            .id("burst")
    )
    // Watermark sugar — bottom-right at 50% opacity
    .watermark(logo, position: .bottomRight, opacity: 0.5)
    .preset(.reelsAndShorts)
    .export(to: outputURL)
}

// MARK: - 2. Filters — color grading

/// Applies a multi-filter chain across clips with a transition between them.
@available(iOS 16, macOS 13, *)
func v030FilterShowcase() async throws {
    let clipA = URL(fileURLWithPath: "/tmp/a.mov")
    let clipB = URL(fileURLWithPath: "/tmp/b.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v030_filters.mp4")

    _ = try await Video {
        // Subtle warm grade
        VideoClip(url: clipA).trimmed(to: 0...5)
            .filter(.brightness(0.05), .contrast(1.15), .saturation(1.2))

        Transition.dissolve(duration: 0.5)

        // Stark mono on the second clip
        VideoClip(url: clipB).trimmed(to: 0...5).filter(.mono)
    }
    .export(to: outputURL)
}

// MARK: - 3. Crop — reframing for portrait export

/// Cinema source (16:9), exported as a portrait crop centered on the action.
@available(iOS 16, macOS 13, *)
func v030CropShowcase() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/landscape.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v030_crop.mp4")

    _ = try await Video {
        VideoClip(url: videoURL).trimmed(to: 0...10)
    }
    .preset(.cinema)  // 1920×1080
    // Crop to a 9:16 portrait region centered on the canvas
    .crop(at: .center, size: .normalized(width: 0.5, height: 1.0))
    .export(to: outputURL)
}

// MARK: - 4. Sugar — title sequence + background music

/// Vlog-style intro: title card, fade-through-black into the clip, music underneath.
@available(iOS 16, macOS 13, *)
func v030SugarShowcase() async throws {
    let clipURL = URL(fileURLWithPath: "/tmp/vlog.mov")
    let musicURL = URL(fileURLWithPath: "/tmp/lofi.mp3")
    let outputURL = URL(fileURLWithPath: "/tmp/v030_sugar.mp4")

    _ = try await Video {
        TitleSequence("EPISODE 1",
                      duration: 2.5,
                      style: TextStyle(fontSize: 120, color: .white, alignment: .center, weight: .bold),
                      background: .black)
        Transition.fade(duration: 0.4)
        VideoClip(url: clipURL).trimmed(to: 0...30)
    }
    // Background music with sensible defaults — 60% volume, fades, ducks to 30% under clip audio
    .backgroundMusic(url: musicURL)
    .export(to: outputURL)
}

// MARK: - 5. The whole story — every v0.3 feature in one composition

/// Title card, color-graded slow-mo, dissolve, captions, watermark, square crop, music.
@available(iOS 16, macOS 13, *)
func v030EverythingShowcase() async throws {
    let introURL = URL(fileURLWithPath: "/tmp/intro.mov")
    let actionURL = URL(fileURLWithPath: "/tmp/action.mov")
    let outroURL = URL(fileURLWithPath: "/tmp/outro.mov")
    let logoImage = PlatformImage()
    let stickerImage = PlatformImage()
    let musicURL = URL(fileURLWithPath: "/tmp/score.mp3")
    let outputURL = URL(fileURLWithPath: "/tmp/v030_everything.mp4")

    _ = try await Video {
        TitleSequence("HIGHLIGHT REEL",
                      duration: 2.0,
                      style: TextStyle(fontSize: 96, color: .white, alignment: .center, weight: .bold))

        Transition.dissolve(duration: 0.5)

        VideoClip(url: introURL).trimmed(to: 0...4)
            .filter(.brightness(0.03), .contrast(1.1))

        Transition.slide(direction: .fromRight, duration: 0.4)

        // Slow-mo action with a different color grade
        VideoClip(url: actionURL).trimmed(to: 0...3).speed(0.5)
            .filter(.saturation(1.4), .exposure(0.2))

        Transition.dissolve(duration: 0.5)

        VideoClip(url: outroURL).trimmed(to: 0...3).filter(.mono)
    }
    // Persistent caption + corner sticker + watermark
    .overlay(
        TextOverlay("KADR DEMO",
                    style: TextStyle(fontSize: 36, color: .white, alignment: .center, weight: .medium))
            .position(.top)
            .anchor(.top)
            .size(.normalized(width: 1.0, height: 0.08))
    )
    .overlay(
        StickerOverlay(stickerImage)
            .position(.bottomLeft)
            .anchor(.bottomLeft)
            .size(.normalized(width: 0.15, height: 0.15))
            .rotation(degrees: 8)
            .shadow(radius: 10, offset: CGSize(width: 0, height: 6))
    )
    .watermark(logoImage, position: .topRight, opacity: 0.5)
    // Reframe to a square crop centered on the canvas
    .crop(at: .center, size: .normalized(width: 0.9, height: 0.9))
    // Background music with defaults
    .backgroundMusic(url: musicURL)
    .preset(.cinema)
    .export(to: outputURL)
}

// MARK: - 6. Timecode — formatting CMTime for UI

/// Demonstrates Timecode round-trip for displaying current playback position in a UI.
@available(iOS 16, macOS 13, *)
func v030TimecodeShowcase() {
    let tc = Timecode(fps: .fps30)

    // Format an arbitrary CMTime for display
    let position = CMTime(seconds: 65.5, preferredTimescale: 600)
    let display = tc.format(position)
    _ = display  // "00:01:05:15"

    // Parse a user-entered timecode back to CMTime — useful for seek input fields
    if let seekTime = tc.parse("00:02:30:00") {
        _ = seekTime  // CMTime(value: 4500, timescale: 30) — exactly 2:30
    }

    // Different frame rates for cinema vs broadcast
    let cinemaTC = Timecode(fps: .fps24)
    let broadcastTC = Timecode(fps: .fps30)
    _ = cinemaTC.format(position)     // "00:01:05:12"
    _ = broadcastTC.format(position)  // "00:01:05:15"
}
