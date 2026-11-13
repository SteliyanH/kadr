import AVFoundation
import CoreMedia

/// The triplet of AVFoundation objects needed to play, scrub, or export a `Video`.
///
/// Wraps non-`Sendable` AVFoundation types for safe transfer across concurrency boundaries.
/// Only accessed within a single Task body — no concurrent access occurs.
internal struct PlaybackComposition: @unchecked Sendable {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition?
    let audioMix: AVMutableAudioMix?
}

/// Builds an AVFoundation playback composition (asset + videoComposition + audioMix)
/// suitable for `AVPlayerItem`, `AVAssetImageGenerator`, or further export.
///
/// Shared between the export path (`ExportEngine`) and the public preview API
/// (`Video.makePlayerItem()` / `Video.thumbnail(at:)`) so both use identical clip
/// layout, transitions, crop, and audio math — no drift between what plays back
/// and what the engine writes to disk.
///
/// **Overlays are intentionally not baked in here.** AVFoundation's
/// `AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer:in:)` is export-only
/// and throws `NSInternalInconsistencyException` when attached to a videoComposition
/// used for playback or image generation. The export path attaches the tool itself
/// after calling `compose(video:)`. Preview consumers (e.g. kadr-ui) render overlays
/// as SwiftUI views layered over the player using ``Layout/resolveFrame(position:size:anchor:in:)``.
internal enum PlaybackComposer {

    static func compose(video: Video) async throws -> PlaybackComposition {
        guard !video.clips.isEmpty else {
            throw KadrError.noClipsProvided
        }

        let cropRect = video.crop?.resolved(in: video.preset.resolution)

        let result = try await CompositionBuilder.build(
            from: video.clips,
            audioTracks: video.audioTracks,
            preset: video.preset,
            cropRect: cropRect,
            multiInputCompositor: video.multiInputCompositor,
            compositorWindow: video.compositorWindow
        )

        // Simple path: CompositionBuilder doesn't build a videoComposition when there are
        // no transitions. Build one ourselves so preview/export honors preset resolution
        // + frame rate (and crop, if set).
        let videoComposition = result.videoComposition ?? buildSimpleVideoComposition(
            for: result.composition,
            preset: video.preset,
            cropRect: cropRect
        )

        return PlaybackComposition(
            composition: result.composition,
            videoComposition: videoComposition,
            audioMix: result.audioMix
        )
    }

    /// Builds an `AVMutableVideoComposition` that enforces the preset's resolution and
    /// frame rate for the no-transitions path. Mirrors the engine's layout math: scale to
    /// fill, center, then translate by `-cropOrigin` when cropped.
    ///
    /// Used by both `ExportEngine` (export pipeline) and `compose(video:)` (preview /
    /// thumbnail pipeline) so the videoComposition is identical across both consumers.
    static func buildSimpleVideoComposition(
        for composition: AVMutableComposition,
        preset: Preset,
        cropRect: CGRect? = nil,
        orientations: OrientationSchedule = .empty
    ) -> AVMutableVideoComposition? {
        let videoTracks = composition.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = cropRect?.size ?? preset.resolution
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))

        let cropOffset = cropRect?.origin ?? .zero
        let cropTransform = CGAffineTransform(translationX: -cropOffset.x, y: -cropOffset.y)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[0])

        // Scale to fill and center. With an orientation schedule, each source is first
        // turned upright and the layout is set again wherever the source changes, since
        // a portrait clip and a landscape clip can share this one track.
        let entries = orientations.entries(for: videoTracks[0].trackID)
        if !entries.isEmpty {
            var transforms = LayerTransformTimeline()
            for (index, entry) in entries.enumerated() {
                let base = entry.orientation.fill(preset.resolution) ?? .identity
                transforms.set(base.concatenating(cropTransform), at: index == 0 ? .zero : entry.range.start)
            }
            transforms.apply(to: layerInstruction)
        } else if let fill = OrientationSchedule.aspectFill(videoTracks[0].naturalSize, into: preset.resolution) {
            layerInstruction.setTransform(fill.concatenating(cropTransform), at: .zero)
        } else if cropRect != nil {
            layerInstruction.setTransform(cropTransform, at: .zero)
        }

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        return videoComposition
    }
}
