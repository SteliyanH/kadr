import Foundation
import AVFoundation
import CoreMedia
import Accelerate

/// Loads an audio asset and reduces it to a fixed-length ``AudioWaveform`` for
/// rendering. The reader streams PCM samples via `AVAssetReader`, downmixes to mono
/// (averaging channels) when the source is multi-channel, and bucket-peaks the
/// resulting magnitudes into `sampleCount` entries.
///
/// `load(url:sampleCount:)` is asynchronous and may take several hundred ms on long
/// assets — call it off the main thread (which is what `await` already does) and
/// cache the result. KadrUI's `TimelineView` caches per-track in `@State`.
public enum AudioWaveformLoader {

    /// Render `url`'s audio to a normalized peak array of length `sampleCount`.
    ///
    /// - Parameters:
    ///   - url: A file URL pointing at any AVAsset-readable audio (mp3, m4a, wav, mov...).
    ///   - sampleCount: Number of peaks in the returned waveform. Larger values give
    ///     finer detail at the cost of memory; values around 100–500 work well for
    ///     a TimelineView lane.
    /// - Returns: An ``AudioWaveform`` whose `peaks` array has exactly
    ///   `sampleCount` elements, normalized so the max peak is `1.0`. Returns
    ///   ``AudioWaveform/empty`` for unreadable assets, asset-with-no-audio, or
    ///   `sampleCount <= 0`.
    public static func load(url: URL, sampleCount: Int) async throws -> AudioWaveform {
        guard sampleCount > 0 else { return .empty }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else { return .empty }

        // Request linear PCM, 32-bit float, interleaved by channel — easy to
        // downmix and to feed straight into bucketing.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            return .empty
        }
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        guard reader.canAdd(trackOutput) else { return .empty }
        reader.add(trackOutput)
        guard reader.startReading() else { return .empty }

        // Determine the number of channels so we can downmix.
        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        let channelCount: Int = formatDescriptions
            .compactMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
            .map { Int($0) }
            .first ?? 1

        // Stream samples. We accumulate a mono buffer of magnitudes (already abs-ed
        // and downmixed) and bucket at the end. For very long assets this could be
        // memory-heavy; the trade-off is simpler math and one-pass bucketing.
        var monoMagnitudes: [Float] = []
        monoMagnitudes.reserveCapacity(1 << 20)  // 1M samples ≈ 4 MB; grow as needed.

        while reader.status == .reading, let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr, let pointer = dataPointer else { continue }

            let floatCount = totalLength / MemoryLayout<Float>.size
            let floats = UnsafeBufferPointer<Float>(
                start: pointer.withMemoryRebound(to: Float.self, capacity: floatCount) { $0 },
                count: floatCount
            )

            if channelCount <= 1 {
                // Already mono — take absolute values.
                for sample in floats {
                    monoMagnitudes.append(abs(sample))
                }
            } else {
                // Downmix interleaved channels: avg of magnitudes per frame.
                let frameCount = floatCount / channelCount
                for f in 0..<frameCount {
                    var sum: Float = 0
                    for c in 0..<channelCount {
                        sum += abs(floats[f * channelCount + c])
                    }
                    monoMagnitudes.append(sum / Float(channelCount))
                }
            }
        }

        guard reader.status == .completed else { return .empty }

        let buckets = AudioWaveform.bucketPeaks(samples: monoMagnitudes, bucketCount: sampleCount)
        return AudioWaveform(peaks: AudioWaveform.normalized(buckets))
    }
}
