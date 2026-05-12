import Foundation
import CoreMedia
import CoreImage
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Asset-level information about a `VideoClip`'s source file. Read via
/// ``VideoClip/metadata``.
public struct VideoClipMetadata: Sendable {
    /// Total duration of the source asset (before any trim or speed adjustment).
    public let duration: CMTime
    /// Native resolution of the source video track, in pixels.
    public let resolution: CGSize
    /// Nominal frame rate reported by the source video track, in frames per second.
    public let frameRate: Double
    /// `true` if the source asset contains at least one audio track.
    public let hasAudio: Bool
}

/// A clip backed by a video file at a `URL`. Apply modifiers to trim, reverse, mute,
/// replace audio, or change playback speed.
///
/// ```swift
/// VideoClip(url: clipURL)
///     .trimmed(to: 0...10)
///     .speed(0.5)            // half-speed slow-mo
///     .muted()
/// ```
///
/// Time-related modifiers like ``trimmed(to:)-(CMTimeRange)`` and ``thumbnail(at:)-(CMTime)``
/// accept both `CMTime` (frame-accurate) and `TimeInterval` (ergonomic) forms.
public struct VideoClip: Clip, Sendable {
    /// File URL of the source video.
    public let url: URL

    /// The active trim range in source-asset time, or `nil` if the full asset is used.
    /// Set via ``trimmed(to:)`` (CMTimeRange or ClosedRange<TimeInterval>).
    public let trimRange: CMTimeRange?

    /// `true` if the clip is played in reverse. Set via ``reversed()``.
    public let isReversed: Bool

    /// `true` if the source asset's audio is dropped from the timeline. Set via ``muted()``.
    public let isMuted: Bool

    /// External audio file replacing the source asset's audio, or `nil`. Set via ``withAudio(_:)``.
    public let replacementAudioURL: URL?

    /// Playback speed multiplier in `0.25...4.0`; `1.0` is real-time. Set via ``speed(_:)``.
    public let speedRate: Double

    /// Optional non-linear speed curve over clip-relative time. When set, takes precedence
    /// over ``speedRate`` — values in the animation are speed multipliers (1.0 = normal,
    /// 0.5 = half-speed, 2.0 = 2×). The engine integrates the curve into a piecewise-linear
    /// time map and applies via repeated `scaleTimeRange` segments. Composes with
    /// ``trimmed(to:)``: trim is applied first (selects the source range), then the speed
    /// curve maps that range to the timeline. Set via ``speed(curve:)``. Added in v0.9.
    public let speedCurve: Animation<Double>?

    /// Filters applied to this clip in declaration order. Set via ``filter(_:)``.
    public let filters: [Filter]

    /// Stable identifiers for each ``Filter`` slot, parallel to ``filters``.
    /// `filterIDs[i]` is the identity of `filters[i]`. Auto-generated on
    /// every ``filter(_:)`` call; preserved across modifier rebuilds.
    ///
    /// Use the keyed surface (``filterAnimation(for:)``,
    /// ``setFilter(for:_:)``, ``removeFilter(for:)``) to mutate filters and
    /// their animations without the parallel-index drift the v0.10.x API
    /// was exposed to. Added in v0.11.
    public let filterIDs: [FilterID]

    /// Optional clip-relative keyframe animations driving the primary scalar parameter
    /// of each filter. Parallel to ``filters`` — `filterAnimations[i]` (when non-nil)
    /// animates `filters[i]`'s primary scalar (brightness / contrast / saturation /
    /// exposure / sepia intensity). Filters without a primary scalar (.mono, .lut,
    /// .chromaKey) ignore the animation. Set via ``filter(_:animation:)``. Added in
    /// v0.8.2.
    ///
    /// **Index-based access is discouraged as of v0.11.** Prefer
    /// ``filterAnimation(for:)`` keyed by ``FilterID``, which preserves the
    /// animation across filter rebuilds. The index-based surface stays for
    /// back-compat.
    public let filterAnimations: [Animation<Double>?]

    /// User-supplied compositors applied to this clip in declaration order, after
    /// ``filters``. Set via ``compositor(_:)-(any)`` or ``compositor(_:)-(closure)``.
    public let compositors: [any Compositor]

