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
    internal let trimRange: ClosedRange<TimeInterval>?
    internal let isReversed: Bool
    internal let isMuted: Bool
    internal let replacementAudioURL: URL?

    public var duration: CMTime {
        if let trimRange {
            return CMTime(seconds: trimRange.upperBound - trimRange.lowerBound, preferredTimescale: 600)
        }
        // Synchronous fallback — actual duration requires async asset loading
        return .zero
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
    }

    internal init(url: URL, trimRange: ClosedRange<TimeInterval>?, isReversed: Bool, isMuted: Bool, replacementAudioURL: URL?) {
        self.url = url
        self.trimRange = trimRange
        self.isReversed = isReversed
        self.isMuted = isMuted
        self.replacementAudioURL = replacementAudioURL
    }

    public func trimmed(to range: ClosedRange<TimeInterval>) -> VideoClip {
        VideoClip(url: url, trimRange: range, isReversed: isReversed, isMuted: isMuted, replacementAudioURL: replacementAudioURL)
    }

    public func reversed() -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: true, isMuted: isMuted, replacementAudioURL: replacementAudioURL)
    }

    public func muted() -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: true, replacementAudioURL: replacementAudioURL)
    }

    public func withAudio(_ audioURL: URL) -> VideoClip {
        VideoClip(url: url, trimRange: trimRange, isReversed: isReversed, isMuted: true, replacementAudioURL: audioURL)
    }

    public func thumbnail(at time: TimeInterval = 0) async throws -> PlatformImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let cgImage = try await generator.image(at: cmTime).image
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }
}
