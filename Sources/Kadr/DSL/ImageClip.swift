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

    /// Solid color drawn behind the image to fill the render canvas. `nil` means
    /// transparent / black. Set via ``background(_:)``.
    public let backgroundColor: PlatformColor?

    /// Audio file played alongside the image for the clip's duration, or `nil`. Set via
    /// ``withAudio(_:)``.
    public let audioURL: URL?

    /// Stable identifier for addressing this clip across reorders or trims, set via
    /// ``id(_:)``. `nil` if no ID has been assigned.
    public let clipID: ClipID?

    public var duration: CMTime { _duration }

    /// Image clip with a `CMTime` duration for frame-accurate precision.
    public init(_ image: PlatformImage, duration: CMTime) {
        self.image = image
        self._duration = duration
        self.backgroundColor = nil
        self.audioURL = nil
        self.clipID = nil
    }

    /// Image clip with a `TimeInterval` duration. Convenience overload.
    public init(_ image: PlatformImage, duration: TimeInterval = 3.0) {
        self.init(image, duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    internal init(image: PlatformImage, duration: CMTime, backgroundColor: PlatformColor?, audioURL: URL?, clipID: ClipID? = nil) {
        self.image = image
        self._duration = duration
        self.backgroundColor = backgroundColor
        self.audioURL = audioURL
        self.clipID = clipID
    }

    /// Fill the area outside the image (when aspect-ratio doesn't match the export preset)
    /// with `color`. Defaults to transparent if not set.
    public func background(_ color: PlatformColor) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: color, audioURL: audioURL, clipID: clipID)
    }

    /// Attach an audio track that plays for this clip's duration. If the audio is longer
    /// than the clip, it is truncated.
    public func withAudio(_ audioURL: URL) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: clipID)
    }

    /// Override the duration with a `CMTime` for frame-accurate precision.
    public func duration(_ duration: CMTime) -> ImageClip {
        ImageClip(image: image, duration: duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: clipID)
    }

    /// Override the duration with a `TimeInterval`. Convenience overload.
    public func duration(_ duration: TimeInterval) -> ImageClip {
        self.duration(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Assign a stable identifier so callers can address this clip by ID across reorders
    /// or trims. See ``ClipID`` for guidelines on choosing IDs.
    public func id(_ id: ClipID) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: id)
    }
}