    /// Stable identifier for addressing this clip across reorders or trims, set via
    /// ``id(_:)``. `nil` if no ID has been assigned.
    public let clipID: ClipID?

    /// Explicit composition start time for this clip, set via ``at(time:)-(CMTime)`` /
    /// ``at(time:)-(TimeInterval)``. `nil` (default) participates in the implicit chain.
    /// See ``Clip/startTime`` for the v0.6 surface contract.
    public let startTime: CMTime?

    /// Optional per-clip affine transform applied in the engine's render space. `nil`
    /// (default) leaves the clip's natural aspect-fill layout unchanged. Set via
    /// ``transform(_:)``. Added in v0.8.
    public let transform: Transform?

    /// Optional keyframe animation driving ``transform`` over the clip's lifetime. When
    /// set, the engine samples this animation per frame and overrides the static
    /// ``transform`` base for any time inside the animation's keyframes. Outside the
    /// animation range, the static base applies. Set via ``transform(_:animation:)``.
    /// Added in v0.8.
    public let transformAnimation: Animation<Transform>?

    /// Optional per-clip opacity in `0...1`. `nil` (default) means fully opaque (1.0)
    /// for compatibility with pre-v0.8 compositions. Set via ``opacity(_:)``. Added in v0.8.
    public let opacity: Double?

    /// Optional keyframe animation driving ``opacity`` over the clip's lifetime. Set
    /// via ``opacity(_:animation:)``. Added in v0.8.
    public let opacityAnimation: Animation<Double>?

    /// Timeline contribution after trim and speed are applied. Returns `CMTime.zero` when
    /// the clip hasn't been trimmed (the source asset's duration isn't known synchronously
    /// — call ``metadata`` for that).
    public var duration: CMTime {
        guard let trimRange else {
            // Synchronous fallback — actual duration requires async asset loading
            return .zero
        }
        // Speed curve takes precedence when set: integrate (1 / curve(t)) over the trim range.
        if let speedCurve {
            let outputSeconds = SpeedCurveSampler.integratedDuration(
                curve: speedCurve,
                sourceDuration: trimRange.duration
            )
            return CMTime(seconds: outputSeconds, preferredTimescale: 600)
        }
        // Apply speed: scaled duration = raw / speedRate
        if speedRate == 1.0 {
            return trimRange.duration
        }
        return CMTimeMultiplyByFloat64(trimRange.duration, multiplier: 1.0 / speedRate)
    }

    /// Asynchronously load the source asset's metadata: duration, native resolution,
    /// nominal frame rate, and whether it has audio. Throws `KadrError.invalidURL`
    /// if the asset has no video track.
    public var metadata: VideoClipMetadata {
        get async throws {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let videoTrack = tracks.first else {
                throw KadrError.invalidURL(url)
            }
            let size = try await videoTrack.load(.naturalSize)
            let frameRate = try await videoTrack.load(.nominalFrameRate)
            return VideoClipMetadata(
                duration: duration,
                resolution: size,
                frameRate: Double(frameRate),
                hasAudio: !audioTracks.isEmpty
            )
        }
    }

    /// Build a clip from a video file `URL`. Defaults: full duration, original audio,
    /// 1x speed, not reversed, not muted, no filters or compositors, no explicit start time.
    public init(url: URL) {
        self.url = url
        self.trimRange = nil
        self.isReversed = false
        self.isMuted = false
        self.replacementAudioURL = nil
        self.speedRate = 1.0
        self.speedCurve = nil
        self.filters = []
        self.filterIDs = []
        self.filterAnimations = []
        self.compositors = []
        self.clipID = nil
        self.startTime = nil
        self.transform = nil
        self.transformAnimation = nil
        self.opacity = nil
        self.opacityAnimation = nil
    }

