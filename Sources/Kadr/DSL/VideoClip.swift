import Foundation
import CoreMedia
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct VideoClipMetadata: Sendable {
    public let duration: CMTime
    public let resolution: CGSize
    public let frameRate: Double
    public let hasAudio: Bool
}

public struct VideoClip: Clip, Sendable {
    public let url: URL
    internal let trimRange: CMTimeRange?
    internal let isReversed: Bool
    internal let isMuted: Bool
    internal let replacementAudioURL: URL?
    internal let speedRate: Double

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

    public init(url: URL) {
        self.url = url
        self.trimRange = nil
        self.isReversed = false
        self.isMuted = false
        self.replacementAudioURL = nil
        self.speedRate = 1.0
    }

    internal init(url: URL, trimRange: CMTimeRange?, isReversed: Bool, isMuted: Bool, replacementAudioURL: URL?, speedRate: Double = 1.0) {
        self.url = url
        self.trimRange = trimRange
        self.isReversed = isReversed
        self.isMuted = isMuted
        self.replacementAudioURL = replacementAudioURL
        self.speedRate = speedRate
    }

    /// Trim with a `CMTimeRange` for frame-accurate precision.
    public func trimmed(_ range: CMTimeRange) -> VideoClip {
        VideoClip(url: url, trimRange: range, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate)
    }

    /// Trim with a `ClosedRange<TimeInterval>`. Convenience overload — converts to `CMTimeRange`
    /// at timescale 600. For frame-accurate trims at a specific frame rate, prefer
    /// `trimmed(_ range: CMTimeRange)`.
    public func trimmed(to range: ClosedRange<TimeInterval>) -> VideoClip {
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        return trimmed(CMTimeRange(start: start, duration: CMTimeSubtract(end, start)))
    }

    public func reversed() -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: true, isMuted: isMuted, replacementAudioURL: replacementAudioURL, speedRate: speedRate)
    }

    public func muted() -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: true, replacementAudioURL: replacementAudioURL, speedRate: speedRate)
    }

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
