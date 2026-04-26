import Kadr
import Foundation
import CoreMedia
import AVFoundation
import CoreGraphics

/// v0.4.0 showcase — composition introspection, preview primitives, and layout helpers.
///
/// Each function below is a self-contained recipe. Most v0.4 features are designed
/// for *consumers* of a `Video` (a custom UI layer like `kadr-ui`) rather than the DSL
/// itself, so these examples lean toward read paths and AVKit integration rather than
/// new authoring sugar.

// MARK: - 1. Introspection — iterate clips and overlays for a custom timeline

/// Walks a composition's structure to print a textual timeline. The same pattern
/// drives a visual `TimelineView`: clips become blocks, transitions become glyphs,
/// audio tracks become lanes.
@available(iOS 16, macOS 13, *)
func v040IntrospectionTimeline(_ video: Video) {
    print("Composition · \(video.preset.resolution.width)x\(video.preset.resolution.height) @ \(video.preset.frameRate)fps")
    for (index, clip) in video.clips.enumerated() {
        switch clip {
        case let videoClip as VideoClip:
            let trim = videoClip.trimRange.map { "trimmed \(CMTimeGetSeconds($0.start))s..\(CMTimeGetSeconds($0.end))s" } ?? "full"
            print("  [\(index)] VideoClip · \(trim) · speed \(videoClip.speedRate)x · filters \(videoClip.filters.count) · muted \(videoClip.isMuted)")
        case let imageClip as ImageClip:
            print("  [\(index)] ImageClip · \(CMTimeGetSeconds(imageClip.duration))s")
        case let transition as Transition:
            print("  [\(index)] Transition · \(CMTimeGetSeconds(transition.duration))s")
        default:
            print("  [\(index)] \(type(of: clip))")
        }
    }
    for track in video.audioTracks {
        print("  Audio · vol \(track.volumeLevel) · ducking \(track.duckingLevel.map(String.init(describing:)) ?? "off")")
    }
    for overlay in video.overlays {
        print("  Overlay · id=\(overlay.layerID?.rawValue ?? "<none>")")
    }
}

// MARK: - 2. Preview — drop a Video into AVKit.VideoPlayer

/// Builds an `AVPlayer` ready to mount in a SwiftUI `VideoPlayer` view. The player
/// item carries the composition's videoComposition + audioMix so playback matches
/// what `.export(to:)` would write — except for overlays, which are rendered by the
/// SwiftUI layer above the player (see ``v040OverlayHitTesting`` below).
@available(iOS 16, macOS 13, *)
@MainActor
func v040PreviewPlayer(for video: Video) async throws -> AVPlayer {
    let item = try await video.makePlayerItem()
    return AVPlayer(playerItem: item)
}

// MARK: - 3. Thumbnails — composition-level frame rendering

/// Generates a thumbnail strip at evenly spaced times. Each frame honors crop and
/// preset resolution, so the strip aligns visually with the eventual export.
@available(iOS 16, macOS 13, *)
func v040ThumbnailStrip(for video: Video, count: Int) async throws -> [PlatformImage] {
    let total = CMTimeGetSeconds(video.duration)
    guard total > 0, count > 0 else { return [] }
    let step = total / Double(count)
    var images: [PlatformImage] = []
    for i in 0..<count {
        let t = step * Double(i)
        images.append(try await video.thumbnail(at: t))
    }
    return images
}

// MARK: - 4. Layout — pixel-exact hit-testing

/// Maps a tap point in a UI canvas back to an overlay's `LayerID`. Uses the same
/// math the engine uses to lay out overlays, so the hit-region perfectly matches
/// what the user sees in the exported file.
///
/// The pattern: scale the tap point from the UI canvas size into the engine's
/// render-canvas coordinates, then check each overlay's resolved frame.
@available(iOS 16, macOS 13, *)
func v040HitTest(_ tap: CGPoint, in uiCanvas: CGSize, video: Video) -> LayerID? {
    let renderSize = video.preset.resolution
    // Map UI tap → render canvas
    let renderPoint = CGPoint(
        x: tap.x * (renderSize.width / uiCanvas.width),
        y: tap.y * (renderSize.height / uiCanvas.height)
    )
    // Search top-down: later overlays render above earlier ones.
    for overlay in video.overlays.reversed() {
        let frame = Layout.resolveFrame(
            position: overlay.position,
            size: overlay.size ?? .normalized(width: 1, height: 1),
            anchor: overlay.anchor,
            in: renderSize
        )
        if frame.contains(renderPoint) {
            return overlay.layerID
        }
    }
    return nil
}

// MARK: - 5. End-to-end — a tiny "preview before export" flow

/// The canonical v0.4 flow: build a Video, hand its `AVPlayerItem` to a SwiftUI
/// preview, then export the same composition to disk. The preview and the file
/// share the same clip layout, transitions, crop, and audio mix.
@available(iOS 16, macOS 13, *)
@MainActor
func v040PreviewThenExport() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v040_export.mp4")

    let video = Video {
        VideoClip(url: videoURL).trimmed(to: 0...5)
    }
    .crop(at: .center, size: .normalized(width: 0.9, height: 0.9))
    .preset(.reelsAndShorts)

    // Preview path — no file written, no overlays baked in (consumer renders them).
    let previewItem = try await video.makePlayerItem()
    let player = AVPlayer(playerItem: previewItem)
    _ = player

    // Export path — writes the mp4 with overlays baked in (none here).
    _ = try await video.export(to: outputURL)
}