    internal init(
        url: URL,
        trimRange: CMTimeRange?,
        isReversed: Bool,
        isMuted: Bool,
        replacementAudioURL: URL?,
        speedRate: Double = 1.0,
        filters: [Filter] = [],
        filterIDs: [FilterID] = [],
        filterAnimations: [Animation<Double>?] = [],
        compositors: [any Compositor] = [],
        clipID: ClipID? = nil,
        startTime: CMTime? = nil,
        transform: Transform? = nil,
        transformAnimation: Animation<Transform>? = nil,
        opacity: Double? = nil,
        opacityAnimation: Animation<Double>? = nil,
        speedCurve: Animation<Double>? = nil
    ) {
        self.url = url
        self.trimRange = trimRange
        self.isReversed = isReversed
        self.isMuted = isMuted
        self.replacementAudioURL = replacementAudioURL
        self.speedRate = speedRate
        self.speedCurve = speedCurve
        self.filters = filters
        // v0.11: filterIDs parallels filters. If the caller supplies a
        // matching-length array, use it verbatim (preserves identity across
        // modifier rebuilds). Otherwise generate fresh ids — happens when
        // the public .filter(_:) modifier appends without threading the id
        // through, or in tests passing only filters.
        if filterIDs.count == filters.count {
            self.filterIDs = filterIDs
        } else {
            self.filterIDs = filters.map { _ in FilterID.generate() }
        }
        // Always keep filterAnimations parallel to filters (pad with nils if caller
        // passed a shorter array — defensive against modifier-call bugs in tests).
        if filterAnimations.count == filters.count {
            self.filterAnimations = filterAnimations
        } else {
            self.filterAnimations = Array(repeating: nil, count: filters.count)
        }
        self.compositors = compositors
        self.clipID = clipID
        self.startTime = startTime
        self.transform = transform
        self.transformAnimation = transformAnimation
        self.opacity = opacity
        self.opacityAnimation = opacityAnimation
    }

    /// Trim with a `CMTimeRange` for frame-accurate precision.
    public func trimmed(to range: CMTimeRange) -> VideoClip {
        VideoClip(url: url, trimRange: range, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Trim with a `ClosedRange<TimeInterval>`. Convenience overload — converts to `CMTimeRange`
    /// at timescale 600. For frame-accurate trims at a specific frame rate, prefer
    /// `trimmed(to:)` with a `CMTimeRange`.
    public func trimmed(to range: ClosedRange<TimeInterval>) -> VideoClip {
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        return trimmed(to: CMTimeRange(start: start, duration: CMTimeSubtract(end, start)))
    }

    /// Play this clip backwards. The source is pre-processed via a temporary file before
    /// composition; for very long clips this can be memory-intensive.
    public func reversed() -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: true, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Drop the source's audio track from the composition. Use ``withAudio(_:)`` to also
    /// substitute a different audio file.
    public func muted() -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: true, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Apply one or more ``Filter``s to this clip. Filters are pre-rendered to a
    /// temporary file before composition (one extra encode/decode pass per call site
    /// — see ``Filter`` for the available presets and parameter ranges).
    ///
    /// Multiple `.filter(_:)` calls accumulate; you can also pass several filters in
    /// one call. Order matters: filters are applied left-to-right, top-to-bottom.
    ///
    /// ```swift
    /// .filter(.brightness(0.1))
    ///     .filter(.contrast(1.2))            // chained — same as below
    ///
    /// .filter(.brightness(0.1), .contrast(1.2))   // single call
    /// ```
    public func filter(_ filters: Filter...) -> VideoClip {
        VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: speedRate,
            filters: self.filters + filters,
            filterAnimations: self.filterAnimations + Array(repeating: nil, count: filters.count),
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: opacityAnimation,
            speedCurve: speedCurve
        )
    }

    /// Apply a single ``Filter`` with a clip-relative keyframe animation driving the
    /// filter's primary scalar parameter. Animation timing is **clip-relative** —
    /// `.at(0.0, ...)` maps to the clip's first frame (after trim, before speed scaling).
    /// Filters without a primary scalar (.mono, .lut, .chromaKey) ignore the animation
    /// at engine evaluation; the static filter applies as if no animation were set.
    /// Added in v0.8.2.
    ///
    /// ```swift
    /// // Sepia fades in over the first 2 seconds
    /// VideoClip(url: clipURL).trimmed(to: 0...5)
    ///     .filter(.sepia(intensity: 0), animation: .keyframes([
    ///         .at(0.0, value: 0),
    ///         .at(2.0, value: 1.0),
    ///     ]))
    /// ```
    public func filter(_ filter: Filter, animation: Animation<Double>) -> VideoClip {
        VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: speedRate,
            filters: filters + [filter],
            filterAnimations: filterAnimations + [animation],
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: opacityAnimation,
            speedCurve: speedCurve
        )
    }

