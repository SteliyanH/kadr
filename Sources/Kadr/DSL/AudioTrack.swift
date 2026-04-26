import Foundation
import CoreMedia

/// A composition-level audio track (typically background music or narration).
///
/// Apply modifiers to set volume, fade in/out, and auto-duck when clip audio plays:
///
/// ```swift
/// Video { ... }
///     .audio {
///         AudioTrack(url: musicURL)
///             .volume(0.8)
///             .fadeIn(1.0)
///             .fadeOut(2.0)
///             .ducking(0.3)
///     }
/// ```
///
/// Fade durations accept both `CMTime` (frame-accurate) and `TimeInterval` (ergonomic) forms.
public struct AudioTrack: Sendable {
    /// File URL of the audio source.
    public let url: URL
    internal let volumeLevel: Double
    internal let fadeInDuration: CMTime
    internal let fadeOutDuration: CMTime
    internal let duckingLevel: Double?

    /// Build a track at full volume with no fades or ducking.
    public init(url: URL) {
        self.url = url
        self.volumeLevel = 1.0
        self.fadeInDuration = .zero
        self.fadeOutDuration = .zero
        self.duckingLevel = nil
    }

    internal init(
        url: URL,
        volumeLevel: Double,
        fadeInDuration: CMTime,
        fadeOutDuration: CMTime,
        duckingLevel: Double? = nil
    ) {
        self.url = url
        self.volumeLevel = volumeLevel
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
        self.duckingLevel = duckingLevel
    }

    /// Set the track's overall volume. `1.0` is full source volume; `0.5` is half;
    /// `0.0` is silence. Values outside `0.0...` are clamped by AVFoundation.
    public func volume(_ level: Double) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: level, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel)
    }

    /// Fade in over a `CMTime` duration for frame-accurate precision.
    public func fadeIn(_ duration: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: duration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel)
    }

    /// Fade in over a `TimeInterval`. Convenience overload.
    public func fadeIn(_ duration: TimeInterval) -> AudioTrack {
        fadeIn(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Fade out over a `CMTime` duration for frame-accurate precision.
    public func fadeOut(_ duration: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: duration, duckingLevel: duckingLevel)
    }

    /// Fade out over a `TimeInterval`. Convenience overload.
    public func fadeOut(_ duration: TimeInterval) -> AudioTrack {
        fadeOut(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Auto-lower this track's volume to `targetVolume` while clip audio is playing.
    /// `targetVolume` is the absolute level during ducking (0.0 = silent, 1.0 = no ducking).
    /// Out-of-range values throw `KadrError.invalidDuckingLevel` at export time.
    public func ducking(_ targetVolume: Double) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: targetVolume)
    }
}
