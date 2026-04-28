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

    /// Linear volume multiplier in `0.0...1.0`. `1.0` is the asset's natural level.
    /// Set via ``volume(_:)``.
    public let volumeLevel: Double

    /// Fade-in duration applied at the start of the track. `.zero` if no fade-in.
    /// Set via ``fadeIn(_:)`` (CMTime or TimeInterval).
    public let fadeInDuration: CMTime

    /// Fade-out duration applied at the end of the track. `.zero` if no fade-out.
    /// Set via ``fadeOut(_:)`` (CMTime or TimeInterval).
    public let fadeOutDuration: CMTime

    /// Auto-ducking target level in `0.0...1.0`, or `nil` if ducking is disabled. When set,
    /// the engine attenuates this track to `volumeLevel * duckingLevel` whenever clip audio
    /// plays. Set via ``ducking(_:)``.
    public let duckingLevel: Double?

    /// Composition time at which this audio track starts. `nil` (default) means t=0.
    /// Set via ``at(time:)-(CMTime)`` / ``at(time:)-(TimeInterval)``. Added in v0.7 —
    /// enables sound effects pinned to a moment.
    public let startTime: CMTime?

    /// Optional explicit cap on how long this track plays from `startTime`. `nil`
    /// (default) means "play the asset from `startTime` to its natural end, clamped to
    /// the composition's end". Set via ``duration(_:)-(CMTime)`` /
    /// ``duration(_:)-(TimeInterval)``. Added in v0.7.
    public let explicitDuration: CMTime?

    /// Build a track at full volume with no fades or ducking, starting at t=0.
    public init(url: URL) {
        self.url = url
        self.volumeLevel = 1.0
        self.fadeInDuration = .zero
        self.fadeOutDuration = .zero
        self.duckingLevel = nil
        self.startTime = nil
        self.explicitDuration = nil
    }

    internal init(
        url: URL,
        volumeLevel: Double,
        fadeInDuration: CMTime,
        fadeOutDuration: CMTime,
        duckingLevel: Double? = nil,
        startTime: CMTime? = nil,
        explicitDuration: CMTime? = nil
    ) {
        self.url = url
        self.volumeLevel = volumeLevel
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
        self.duckingLevel = duckingLevel
        self.startTime = startTime
        self.explicitDuration = explicitDuration
    }

    /// Set the track's overall volume. `1.0` is full source volume; `0.5` is half;
    /// `0.0` is silence. Values outside `0.0...` are clamped by AVFoundation.
    public func volume(_ level: Double) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: level, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: explicitDuration)
    }

    /// Fade in over a `CMTime` duration for frame-accurate precision.
    public func fadeIn(_ duration: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: duration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: explicitDuration)
    }

    /// Fade in over a `TimeInterval`. Convenience overload.
    public func fadeIn(_ duration: TimeInterval) -> AudioTrack {
        fadeIn(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Fade out over a `CMTime` duration for frame-accurate precision.
    public func fadeOut(_ duration: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: duration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: explicitDuration)
    }

    /// Fade out over a `TimeInterval`. Convenience overload.
    public func fadeOut(_ duration: TimeInterval) -> AudioTrack {
        fadeOut(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Auto-lower this track's volume to `targetVolume` while clip audio is playing.
    /// `targetVolume` is the absolute level during ducking (0.0 = silent, 1.0 = no ducking).
    /// Out-of-range values throw `KadrError.invalidDuckingLevel` at export time.
    public func ducking(_ targetVolume: Double) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: targetVolume, startTime: startTime, explicitDuration: explicitDuration)
    }

    /// Pin this audio track to start at the given composition time. Sound effects and
    /// time-anchored music use this. CMTime form for frame-accurate placement.
    /// Added in v0.7.
    public func at(time: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: time, explicitDuration: explicitDuration)
    }

    /// Pin this audio track to start at the given composition time. TimeInterval
    /// convenience overload. Added in v0.7.
    public func at(time: TimeInterval) -> AudioTrack {
        at(time: CMTime(seconds: time, preferredTimescale: 600))
    }

    /// Cap how long this track plays from `startTime` (or t=0 if unpinned). When `nil`
    /// (the default), the track plays the asset from start to its natural end, clamped
    /// to the composition's end. CMTime form. Added in v0.7.
    public func duration(_ duration: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: duration)
    }

    /// Cap how long this track plays. TimeInterval convenience overload. Added in v0.7.
    public func duration(_ duration: TimeInterval) -> AudioTrack {
        self.duration(CMTime(seconds: duration, preferredTimescale: 600))
    }
}
