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

    /// Optional cross-fade duration to apply when this track's end overlaps with the
    /// **next** audio track's start (in declaration order). When set and an overlap
    /// exists, the engine emits matching volume ramps — fade out on this track and
    /// fade in on the next — over `min(crossfadeDuration, overlapDuration)`. The
    /// crossfade overrides any explicit `fadeIn` / `fadeOut` at that boundary so
    /// AVFoundation doesn't see overlapping ramps. Set via ``crossfade(_:)``.
    /// Added in v0.8.
    public let crossfadeDuration: CMTime?

    /// Granular volume automation curves between two points, in track-relative time
    /// (0 = the audio's start in the composition, i.e. ``startTime``). Each ramp
    /// linearly interpolates from `startVolume` to `endVolume` across `range`. Set
    /// via ``volumeRamp(start:end:during:)``. Added in v0.8.3.
    ///
    /// Engine consumers must avoid overlap between ramps and the implicit fade-in /
    /// fade-out / crossfade ranges. The engine drops ramps that would overlap (with
    /// a console warning); the static `.volume`, `.fadeIn`, `.fadeOut`, and
    /// crossfade-driven ramps win.
    public let volumeRamps: [VolumeRamp]

    /// A volume automation curve between two points in track-relative time.
    public struct VolumeRamp: Sendable, Equatable {

        /// Volume at the start of the ramp's time range. `0...1` typical (AVFoundation
        /// clamps under the hood).
        public let startVolume: Double

        /// Volume at the end of the ramp's time range.
        public let endVolume: Double

        /// Time range in track-relative time (offset from the track's `startTime`).
        public let range: CMTimeRange

        public init(startVolume: Double, endVolume: Double, range: CMTimeRange) {
            self.startVolume = startVolume
            self.endVolume = endVolume
            self.range = range
        }
    }

    /// Build a track at full volume with no fades or ducking, starting at t=0.
    public init(url: URL) {
        self.url = url
        self.volumeLevel = 1.0
        self.fadeInDuration = .zero
        self.fadeOutDuration = .zero
        self.duckingLevel = nil
        self.startTime = nil
        self.explicitDuration = nil
        self.crossfadeDuration = nil
        self.volumeRamps = []
    }

    internal init(
        url: URL,
        volumeLevel: Double,
        fadeInDuration: CMTime,
        fadeOutDuration: CMTime,
        duckingLevel: Double? = nil,
        startTime: CMTime? = nil,
        explicitDuration: CMTime? = nil,
        crossfadeDuration: CMTime? = nil,
        volumeRamps: [VolumeRamp] = []
    ) {
        self.url = url
        self.volumeLevel = volumeLevel
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
        self.duckingLevel = duckingLevel
        self.startTime = startTime
        self.explicitDuration = explicitDuration
        self.crossfadeDuration = crossfadeDuration
        self.volumeRamps = volumeRamps
    }

    /// Set the track's overall volume. `1.0` is full source volume; `0.5` is half;
    /// `0.0` is silence. Values outside `0.0...` are clamped by AVFoundation.
    public func volume(_ level: Double) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: level, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: explicitDuration, crossfadeDuration: crossfadeDuration, volumeRamps: volumeRamps)
    }

    /// Fade in over a `CMTime` duration for frame-accurate precision.
    public func fadeIn(_ duration: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: duration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: explicitDuration, crossfadeDuration: crossfadeDuration, volumeRamps: volumeRamps)
    }

    /// Fade in over a `TimeInterval`. Convenience overload.
    public func fadeIn(_ duration: TimeInterval) -> AudioTrack {
        fadeIn(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Fade out over a `CMTime` duration for frame-accurate precision.
    public func fadeOut(_ duration: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: duration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: explicitDuration, crossfadeDuration: crossfadeDuration, volumeRamps: volumeRamps)
    }

    /// Fade out over a `TimeInterval`. Convenience overload.
    public func fadeOut(_ duration: TimeInterval) -> AudioTrack {
        fadeOut(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Auto-lower this track's volume to `targetVolume` while clip audio is playing.
    /// `targetVolume` is the absolute level during ducking (0.0 = silent, 1.0 = no ducking).
    /// Out-of-range values throw `KadrError.invalidDuckingLevel` at export time.
    public func ducking(_ targetVolume: Double) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: targetVolume, startTime: startTime, explicitDuration: explicitDuration, crossfadeDuration: crossfadeDuration, volumeRamps: volumeRamps)
    }

    /// Pin this audio track to start at the given composition time. Sound effects and
    /// time-anchored music use this. CMTime form for frame-accurate placement.
    /// Added in v0.7.
    public func at(time: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: time, explicitDuration: explicitDuration, crossfadeDuration: crossfadeDuration, volumeRamps: volumeRamps)
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
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: duration, crossfadeDuration: crossfadeDuration, volumeRamps: volumeRamps)
    }

    /// Cap how long this track plays. TimeInterval convenience overload. Added in v0.7.
    public func duration(_ duration: TimeInterval) -> AudioTrack {
        self.duration(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Cross-fade with the **next** audio track in declaration order. When set and
    /// the two tracks overlap on the timeline, the engine emits matching volume
    /// ramps — fade out on this track, fade in on the next — over
    /// `min(crossfadeDuration, overlapDuration)`. CMTime form for frame-accurate
    /// boundaries. Added in v0.8.
    ///
    /// ```swift
    /// .audio {
    ///     AudioTrack(url: musicA).at(time: 0).duration(8.0).crossfade(1.0)
    ///     AudioTrack(url: musicB).at(time: 7.0)  // 1s overlap fades A→B
    /// }
    /// ```
    public func crossfade(_ duration: CMTime) -> AudioTrack {
        AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: explicitDuration, crossfadeDuration: duration, volumeRamps: volumeRamps)
    }

    /// Cross-fade with the next audio track. TimeInterval convenience overload.
    /// Added in v0.8.
    public func crossfade(_ duration: TimeInterval) -> AudioTrack {
        crossfade(CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Add a granular volume automation ramp between two volume levels over a
    /// track-relative time range. Multiple `.volumeRamp(...)` calls accumulate.
    /// CMTime form for frame-accurate boundaries. Added in v0.8.3.
    ///
    /// ```swift
    /// // Music dips between t=2s and t=4s, then ramps back up by t=5s
    /// AudioTrack(url: musicURL)
    ///     .volume(0.8)
    ///     .volumeRamp(start: 0.8, end: 0.3, during: CMTimeRange(start: 2.0, end: 4.0))
    ///     .volumeRamp(start: 0.3, end: 0.8, during: CMTimeRange(start: 4.0, end: 5.0))
    /// ```
    ///
    /// **Avoid overlap with the engine's implicit fade-in / fade-out / crossfade
    /// ranges.** AVFoundation rejects overlapping ramps; the engine drops conflicting
    /// volumeRamps with a console warning rather than throwing.
    public func volumeRamp(start: Double, end: Double, during range: CMTimeRange) -> AudioTrack {
        let ramp = VolumeRamp(startVolume: start, endVolume: end, range: range)
        return AudioTrack(url: url, volumeLevel: volumeLevel, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration, duckingLevel: duckingLevel, startTime: startTime, explicitDuration: explicitDuration, crossfadeDuration: crossfadeDuration, volumeRamps: volumeRamps + [ramp])
    }

    /// Add a volume automation ramp using a `ClosedRange<TimeInterval>` for the time
    /// boundaries. Convenience overload. Added in v0.8.3.
    public func volumeRamp(start: Double, end: Double, during range: ClosedRange<TimeInterval>) -> AudioTrack {
        let cmStart = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        let cmEnd = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        return volumeRamp(start: start, end: end, during: CMTimeRange(start: cmStart, end: cmEnd))
    }
}
