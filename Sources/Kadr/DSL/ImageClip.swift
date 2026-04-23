import Foundation
import CoreMedia

public struct ImageClip: Clip, Sendable {
    public let image: PlatformImage
    internal let _duration: CMTime
    internal let backgroundColor: PlatformColor?
    internal let audioURL: URL?

    public var duration: CMTime { _duration }

    public init(_ image: PlatformImage, duration: TimeInterval = 3.0) {
        self.image = image
        self._duration = CMTime(seconds: duration, preferredTimescale: 600)
        self.backgroundColor = nil
        self.audioURL = nil
    }

    internal init(image: PlatformImage, duration: CMTime, backgroundColor: PlatformColor?, audioURL: URL?) {
        self.image = image
        self._duration = duration
        self.backgroundColor = backgroundColor
        self.audioURL = audioURL
    }

    public func background(_ color: PlatformColor) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: color, audioURL: audioURL)
    }

    public func withAudio(_ audioURL: URL) -> ImageClip {
        ImageClip(image: image, duration: _duration, backgroundColor: backgroundColor, audioURL: audioURL)
    }

    public func duration(_ duration: TimeInterval) -> ImageClip {
        ImageClip(image: image, duration: CMTime(seconds: duration, preferredTimescale: 600), backgroundColor: backgroundColor, audioURL: audioURL)
    }
}
