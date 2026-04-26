import Foundation

/// Errors thrown by Kadr's public API during validation or export.
public enum KadrError: Error, Sendable {
    /// A `URL` did not point at a usable asset (no video track, unreadable, etc.).
    case invalidURL(URL)

    /// The source asset is in a format Kadr can't decode on this platform.
    case unsupportedFormat(String)

    /// `Video.export(to:)` was called on a composition with zero clips.
    case noClipsProvided

    /// The underlying `AVAssetExportSession` failed. The wrapped error is the original
    /// AVFoundation `NSError` for diagnostics.
    case exportFailed(underlying: any Error)

    /// The export was aborted via ``Exporter/cancel()``.
    case cancelled

    /// A feature is on the roadmap but not yet wired through the engine. The string
    /// identifies which feature.
    case notYetImplemented(String)

    /// A transition's placement or duration is invalid (e.g. first/last clip, two
    /// adjacent transitions, duration exceeds adjacent clip duration). The string is
    /// a human-readable explanation suitable for surfacing to users.
    case invalidTransition(String)

    /// `VideoClip.speed(_:)` was called with a value outside `0.25...4.0`. The
    /// associated value is the offending rate, useful for programmatic clamping.
    case invalidSpeed(Double)

    /// `AudioTrack.ducking(_:)` was called with a value outside `0.0...1.0`. The
    /// associated value is the offending level.
    case invalidDuckingLevel(Double)
}