    /// Replace the source's audio with the audio from `audioURL` (mutes the original).
    /// If the replacement audio is longer than the clip, it is truncated; if shorter, it
    /// is not looped.
    public func withAudio(_ audioURL: URL) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: true, replacementAudioURL: audioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Assign a stable identifier so callers can address this clip by ID across reorders
    /// or trims. See ``ClipID`` for guidelines on choosing IDs.
    public func id(_ id: ClipID) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: id, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Pin this clip to an explicit composition start time. The clip opts out of the
    /// implicit linear chain and becomes a free-floating parallel track anchored at
    /// `time` on the composition's timeline.
    ///
    /// ```swift
    /// Video {
    ///     VideoClip(url: main).trimmed(to: 0...10)
    ///     VideoClip(url: pip).trimmed(to: 0...3).at(time: CMTime(seconds: 2, preferredTimescale: 600))
    /// }
    /// ```
    ///
    public func at(time: CMTime) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: clipID, startTime: time, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Pin this clip to an explicit composition start time, in seconds. Convenience
    /// overload of ``at(time:)-(CMTime)``.
    public func at(time: TimeInterval) -> VideoClip {
        at(time: CMTime(seconds: time, preferredTimescale: 600))
    }

    /// Apply a per-clip affine transform in the engine's render space.
    ///
    /// `Transform` composes with the engine's built-in aspect-fill scaling — the clip's
    /// natural content fills the canvas, then the transform's `scale`, `rotation`, and
    /// `center` reposition it. Pass `.identity` (default-initialized `Transform`) for a
    /// no-op base. Calling `.transform(_:)` again replaces the previous value (transforms
    /// don't accumulate). Added in v0.8.
    ///
    /// ```swift
    /// // Picture-in-picture pinned to the top-right corner at 40% scale
    /// VideoClip(url: pip)
    ///     .trimmed(to: 0...3)
    ///     .transform(Transform(center: .topRight, scale: 0.4, anchor: .topRight))
    /// ```
    public func transform(_ transform: Transform) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Apply a per-clip transform with an animation that drives it over the clip's
    /// lifetime. The static `base` is used outside the animation's keyframes range
    /// (or for keyframes the engine couldn't evaluate). Pass `Transform.identity` for
    /// a "pure animation" with no static base. Animation timing is **clip-relative** —
    /// `.at(0.0, ...)` means the clip's first frame, not composition t=0. Added in v0.8.
    ///
    /// ```swift
    /// // Ken Burns zoom-pan on a still image
    /// ImageClip(photo, duration: 5.0)
    ///     .transform(.identity, animation: .keyframes([
    ///         .at(0.0, value: Transform(scale: 1.0)),
    ///         .at(5.0, value: Transform(scale: 1.3)),
    ///     ], timing: .easeInOut))
    /// ```
    public func transform(_ base: Transform, animation: Animation<Transform>) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: clipID, startTime: startTime, transform: base, transformAnimation: animation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Set this clip's opacity in `0...1`. `1.0` (the default when not set) is fully
    /// opaque; `0.0` is fully transparent. Added in v0.8.
    public func opacity(_ opacity: Double) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Animate this clip's opacity over its lifetime. `base` is used outside the
    /// animation's keyframes range. Animation timing is clip-relative. Added in v0.8.
    ///
    /// ```swift
    /// // Fade-in then hold
    /// VideoClip(url: clipURL).trimmed(to: 0...3)
    ///     .opacity(1.0, animation: .keyframes([
    ///         .at(0.0, value: 0.0),
    ///         .at(0.5, value: 1.0),
    ///     ]))
    /// ```
    public func opacity(_ base: Double, animation: Animation<Double>) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: base, opacityAnimation: animation, speedCurve: speedCurve)
    }

    /// Append a ``Compositor`` to this clip. Compositors run after ``Filter``s during
    /// the export pre-render pass; multiple `.compositor` calls accumulate in declaration
    /// order. See the ``Compositor`` documentation for the per-frame contract.
    public func compositor(_ compositor: any Compositor) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters, filterIDs: filterIDs, filterAnimations: filterAnimations, compositors: compositors + [compositor], clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation, speedCurve: speedCurve)
    }

    /// Append an inline closure-backed ``Compositor``. Convenient for one-off
    /// transformations:
    ///
    /// ```swift
    /// VideoClip(url: clipURL).compositor { image, _ in
    ///     image.applyingFilter("CIColorInvert")
    /// }
    /// ```
    public func compositor(_ body: @Sendable @escaping (CIImage, CompositorContext) -> CIImage) -> VideoClip {
        compositor(ClosureCompositor(body: body))
    }

    /// Crop this clip to a rectangular region, scaling the result to fill the clip's
    /// original frame ("reframe / zoom-in" semantics). Mirrors the composition-wide
    /// ``Video/crop(at:size:anchor:)`` shape but operates per-clip.
    ///
    /// ```swift
    /// VideoClip(url: clipURL)
    ///     .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
    /// ```
    ///
    /// `position` is where the crop's `anchor` lands within the clip's source frame, in
    /// the same coordinate system as overlays. Default `anchor` is `.center` so the
    /// most common case — "crop to the middle X%" — reads naturally.
    ///
    /// **Implementation:** wraps a built-in ``Compositor`` (internal `CropCompositor`)
    /// and appends it to the clip's compositor list. Multiple `.crop` calls accumulate
    /// — each subsequent crop further crops the result of the previous, in declaration
    /// order. If the crop's aspect ratio doesn't match the source frame's, the cropped
    /// region is stretched to fill (no letterbox). For aspect-preserved letterbox or
    /// composition-wide cropping, use ``Video/crop(at:size:anchor:)``.
    public func crop(at position: Position, size: Size, anchor: Anchor = .center) -> VideoClip {
        compositor(CropCompositor(position: position, size: size, anchor: anchor))
    }

    /// Mask this clip with an alpha mask image. Pixels under fully-opaque mask alpha
    /// pass through; pixels under fully-transparent mask alpha become transparent.
    /// Anti-aliased mask edges produce proportional alpha — useful for soft-edge or
    /// shape-cropped looks (circular bug, irregular cutouts, vignettes).
    ///
    /// ```swift
    /// VideoClip(url: clipURL).mask(circularMask)
    /// ```
    ///
    /// **Sizing**: the mask is stretched to fit each frame's extent. Authoring masks at
    /// the composition's preset resolution avoids distortion when aspect ratios differ.
    ///
    /// **Implementation**: wraps a built-in ``Compositor`` (internal `MaskCompositor`)
    /// using `CIBlendWithAlphaMask`. Multiple `.mask` calls accumulate; each subsequent
    /// mask further restricts the visible region (logical AND of mask alphas).
    public func mask(_ mask: CIImage) -> VideoClip {
        compositor(MaskCompositor(mask: mask))
    }

    /// Mask this clip with a `PlatformImage` (UIImage / NSImage). Convenience overload —
    /// extracts a `CIImage` from the platform image and delegates to ``mask(_:)-(CIImage)``.
    /// If the image can't be converted to a `CIImage`, this clip passes through unchanged.
    public func mask(_ mask: PlatformImage) -> VideoClip {
        guard let ci = MaskCompositor.ciImage(from: mask) else { return self }
        return self.mask(ci)
    }

    /// Extract a thumbnail at a `CMTime` offset for frame-accurate selection.
    public func thumbnail(at time: CMTime) async throws -> PlatformImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let cgImage = try await generator.image(at: time).image
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }

    /// Extract a thumbnail at a `TimeInterval` offset. Convenience overload.
    public func thumbnail(at time: TimeInterval = 0) async throws -> PlatformImage {
        try await thumbnail(at: CMTime(seconds: time, preferredTimescale: 600))
    }
}
