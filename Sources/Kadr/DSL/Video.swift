import Foundation
import CoreMedia

/// A composition of clips, optional background audio, and an export preset.
///
/// Build a `Video` with the result-builder DSL, then chain modifiers and call
/// ``export(to:)`` to produce an `mp4` on disk:
///
/// ```swift
/// let url = try await Video {
///     VideoClip(url: introURL).trimmed(to: 0...3)
///     Transition.dissolve(duration: 0.5)
///     VideoClip(url: outroURL).trimmed(to: 0...3)
/// }
/// .audio { AudioTrack(url: musicURL).volume(0.8).ducking(0.3) }
/// .preset(.reelsAndShorts)
/// .export(to: outputURL)
/// ```
public struct Video: Sendable {
    /// The ordered clips that make up this composition, including any ``Transition`` markers
    /// between media clips. Iterate to inspect the timeline (e.g. for a custom timeline UI).
    public let clips: [any Clip]

    /// Background audio tracks added via ``audio(_:)`` or ``audio(url:)``. Drawn over the
    /// composition's full duration, mixed with each clip's own audio.
    public let audioTracks: [AudioTrack]

    /// The export preset (resolution / frame rate / codec). Defaults to ``Preset/auto``.
    public let preset: Preset

    /// Overlays drawn on top of the composition for its full duration, in declaration order
    /// (later entries render above earlier ones). Each overlay carries an optional
    /// ``LayerID`` that callers can use for hit-testing in custom UI.
    public let overlays: [any Overlay]

    /// The active crop region, or `nil` if no crop is applied. Set via ``crop(at:size:anchor:)``.
    public let crop: CropRegion?

    /// Build a `Video` from a result-builder block of clips.
    public init(@VideoBuilder _ content: () -> [any Clip]) {
        self.clips = content()
        self.audioTracks = []
        self.preset = .auto
        self.overlays = []
        self.crop = nil
    }

    internal init(clips: [any Clip], audioTracks: [AudioTrack], preset: Preset, overlays: [any Overlay] = [], crop: CropRegion? = nil) {
        self.clips = clips
        self.audioTracks = audioTracks
        self.preset = preset
        self.overlays = overlays
        self.crop = crop
    }

    /// Add one or more background audio tracks via the ``AudioBuilder`` DSL.
    /// Useful for chained modifiers like `.volume(_:)`, `.fadeIn(_:)`, `.ducking(_:)`.
    public func audio(@AudioBuilder _ tracks: () -> [AudioTrack]) -> Video {
        Video(clips: clips, audioTracks: audioTracks + tracks(), preset: preset, overlays: overlays, crop: crop)
    }

    /// Convenience: add a single background audio track from `url`. Equivalent to
    /// `.audio { AudioTrack(url: url) }` with default volume and no fades.
    public func audio(url: URL) -> Video {
        Video(clips: clips, audioTracks: audioTracks + [AudioTrack(url: url)], preset: preset, overlays: overlays, crop: crop)
    }

    /// Apply an export preset (resolution, frame rate, codec). Defaults to ``Preset/auto`` if
    /// unset. See ``Preset`` for the built-in choices and ``Preset/custom(width:height:frameRate:codec:)``.
    public func preset(_ preset: Preset) -> Video {
        Video(clips: clips, audioTracks: audioTracks, preset: preset, overlays: overlays, crop: crop)
    }

    /// Add an overlay drawn on top of the composition for its full duration.
    /// Accepts any ``Overlay`` conformer — currently ``ImageOverlay`` and ``TextOverlay``.
    /// Each overlay is drawn above the previous one in declaration order.
    public func overlay<O: Overlay>(_ overlay: O) -> Video {
        Video(clips: clips, audioTracks: audioTracks, preset: preset, overlays: overlays + [overlay], crop: crop)
    }

