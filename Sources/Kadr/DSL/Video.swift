import Foundation
import CoreMedia
import CoreImage
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
    public internal(set) var clips: [any Clip]

    /// Background audio tracks added via ``audio(_:)`` or ``audio(url:)``. Drawn over the
    /// composition's full duration, mixed with each clip's own audio.
    public internal(set) var audioTracks: [AudioTrack]

    /// The export preset (resolution / frame rate / codec). Defaults to ``Preset/auto``.
    public internal(set) var preset: Preset

    /// Overlays drawn on top of the composition for its full duration, in declaration order
    /// (later entries render above earlier ones). Each overlay carries an optional
    /// ``LayerID`` that callers can use for hit-testing in custom UI.
    public internal(set) var overlays: [any Overlay]

    /// The active crop region, or `nil` if no crop is applied. Set via ``crop(at:size:anchor:)``.
    public internal(set) var crop: CropRegion?

    /// Optional multi-track blender. Set via ``compositor(_:)-(any)`` /
    /// ``compositor(_:)-(closure)``. `nil` (default) means the engine will use its
    /// built-in alpha-composite later-over-earlier blender when the composition has
    /// multiple parallel tracks.
    public internal(set) var multiInputCompositor: (any MultiInputCompositor)?

    /// Optional time window during which the ``multiInputCompositor`` is active. When
    /// `nil` (default), the compositor runs for the entire composition. When set, the
    /// engine consults each frame's composition time — inside the window the user's
    /// compositor runs; outside it, the default alpha-composite blender runs. Set via
    /// ``compositor(_:during:)-(CMTimeRange)`` / ``compositor(_:during:)-(closedrange)``.
    /// Added in v0.7.
    public internal(set) var compositorWindow: CMTimeRange?

    /// Caption cues attached to this composition. The engine bakes them as
    /// `AVMetadataItem` group at export. `nil` / empty (default) means no captions.
    /// Set via ``captions(_:)``. Added in v0.9.2.
    /// How many bits to spend on the export, independent of ``preset``. `.automatic`
    /// (the default) leaves it to the encoder, which is what every export did before
    /// v0.20. Set via ``quality(_:)``.
    public internal(set) var quality: ExportQuality

    public internal(set) var captions: [Caption]

    /// The total media-timeline duration of the composition.
    ///
    /// Sum of each clip's `Clip/duration`, post-speed and post-trim. For an
    /// untrimmed `VideoClip` the contribution is `CMTime.zero` because the asset
    /// hasn't been loaded yet — use ``VideoClip/metadata`` for the asset's true duration.
    ///
    /// Computed once at construction and stored (v0.13). `Video` is immutable, so the
    /// value is fully determined by `clips` at init time; storing it makes repeated reads
    /// (timeline UIs, the exporter, progress estimation) O(1) instead of re-walking the
    /// clip list on every access.
    public internal(set) var duration: CMTime

    /// Sum of each clip's media-timeline contribution. The single source of truth for
    /// ``duration``; both initializers route through it so the walk happens exactly once
    /// per `Video` construction.
    private static func totalDuration(of clips: [any Clip]) -> CMTime {
        clips.reduce(CMTime.zero) { CMTimeAdd($0, $1.duration) }
    }

    /// Build a `Video` from a result-builder block of clips.
    public init(@VideoBuilder _ content: () -> [any Clip]) {
        let clips = content()
        self.clips = clips
        self.audioTracks = []
        self.preset = .auto
        self.overlays = []
        self.crop = nil
        self.multiInputCompositor = nil
        self.compositorWindow = nil
        self.captions = []
        self.quality = .automatic
        self.duration = Self.totalDuration(of: clips)
    }

    internal init(
        clips: [any Clip],
        audioTracks: [AudioTrack],
        preset: Preset,
        overlays: [any Overlay] = [],
        crop: CropRegion? = nil,
        multiInputCompositor: (any MultiInputCompositor)? = nil,
        compositorWindow: CMTimeRange? = nil,
        captions: [Caption] = [],
        quality: ExportQuality = .automatic
    ) {
        self.clips = clips
        self.audioTracks = audioTracks
        self.preset = preset
        self.overlays = overlays
        self.crop = crop
        self.multiInputCompositor = multiInputCompositor
        self.compositorWindow = compositorWindow
        self.captions = captions
        self.quality = quality
        self.duration = Self.totalDuration(of: clips)
    }

    // MARK: - Copy-with

    /// A copy of this video with `mutate` applied.
    ///
    /// Same reasoning as `VideoClip.with(_:)`: every modifier here is a
    /// copy-with-one-change, and each used to re-invoke the memberwise initialiser
    /// by hand. Nine call sites, nine properties — and a missed argument dropped a
    /// property's value silently rather than failing to compile.
    ///
    /// `internal(set)` on the stored properties exists for this and nothing else.
    /// They stay read-only to every caller outside the module.
    func with(_ mutate: (inout Video) -> Void) -> Video {
        var copy = self
        mutate(&copy)
        return copy
    }

    /// Attach caption cues to this composition. The engine bakes them as `AVMetadataItem`
    /// group at export. Multiple `.captions(_:)` calls accumulate.
    ///
    /// File-format parsing (SRT, VTT, iTT) lives in the
    /// [`kadr-captions`](https://github.com/SteliyanH/kadr-captions) adapter; this
    /// modifier only takes pre-built ``Caption`` values. Added in v0.9.2.
    public func captions(_ captions: [Caption]) -> Video {
        with {
    $0.captions = self.captions + captions
}
    }

    /// Add one or more background audio tracks via the ``AudioBuilder`` DSL.
    /// Useful for chained modifiers like `.volume(_:)`, `.fadeIn(_:)`, `.ducking(_:)`.
    public func audio(@AudioBuilder _ tracks: () -> [AudioTrack]) -> Video {
        with { $0.audioTracks += tracks() }
    }

    /// Convenience: add a single background audio track from `url`. Equivalent to
    /// `.audio { AudioTrack(url: url) }` with default volume and no fades.
    public func audio(url: URL) -> Video {
        with { $0.audioTracks.append(AudioTrack(url: url)) }
    }

    /// Apply an export preset (resolution, frame rate, codec). Defaults to ``Preset/auto`` if
    /// unset. See ``Preset`` for the built-in choices and ``Preset/custom(width:height:frameRate:codec:)``.
    /// Set how many bits the export spends, independent of ``preset``.
    ///
    /// ``Preset`` decides the output's shape — dimensions, frame rate, codec.
    /// This decides how heavily it is compressed. A 1080×1920 reel can be a 12 MB
    /// upload or a 60 MB master at identical dimensions.
    ///
    /// ```swift
    /// video.quality(.bitrate(4_000_000))              // ~4 Mbps
    /// video.quality(.fileSize(bytes: 25_000_000))     // aim for under 25 MB
    /// ```
    ///
    /// `.automatic` (the default) leaves the choice to the encoder, which is what
    /// every export did before v0.20. Added in v0.20.
    public func quality(_ quality: ExportQuality) -> Video {
        with { $0.quality = quality }
    }

    public func preset(_ preset: Preset) -> Video {
        with { $0.preset = preset }
    }

    /// Add an overlay drawn on top of the composition for its full duration.
    /// Accepts any ``Overlay`` conformer — currently ``ImageOverlay`` and ``TextOverlay``.
    /// Each overlay is drawn above the previous one in declaration order.
    public func overlay<O: Overlay>(_ overlay: O) -> Video {
        with { $0.overlays.append(overlay) }
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
        with {
    $0.crop = CropRegion(position: position, size: size, anchor: anchor)
}
    }

    /// Attach a multi-track blender to this composition. The compositor is consulted
    /// at output time when more than one parallel track is active. With no compositor
    /// set (the default), the engine alpha-composites later-over-earlier.
    ///
    /// ```swift
    /// Video {
    ///     VideoClip(url: base).trimmed(to: 0...10)
    ///     VideoClip(url: overlay).trimmed(to: 0...10).at(time: 0)
    /// }
    /// .compositor(MultiplyBlend())
    /// ```
    ///
    /// Single-track compositions ignore the compositor entirely — the v0.5 fast-path
    /// pipeline doesn't engage it. See ``MultiInputCompositor``.
    public func compositor(_ compositor: any MultiInputCompositor) -> Video {
        with {
    $0.multiInputCompositor = compositor
}
    }

    /// Attach a closure-backed multi-track blender. Convenient for one-off blends:
    ///
    /// ```swift
    /// Video { ... }
    ///     .compositor { images, _ in
    ///         // Custom blend math
    ///         images.dropFirst().reduce(images.first ?? .empty()) { acc, layer in ... }
    ///     }
    /// ```
    public func compositor(_ body: @Sendable @escaping ([CIImage], CompositorContext) -> CIImage) -> Video {
        compositor(ClosureMultiInputCompositor(body: body))
    }

    /// Attach a multi-track blender that runs **only during** `range`. Outside the
    /// window the engine falls back to its built-in alpha-composite later-over-earlier
    /// blender. Frame-accurate — the active compositor is selected per frame at the
    /// composition-time level. Added in v0.7.
    ///
    /// ```swift
    /// Video { ... }
    ///     .compositor(MultiplyBlend(), during: CMTimeRange(start: t1, end: t2))
    /// ```
    public func compositor(_ compositor: any MultiInputCompositor, during range: CMTimeRange) -> Video {
        with {
    $0.multiInputCompositor = compositor
    $0.compositorWindow = range
}
    }

    /// Convenience overload accepting a `ClosedRange<TimeInterval>`. Added in v0.7.
    public func compositor(_ compositor: any MultiInputCompositor, during range: ClosedRange<TimeInterval>) -> Video {
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        return self.compositor(compositor, during: CMTimeRange(start: start, end: end))
    }

    /// Closure form of ``compositor(_:during:)-(CMTimeRange)``. Added in v0.7.
    public func compositor(during range: CMTimeRange, _ body: @Sendable @escaping ([CIImage], CompositorContext) -> CIImage) -> Video {
        compositor(ClosureMultiInputCompositor(body: body), during: range)
    }

    /// Closure form of ``compositor(_:during:)-(closedrange)``. Added in v0.7.
    public func compositor(during range: ClosedRange<TimeInterval>, _ body: @Sendable @escaping ([CIImage], CompositorContext) -> CIImage) -> Video {
        compositor(ClosureMultiInputCompositor(body: body), during: range)
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
        // `quality` disqualifies the fast path. ImageEncoder writes with its own
        // settings and cannot honour a bitrate, so taking this route with a bitrate
        // requested would ignore it silently — the user asked for 1 Mbps and got
        // whatever the encoder felt like, with nothing to indicate the request was
        // dropped. Found by a benchmark whose writer-path numbers came back
        // identical to the session path, because it was never leaving this branch.
        if clips.count == 1, let imageClip = clips.first as? ImageClip, overlays.isEmpty, crop == nil,
           quality == .automatic {
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
            cropRect: crop?.resolved(in: preset.resolution),
            multiInputCompositor: multiInputCompositor,
            compositorWindow: compositorWindow
        )

        let stream = ExportEngine.export(
            composition: result.composition,
            audioMix: result.audioMix,
            videoComposition: result.videoComposition,
            overlays: overlays,
            crop: crop,
            preset: preset,
            captions: captions,
            quality: quality,
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
        Exporter(clips: clips, audioTracks: audioTracks, preset: preset, overlays: overlays, crop: crop, multiInputCompositor: multiInputCompositor, compositorWindow: compositorWindow, captions: captions, quality: quality, outputURL: url)
    }

    // MARK: - Preview

    /// Build an `AVPlayerItem` ready for playback in `AVPlayer` / `AVKit.VideoPlayer`.
    ///
    /// The returned item has the composition's video composition (preset resolution +
    /// frame rate, crop, transitions) and audio mix (background music, fades, ducking)
    /// pre-attached, so video frames and audio match what ``export(to:)`` writes to disk.
    ///
    /// > **Overlays are not baked in.** AVFoundation's
    /// > `AVVideoCompositionCoreAnimationTool` is export-only and crashes when attached
    /// > to a playback `videoComposition`. Render overlays separately as views layered
    /// > over the player, using ``Layout/resolveFrame(position:size:anchor:in:)`` to
    /// > place each one in the same coordinates the engine renders to. The exported
    /// > file still contains the overlays — only the *preview* surface excludes them.
    ///
    /// ```swift
    /// import SwiftUI
    /// import AVKit
    /// import Kadr
    ///
    /// struct PreviewScreen: View {
    ///     let video: Video
    ///     @State private var player: AVPlayer?
    ///
    ///     var body: some View {
    ///         VideoPlayer(player: player)
    ///             .task {
    ///                 let item = try? await video.makePlayerItem()
    ///                 player = item.map(AVPlayer.init(playerItem:))
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// Each call returns a fresh `AVPlayerItem` because `AVPlayerItem` carries playback
    /// state and the embedded `AVVideoCompositionCoreAnimationTool` cannot be shared.
    ///
    /// - Throws: ``KadrError/noClipsProvided`` if the composition has no clips, or any
    ///   error surfaced by the underlying composition build.
    ///
    /// > MainActor: this method is `@MainActor` because `AVPlayerItem` requires main-thread
    /// > construction under Swift 6 strict concurrency. The expensive composition build
    /// > (`PlaybackComposer.compose`) is awaited normally and hops off-main while running.
    @MainActor
    public func makePlayerItem() async throws -> AVPlayerItem {
        let playback = try await PlaybackComposer.compose(video: self)
        let item = AVPlayerItem(asset: playback.composition)
        item.videoComposition = playback.videoComposition
        item.audioMix = playback.audioMix
        return item
    }

    /// Render a single frame of the composition at `time` for use as a thumbnail.
    ///
    /// Honors clip layout, transitions, crop, and preset resolution — same as
    /// ``makePlayerItem()``. **Overlays are not baked in** for the same reason: the
    /// underlying `AVAssetImageGenerator` shares the playback path's videoComposition
    /// constraints. Compose overlays on top of the returned image manually if needed.
    ///
    /// - Parameter time: Composition time of the frame to render.
    /// - Returns: A `UIImage` on iOS / tvOS / visionOS, `NSImage` on macOS.
    /// - Throws: ``KadrError/noClipsProvided`` or the underlying image-generation error.
    public func thumbnail(at time: CMTime) async throws -> PlatformImage {
        // Delegates to the reusable generator (v0.14): one code path, identical
        // configuration / output. For many frames (scrubbing, filmstrips) build a
        // ``ThumbnailGenerator`` once via ``thumbnailGenerator()`` and reuse it instead
        // of paying composition + generator setup per call.
        try await thumbnailGenerator().thumbnail(at: time)
    }

    /// Compose this video once and return a reusable ``ThumbnailGenerator`` for
    /// scrubbing or building a filmstrip.
    ///
    /// The generator holds a single `AVAssetImageGenerator` over the composed asset, so
    /// repeated ``ThumbnailGenerator/thumbnail(at:)-(CMTime)`` calls — or a batch
    /// ``ThumbnailGenerator/thumbnails(at:)`` stream — don't re-run composition or
    /// re-allocate the generator. Prefer this over calling ``thumbnail(at:)-(CMTime)`` in
    /// a loop. Frames honor crop / transitions / preset resolution but **exclude
    /// overlays**, same as ``thumbnail(at:)-(CMTime)``. Added in v0.14.
    ///
    /// - Throws: ``KadrError/noClipsProvided`` if the composition has no clips, or any
    ///   error surfaced by the underlying composition build.
    public func thumbnailGenerator() async throws -> ThumbnailGenerator {
        let playback = try await PlaybackComposer.compose(video: self)
        return ThumbnailGenerator(playback: playback)
    }

    /// Render a single frame of the composition at `time` (seconds) for use as a thumbnail.
    /// Convenience overload of ``thumbnail(at:)-(CMTime)``.
    public func thumbnail(at time: TimeInterval) async throws -> PlatformImage {
        try await thumbnail(at: CMTime(seconds: time, preferredTimescale: 600))
    }
}
