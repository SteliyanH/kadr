import Foundation
import CoreMedia

/// A still image displayed for a fixed duration.
///
/// ```swift
/// ImageClip(heroImage, duration: 5.0)
///     .background(.black)
///     .withAudio(narrationURL)
/// ```
///
/// The duration parameter accepts both `CMTime` (frame-accurate) and `TimeInterval`
/// (ergonomic) forms.
public struct ImageClip: Clip, Sendable {
    /// The image rendered for the clip's duration.
    public let image: PlatformImage
    internal let _duration: CMTime
    internal let backgroundColor: PlatformColor?
    internal let audioURL: URL?

    public var duration: CMTime { _duration }

    /// Image clip with a `CMTime` duration for frame-accurate precision.
    public init(_ image: PlatformImage, duration: CMTime) {
        self.image = image
        self._duration = duration
        self.backgroundColor = nil
        self.audioURL = nil
    }

    /// Image clip with a `TimeInterval` duration. Convenience overload.
    public init(_ image: PlatformImage, duration: TimeInterval = 3.0) {
        self.init(image, duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    internal init(image: PlatformImage, duration: CMTime, backgroundColor: PlatformColor?, audioURL: URL?) {
        self.image = image
        self._duration = duration
        self.backgroundColor = backgroundColor
        self.audioURL = audioURL
    }

    /// Fill the area outside the image (when aspect-ratio doesn't match the export preset)
    /// with `color`. Defaults to transparent if not set.
    public func background(_ color: PlatformColor) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: color, audioURL: audioURL)
    }

    /// Attach an audio track that plays for this clip's duration. If the audio is longer
    /// than the clip, it is truncated.
    public func withAudio(_ audioURL: URL) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL)
    }

    /// Override the duration with a `CMTime` for frame-accurate precision.
    public func duration(_ duration: CMTime) -> ImageClip {
        ImageClip(image: image, duration: duration, backgroundColor: backgroundColor, audioURL: audioURL)
    }

    /// Override the duration with a `TimeInterval`. Convenience overload.
    public func duration(_ duration: TimeInterval) -> ImageClip {
        self.duration(CMTime(seconds: duration, preferredTimescale: 600))
    }
}