    /// Crop the composition to a rectangular region of the render canvas. The export's
    /// resolution becomes the crop's resolved size (not the preset's full resolution).
    ///
    /// `position` is where the crop's `anchor` point lands on the render canvas, using
    /// the same render-space coordinates as overlays. Default `anchor` is `.center` so
    /// the most common case — "crop to the middle X%" — reads naturally:
    ///
    /// ```swift
    /// // Crop to the center 80% of the render canvas
    /// .crop(at: .center, size: .normalized(width: 0.8, height: 0.8))
    ///
    /// // Crop to the bottom-right quarter
    /// .crop(at: .bottomRight, size: .normalized(width: 0.5, height: 0.5), anchor: .bottomRight)
    ///
    /// // Crop to a specific pixel rectangle
    /// .crop(at: .pixels(x: 100, y: 200),
    ///       size: .pixels(width: 800, height: 1000),
    ///       anchor: .topLeft)
    /// ```
    ///
    /// Overlays are positioned in the cropped (post-crop) render space, so a watermark
    /// at `.bottomRight` lands at the bottom-right of the cropped output.
    ///
    /// Only one crop region per `Video`. Calling `.crop(...)` again replaces the previous one.
    ///
    /// > Future: per-clip cropping (`VideoClip.crop(...)`) and alpha-mask cropping (any
    /// > shape, not just rectangles) are tracked for **v0.5** alongside custom compositors.
    public func crop(at position: Position, size: Size, anchor: Anchor = .center) -> Video {
        Video(
            clips: clips,
            audioTracks: audioTracks,
            preset: preset,
            overlays: overlays,
            crop: CropRegion(position: position, size: size, anchor: anchor)
        )
    }

    /// The total media-timeline duration of the composition.
    ///
    /// Sum of each clip's `Clip/duration`, post-speed and post-trim. For an
    /// untrimmed `VideoClip` the contribution is `CMTime.zero` because the asset
    /// hasn't been loaded yet — use ``VideoClip/metadata`` for the asset's true duration.
    public var duration: CMTime {
        clips.reduce(CMTime.zero) { result, clip in
            CMTimeAdd(result, clip.duration)
        }
    }

    /// Export this composition to `url` as an `mp4`. Throws ``KadrError`` on validation
    /// or export failure. Use ``exporter(to:)`` instead if you need progress reporting,
    /// time estimation, or cancellation.
    public func export(to url: URL) async throws -> URL {
        guard !clips.isEmpty else {
            throw KadrError.noClipsProvided
        }

        // Fast path: single ImageClip with no overlays and no crop. Both require the
        // full CompositionBuilder + ExportEngine path (overlays need an
        // AVVideoCompositionCoreAnimationTool; crop needs a videoComposition with
        // adjusted renderSize and offset transforms).
        if clips.count == 1, let imageClip = clips.first as? ImageClip, overlays.isEmpty, crop == nil {
            let audioURL = imageClip.audioURL ?? audioTracks.first?.url
            return try await ImageEncoder.encode(
                image: imageClip.image,
                duration: imageClip.duration,
                preset: preset,
                audioURL: audioURL,
                to: url
            )
        }

        // Multi-clip path: CompositionBuilder → ExportEngine
        let result = try await CompositionBuilder.build(
            from: clips,
            audioTracks: audioTracks,
            preset: preset,
            cropRect: crop?.resolved(in: preset.resolution)
        )

        let stream = ExportEngine.export(
            composition: result.composition,
            audioMix: result.audioMix,
            videoComposition: result.videoComposition,
            overlays: overlays,
            crop: crop,
            preset: preset,
            to: url
        )

        // Consume the stream to completion
        for try await _ in stream {}

        return url
    }

    /// Build an ``Exporter`` for this composition. Use the exporter when you need
    /// progress reporting via `AsyncThrowingStream<ExportProgress, Error>`,
    /// estimated time remaining, or cancellation. Otherwise prefer ``export(to:)``.
    public func exporter(to url: URL) -> Exporter {
        Exporter(clips: clips, audioTracks: audioTracks, preset: preset, overlays: overlays, crop: crop, outputURL: url)
    }
}
