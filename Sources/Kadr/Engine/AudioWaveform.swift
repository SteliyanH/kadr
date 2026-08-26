import Foundation
import AVFoundation
import CoreMedia

/// A pre-computed audio waveform — a fixed-length array of normalized peak values
/// suitable for rendering as a row of bars or a polyline.
///
/// Each entry is a non-negative `Float` typically in `0.0...1.0` (the loader
/// normalizes to the peak sample magnitude observed in the asset, so a near-silent
/// file still renders visibly). Index `0` is the start of the asset; `peaks.count - 1`
/// is the end.
///
/// Build via ``AudioWaveformLoader/load(url:sampleCount:)``. Treat the value as
/// expensive-to-produce and cache for reuse — kadr-ui's `TimelineView` does this
/// internally when `showAudioWaveforms` is enabled.
///
/// Lives in kadr core rather than a view package, for the same reason
/// ``ThumbnailGenerator`` does: it is a read of the media, not a rendering of it,
/// and it needs nothing beyond AVFoundation. Drawing the peaks is the view
/// package's job; producing them is not. Moved here in v0.18 — it had been
/// stranded in kadr-ui, so a headless consumer had to import SwiftUI to reach it.
public struct AudioWaveform: Sendable, Equatable {

    /// Peak values, ordered start-to-end of the source asset. Always non-negative.
    public let peaks: [Float]

    public init(peaks: [Float]) {
        self.peaks = peaks
    }

    /// Empty waveform (no peaks). Useful as a fallback while loading.
    public static let empty = AudioWaveform(peaks: [])
}

extension AudioWaveform {

    /// This waveform resampled to exactly `bucketCount` peaks.
    ///
    /// Renderers need this: a waveform is extracted once at some sample count and
    /// then drawn into whatever width the view happens to have, which is rarely the
    /// same number. Decimates when the waveform has more peaks than buckets and
    /// stretches when it has fewer, so the result always has `bucketCount` entries.
    ///
    /// Returns an empty waveform for `bucketCount <= 0`.
    ///
    /// Added in v0.19. Before it, the only way to resample was an internal helper —
    /// which is why the move of this type into core in v0.18 left kadr-ui unable to
    /// draw what it had just been handed.
    public func resampled(to bucketCount: Int) -> AudioWaveform {
        AudioWaveform(peaks: AudioWaveform.bucketPeaks(samples: peaks, bucketCount: bucketCount))
    }
}

/// Pure helpers for waveform sample math. Surface as nonisolated statics so they
/// can run inside an `AVAssetReader` background queue without actor hops.
extension AudioWaveform {

    /// Bucket-peaks `samples` (raw signed amplitudes in `-1.0...1.0`) into exactly
    /// `bucketCount` non-negative peak values. Each bucket's peak is the maximum
    /// absolute sample inside it.
    ///
    /// `samples.count == 0` or `bucketCount <= 0` returns an empty array. When
    /// `samples.count < bucketCount`, the result is padded with zeros for missing
    /// buckets so consumers always receive `bucketCount` entries.
    nonisolated static func bucketPeaks(samples: [Float], bucketCount: Int) -> [Float] {
        guard bucketCount > 0 else { return [] }
        guard !samples.isEmpty else {
            return Array(repeating: 0, count: bucketCount)
        }
        if samples.count <= bucketCount {
            // Map each sample into one bucket; pad the remainder with zeros.
            var out = Array(repeating: Float(0), count: bucketCount)
            for i in samples.indices {
                out[i] = abs(samples[i])
            }
            return out
        }
        // Even bucketing: each bucket spans roughly samples.count / bucketCount
        // entries. Use floating-point boundaries to avoid systematic drift on
        // non-divisible counts.
        var out: [Float] = []
        out.reserveCapacity(bucketCount)
        let step = Double(samples.count) / Double(bucketCount)
        for i in 0..<bucketCount {
            let startIdx = Int((Double(i) * step).rounded(.down))
            let endIdx = min(samples.count, Int((Double(i + 1) * step).rounded(.down)))
            var peak: Float = 0
            for j in startIdx..<endIdx {
                let mag = abs(samples[j])
                if mag > peak { peak = mag }
            }
            out.append(peak)
        }
        return out
    }

    /// Scale every peak so the maximum becomes `1.0`, preserving relative shape.
    /// A waveform with all-zero peaks is returned unchanged. Pure.
    nonisolated static func normalized(_ peaks: [Float]) -> [Float] {
        guard let maxPeak = peaks.max(), maxPeak > 0 else { return peaks }
        return peaks.map { $0 / maxPeak }
    }
}

// MARK: - Rendering
