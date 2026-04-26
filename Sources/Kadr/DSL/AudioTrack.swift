import Foundation

public struct AudioTrack: Sendable {
    public let url: URL
    internal let volumeLevel: Double
    internal let fadeInDuration: TimeInterval
    internal let fadeOutDuration: TimeInterval
    internal let duckingLevel: Double?

    public init(url: URL) {
        self.url = url
        self.volumeLevel = 1.0
        self.fadeInDuration = 0
        self.fadeOutDuration = 0
        self.duckingLevel = nil
    }

    internal init(
        url: URL,
        volumeLevel: Double,
        fadeInDuration: TimeInterval,
        fadeOutDuration: TimeInterval,
        duckingLevel: Double? = nil
    ) {
        self.url = url
        self.volumeLevel = volumeLevel
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
        self.duckingLevel = duckingLevel
    }

    public func volume(_ level: Double) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: level, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel)
    }

    public func fadeIn(_ duration: TimeInterval) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: duration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel)
    }

    public func fadeOut(_ duration: TimeInterval) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: duration, duckingLevel: duckingLevel)
    }

    /// Auto-lower this track's volume to `targetVolume` while clip audio is playing.
    /// `targetVolume` is the absolute level during ducking (0.0 = silent, 1.0 = no ducking).
    /// Out-of-range values throw `KadrError.invalidDuckingLevel` at export time.
    public func ducking(_ targetVolume: Double) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: targetVolume)
    }
}
