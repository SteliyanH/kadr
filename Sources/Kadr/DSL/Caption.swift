import Foundation
import CoreMedia
import AVFoundation

/// A single caption cue — text shown on screen for a specific time range. Attach to a
/// composition via ``Video/captions(_:)`` and the engine bakes it into the export as an
/// `AVMetadataItem` with the `commonKeyDescription` identifier and the cue's
/// `time` / `duration`. Players that surface video metadata (Apple Photos, system
/// quick-look, AVPlayer's metadata APIs) read these directly.
///
/// **Scope (v0.9.2).** Core ships only the in-memory value type plus the engine writer.
/// File-format parsing and authoring (SRT, VTT, iTT) live in the
/// [`kadr-captions`](https://github.com/SteliyanH/kadr-captions) adapter package; the
/// adapter produces `Caption` values that flow into ``Video/captions(_:)`` here.
///
/// ```swift
/// // Hand-built captions
/// Video {
///     VideoClip(url: clipURL).trimmed(to: 0...10)
/// }
/// .captions([
///     Caption(text: "Hello", timeRange: CMTimeRange(
///         start: .zero,
///         duration: CMTime(seconds: 2, preferredTimescale: 600)
///     )),
///     Caption(text: "World", timeRange: CMTimeRange(
///         start: CMTime(seconds: 2, preferredTimescale: 600),
///         duration: CMTime(seconds: 3, preferredTimescale: 600)
///     )),
/// ])
///
/// // From a parsed SRT (kadr-captions adapter)
/// import KadrCaptions
/// let cues = try await Caption.load(srt: srtURL)
/// video.captions(cues)
/// ```
///
/// **Multiple `.captions(_:)` calls accumulate.** Later calls append to the previous
/// list. Overlapping cues are allowed at the metadata layer; player UIs may render only
/// one at a time.
public struct Caption: Sendable, Equatable {

    /// Caption text. Plain string in v0.9.2 — no styling. Styled / animated captions
    /// belong in the `kadr-captions` adapter and map onto v0.8 ``TextOverlay`` +
    /// ``TextAnimation`` instead.
    public let text: String

    /// Composition-time range during which this caption is visible. `start` is the time
    /// the cue appears; `start + duration` is the time it disappears.
    public let timeRange: CMTimeRange

    public init(text: String, timeRange: CMTimeRange) {
        self.text = text
        self.timeRange = timeRange
    }
}

extension Caption {

    /// Build an `AVMetadataItem` carrying this cue's text + timing for export. Internal —
    /// the engine writer iterates an array of these and assigns to
    /// `AVAssetExportSession.metadata`. Pure (no side effects); exposed for unit tests.
    internal func makeMetadataItem() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierDescription
        item.value = text as NSString
        item.time = timeRange.start
        item.duration = timeRange.duration
        item.extendedLanguageTag = "und"
        return item
    }
}
