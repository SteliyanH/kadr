import Foundation

public struct AudioTrack: Sendable {
    public let url: URL
    internal let volumeLevel: Double
    internal let fadeInDuration: TimeInterval
    internal let fadeOutDuration: TimeInterval

    public init(url: URL) {
        self.url = url
        self.volumeLevel = 1.0
        self.fadeInDuration = 0
        self.fadeOutDuration = 0
    }

    internal init(url: URL, volumeLevel: Double, fadeInDuration: TimeInterval, fadeOutDuration: TimeInterval) {
        self.url = url
        self.volumeLevel = volumeLevel
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
    }

    public func volume(_ level: Double) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: level, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration)
    }

    public func fadeIn(_ duration: TimeInterval) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: duration, fadeOutDuration: fadeOutDuration)
    }

    public func fadeOut(_ duration: TimeInterval) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: duration)
    }
}
