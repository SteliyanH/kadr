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
    internal let clips: [any Clip]
    internal let audioTracks: [AudioTrack]
    internal let preset: Preset
    internal let overlays: [any Overlay]

    /// Build a `Video` from a result-builder block of clips.
    public init(@VideoBuilder _ content: () -> [any Clip]) {
        self.clips = content()
        self.audioTracks = []
        self.preset = .auto
        self.overlays = []
    }

    internal init(clips: [any Clip], audioTracks: [AudioTrack], preset: Preset, overlays: [any Overlay] = []) {
        self.clips = clips
        self.audioTracks = audioTracks
        self.preset = preset
        self.overlays = overlays
    }

    /// Add one or more background audio tracks via the ``AudioBuilder`` DSL.
    /// Useful for chained modifiers like `.volume(_:)`, `.fadeIn(_:)`, `.ducking(_:)`.
    public func audio(@AudioBuilder _ tracks: () -> [AudioTrack]) -> Video {
        Video(clips: clips, audioTracks: audioTracks + tracks(), preset: preset, overlays: overlays)
    }

    /// Convenience: add a single background audio track from `url`. Equivalent to
    /// `.audio { AudioTrack(url: url) }` with default volume and no fades.
    public func audio(url: URL) -> Video {
        Video(clips: clips, audioTracks: audioTracks + [AudioTrack(url: url)], preset: preset, overlays: overlays)
    }

    /// Apply an export preset (resolution, frame rate, codec). Defaults to ``Preset/auto`` if
    /// unset. See ``Preset`` for the built-in choices and ``Preset/custom(width:height:frameRate:codec:)``.
    public func preset(_ preset: Preset) -> Video {
        Video(clips: clips, audioTracks: audioTracks, preset: preset, overlays: overlays)
    }

    /// Add an overlay drawn on top of the composition for its full duration.
    /// Accepts any ``Overlay`` conformer — currently ``ImageOverlay`` and ``TextOverlay``.
    /// Each overlay is drawn above the previous one in declaration order.
    public func overlay<O: Overlay>(_ overlay: O) -> Video {
        Video(clips: clips, audioTracks: audioTracks, preset: preset, overlays: overlays + [overlay])
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

        // Fast path: single ImageClip with no overlays. Overlays require the full
        // CompositionBuilder + ExportEngine path because they need an
        // AVVideoCompositionCoreAnimationTool wired into a videoComposition.
        if clips.count == 1, let imageClip = clips.first as? ImageClip, overlays.isEmpty {
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
            preset: preset
        )

        let stream = ExportEngine.export(
            composition: result.composition,
            audioMix: result.audioMix,
            videoComposition: result.videoComposition,
            overlays: overlays,
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
        Exporter(clips: clips, audioTracks: audioTracks, preset: preset, overlays: overlays, outputURL: url)
    }
}
