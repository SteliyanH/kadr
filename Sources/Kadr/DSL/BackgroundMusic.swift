import Foundation
import CoreMedia

/// Convenience wrapper over ``AudioTrack`` for the typical "background music throughout
/// the composition" use case. Comes with sensible defaults for volume, fades, and
/// auto-ducking when clip audio plays.
///
/// ```swift
/// // One-line common case
/// Video { ... }.backgroundMusic(url: musicURL)
///
/// // Explicit overrides
/// Video { ... }.backgroundMusic(
///     BackgroundMusic(url: musicURL, volume: 0.4, duckingLevel: 0.15)
/// )
/// ```
///
/// For full control over fade timing or to omit ducking entirely, use ``Video/audio(_:)-(_)``
/// with a hand-built ``AudioTrack``.
public struct BackgroundMusic: Sendable {
    public let url: URL
    public let volume: Double
    public let fadeIn: TimeInterval
    public let fadeOut: TimeInterval
    /// Target volume (`0.0`...`1.0`) when clip audio plays. `nil` disables ducking.
    public let duckingLevel: Double?

    /// Build a background-music spec. Defaults: volume `0.6`, fade-in `0.5s`, fade-out `1.0s`,
    /// ducking to `0.3` while clip audio plays. Pass `duckingLevel: nil` to disable ducking.
    public init(
        url: URL,
        volume: Double = 0.6,
        fadeIn: TimeInterval = 0.5,
        fadeOut: TimeInterval = 1.0,
        duckingLevel: Double? = 0.3
    ) {
        self.url = url
        self.volume = volume
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.duckingLevel = duckingLevel
    }

    /// Materialize this spec into an ``AudioTrack`` ready for the Video's audio mix.
    internal var audioTrack: AudioTrack {
        var track = AudioTrack(url: url)
            .volume(volume)
            .fadeIn(fadeIn)
            .fadeOut(fadeOut)
        if let duck = duckingLevel {
            track = track.ducking(duck)
        }
        return track
    }
}

extension Video {
    /// Add a background-music track with sensible defaults. Sugar for the common case;
    /// use ``audio(_:)-(_)`` with a hand-built ``AudioTrack`` for full control.
    public func backgroundMusic(_ music: BackgroundMusic) -> Video {
        audio { music.audioTrack }
    }

    /// Convenience overload taking a URL with all defaults
    /// (volume `0.6`, fade-in `0.5s`, fade-out `1.0s`, ducking to `0.3`).
    public func backgroundMusic(url: URL) -> Video {
        backgroundMusic(BackgroundMusic(url: url))
    }
}
