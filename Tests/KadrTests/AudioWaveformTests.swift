import Testing
import Foundation
@testable import Kadr

/// Unit tests for the pure waveform helpers — bucketing math + normalization.
/// Loader tests would need real audio fixtures; keeping this file focused on math
/// (the loader is exercised in the example app and through manual smoke tests).
struct AudioWaveformTests {

    // Moved from kadr-ui in v0.18 along with the types they cover: waveform
    // extraction is a read of the media, not a rendering of it.


    // MARK: - bucketPeaks

    @Test func bucketEmptyInputReturnsZerosOfBucketCount() {
        let result = AudioWaveform.bucketPeaks(samples: [], bucketCount: 4)
        #expect(result == [0, 0, 0, 0])
    }

    @Test func bucketWithZeroBucketCountReturnsEmpty() {
        let result = AudioWaveform.bucketPeaks(samples: [0.5, -0.3], bucketCount: 0)
        #expect(result.isEmpty)
    }

    @Test func bucketSamplesShorterThanBucketCountPadsWithZeros() {
        // 3 samples into 5 buckets — first 3 get peaks, last 2 are zero.
        let result = AudioWaveform.bucketPeaks(samples: [0.2, -0.5, 0.8], bucketCount: 5)
        #expect(result.count == 5)
        #expect(result[0] == 0.2)
        #expect(result[1] == 0.5)
        #expect(result[2] == 0.8)
        #expect(result[3] == 0)
        #expect(result[4] == 0)
    }

    @Test func bucketTakesAbsoluteValuesPerBucket() {
        // 4 samples into 2 buckets — each bucket is the abs-max of its half.
        let result = AudioWaveform.bucketPeaks(samples: [0.1, -0.6, 0.3, -0.9], bucketCount: 2)
        #expect(result.count == 2)
        #expect(result[0] == 0.6)  // max(|0.1|, |-0.6|) = 0.6
        #expect(result[1] == 0.9)  // max(|0.3|, |-0.9|) = 0.9
    }

    @Test func bucketHandlesNonDivisibleCounts() {
        // 7 samples into 3 buckets — boundaries fall on non-integers; helper rounds down.
        let samples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]
        let result = AudioWaveform.bucketPeaks(samples: samples, bucketCount: 3)
        #expect(result.count == 3)
        // Each bucket is a contiguous slice; max value is the bucket's peak.
        for peak in result { #expect(peak > 0) }
    }

    // MARK: - normalized

    @Test func normalizeAllZeroReturnsUnchanged() {
        let result = AudioWaveform.normalized([0, 0, 0])
        #expect(result == [0, 0, 0])
    }

    @Test func normalizeScalesMaxToOne() {
        let result = AudioWaveform.normalized([0.1, 0.5, 0.25])
        #expect(abs(result[0] - 0.2) < 0.0001)
        #expect(result[1] == 1.0)
        #expect(abs(result[2] - 0.5) < 0.0001)
    }

    @Test func normalizePreservesShape() {
        let original: [Float] = [0.2, 0.4, 0.8, 0.4, 0.2]
        let result = AudioWaveform.normalized(original)
        // Ratios survive scaling: result[2] should be 4× result[0].
        #expect(abs(result[2] - 4 * result[0]) < 0.0001)
    }

    // MARK: - AudioWaveform value type

    @Test func emptyWaveformHasNoPeaks() {
        #expect(AudioWaveform.empty.peaks.isEmpty)
    }

    @Test func waveformEquatable() {
        let a = AudioWaveform(peaks: [0.1, 0.2, 0.3])
        let b = AudioWaveform(peaks: [0.1, 0.2, 0.3])
        let c = AudioWaveform(peaks: [0.1, 0.2])
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - resampled(to:) — v0.19
    //
    // The move in v0.18 put the value type in core and left the only helper that
    // reshapes it internal, so kadr-ui's Shape could not draw the waveform core
    // had just handed it. This is the public surface that closes that.

    @Test func resampledProducesExactlyTheRequestedCount() {
        let w = AudioWaveform(peaks: [0.1, 0.9, 0.4, 0.6, 0.2])
        #expect(w.resampled(to: 3).peaks.count == 3)
        #expect(w.resampled(to: 12).peaks.count == 12)
    }

    @Test func resampledToZeroOrNegativeIsEmpty() {
        let w = AudioWaveform(peaks: [0.1, 0.9])
        #expect(w.resampled(to: 0).peaks.isEmpty)
        #expect(w.resampled(to: -4).peaks.isEmpty)
    }

    @Test func resamplingKeepsThePeakOfEachBucket() {
        let w = AudioWaveform(peaks: [0.1, 0.9, 0.2, 0.8])
        #expect(w.resampled(to: 2).peaks == [0.9, 0.8])
    }

    @Test func resamplingAnEmptyWaveformPadsWithZeros() {
        #expect(AudioWaveform.empty.resampled(to: 3).peaks == [0, 0, 0])
    }
}

