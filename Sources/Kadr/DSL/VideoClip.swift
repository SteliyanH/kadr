import Foundation
import CoreMedia
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
    internal let trimRange: CMTimeRange?
    internal let isReversed: Bool
    internal let isMuted: Bool
    internal let replacementAudioURL: URL?
    internal let speedRate: Double
    internal let filters: [Filter]

    /// Timeline contribution after trim and speed are applied. Returns `CMTime.zero` when
    /// the clip hasn't been trimmed (the source asset's duration isn't known synchronously
    /// — call ``metadata`` for that).
    public var duration: CMTime {
        guard let trimRange else {
            // Synchronous fallback — actual duration requires async asset loading
            return .zero
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
    /// 1x speed, not reversed, not muted.
    public init(url: URL) {
        self.url = url
        self.trimRange = nil
        self.isReversed = false
        self.isMuted = false
        self.replacementAudioURL = nil
        self.speedRate = 1.0
        self.filters = []
    }

    internal init(
        url: URL,
        trimRange: CMTimeRange?,
        isReversed: Bool,
        isMuted: Bool,
        replacementAudioURL: URL?,
        speedRate: Double = 1.0,
        filters: [Filter] = []
    ) {
        self.url = url
        self.trimRange = trimRange
        self.isReversed = isReversed
        self.isMuted = isMuted
        self.replacementAudioURL = replacementAudioURL
        self.speedRate = speedRate
        self.filters = filters
    }

    /// Trim with a `CMTimeRange` for frame-accurate precision.
    public func trimmed(to range: CMTimeRange) -> VideoClip {
        VideoClip(url: url, trimRange: range, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters)
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
        VideoClip(url: url, trimRange: trimRange, isReversed: true, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters)
    }

    /// Drop the source's audio track from the composition. Use ``withAudio(_:)`` to also
    /// substitute a different audio file.
    public func muted() -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: true, replacementAudioURL: replacementAudioURL, speedRate: speedRate, filters: filters)
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
            filters: self.filters + filters
        )
    }

    /// Replace the source's audio with the audio from `audioURL` (mutes the original).
    /// If the replacement audio is longer than the clip, it is truncated; if shorter, it
    /// is not looped.
    public func withAudio(_ audioURL: URL) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: true, replacementAudioURL: audioURL, speedRate: speedRate)
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
