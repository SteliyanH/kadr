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

    /// Explicit composition start time, set via ``at(time:)-(CMTime)`` /
    /// ``at(time:)-(TimeInterval)``. `nil` (default) participates in the implicit chain.
    /// See ``Clip/startTime`` for the v0.6 surface contract.
    public let startTime: CMTime?

    /// Optional per-clip affine transform applied in the engine's render space. `nil`
    /// (default) leaves the clip's natural aspect-fill layout unchanged. Set via
    /// ``transform(_:)``. Added in v0.8.
    public let transform: Transform?

    /// Optional keyframe animation driving ``transform`` over the clip's lifetime.
    /// Set via ``transform(_:animation:)``. Added in v0.8.
    public let transformAnimation: Animation<Transform>?

    /// Optional per-clip opacity in `0...1`. `nil` (default) means fully opaque.
    /// Set via ``opacity(_:)``. Added in v0.8.
    public let opacity: Double?

    /// Optional keyframe animation driving ``opacity`` over the clip's lifetime.
    /// Set via ``opacity(_:animation:)``. Added in v0.8.
    public let opacityAnimation: Animation<Double>?

    public var duration: CMTime { _duration }

    /// Image clip with a `CMTime` duration for frame-accurate precision.
    public init(_ image: PlatformImage, duration: CMTime) {
        self.image = image
        self._duration = duration
        self.backgroundColor = nil
        self.audioURL = nil
        self.clipID = nil
        self.startTime = nil
        self.transform = nil
        self.transformAnimation = nil
        self.opacity = nil
        self.opacityAnimation = nil
    }

    /// Image clip with a `TimeInterval` duration. Convenience overload.
    public init(_ image: PlatformImage, duration: TimeInterval = 3.0) {
        self.init(image, duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    internal init(image: PlatformImage, duration: CMTime, backgroundColor: PlatformColor?, audioURL: URL?, clipID: ClipID? = nil, startTime: CMTime? = nil, transform: Transform? = nil, transformAnimation: Animation<Transform>? = nil, opacity: Double? = nil, opacityAnimation: Animation<Double>? = nil) {
        self.image = image
        self._duration = duration
        self.backgroundColor = backgroundColor
        self.audioURL = audioURL
        self.clipID = clipID
        self.startTime = startTime
        self.transform = transform
        self.transformAnimation = transformAnimation
        self.opacity = opacity
        self.opacityAnimation = opacityAnimation
    }

    /// Fill the area outside the image (when aspect-ratio doesn't match the export preset)
    /// with `color`. Defaults to transparent if not set.
    public func background(_ color: PlatformColor) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: color, audioURL: audioURL, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation)
    }

    /// Attach an audio track that plays for this clip's duration. If the audio is longer
    /// than the clip, it is truncated.
    public func withAudio(_ audioURL: URL) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation)
    }

    /// Override the duration with a `CMTime` for frame-accurate precision.
    public func duration(_ duration: CMTime) -> ImageClip {
        ImageClip(image: image, duration: duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation)
    }

    /// Override the duration with a `TimeInterval`. Convenience overload.
    public func duration(_ duration: TimeInterval) -> ImageClip {
        self.duration(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Assign a stable identifier so callers can address this clip by ID across reorders
    /// or trims. See ``ClipID`` for guidelines on choosing IDs.
    public func id(_ id: ClipID) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: id, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation)
    }

    /// Pin this clip to an explicit composition start time. See ``Clip/startTime`` for
    /// the contract; v0.6 Tier 1 ships the surface only — engine wiring lands in the
    /// multi-track engine PR.
    public func at(time: CMTime) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: clipID, startTime: time, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation)
    }

    /// Pin this clip to an explicit composition start time, in seconds.
    public func at(time: TimeInterval) -> ImageClip {
        at(time: CMTime(seconds: time, preferredTimescale: 600))
    }

    /// Apply a per-clip affine transform in the engine's render space. See
    /// ``Kadr/Transform`` and ``Kadr/VideoClip/transform(_:)`` for the contract.
    /// Added in v0.8.
    public func transform(_ transform: Transform) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation)
    }

    /// Apply a per-clip transform with a clip-relative keyframe animation. See
    /// ``Kadr/VideoClip/transform(_:animation:)`` for the contract. Added in v0.8.
    public func transform(_ base: Transform, animation: Animation<Transform>) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: clipID, startTime: startTime, transform: base, transformAnimation: animation, opacity: opacity, opacityAnimation: opacityAnimation)
    }

    /// Set this clip's opacity in `0...1`. Added in v0.8.
    public func opacity(_ opacity: Double) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: opacity, opacityAnimation: opacityAnimation)
    }

    /// Animate this clip's opacity over its lifetime. Animation timing is
    /// clip-relative. Added in v0.8.
    public func opacity(_ base: Double, animation: Animation<Double>) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL, clipID: clipID, startTime: startTime, transform: transform, transformAnimation: transformAnimation, opacity: base, opacityAnimation: animation)
    }
}
