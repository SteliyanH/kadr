import Testing
import Foundation
@testable import Kadr
import CoreMedia

/// Tests for v0.20 — ``ExportQuality`` and ``Video/quality(_:)``.
///
/// The value type and its arithmetic land before the encoder that honours them, so
/// the bitrate solving is testable on its own. A file-size target is a division
/// people will check by hand against the file they get, and it should be a division
/// they can follow.
struct ExportQualityTests {

    private func seconds(_ s: Double) -> CMTime {
        CMTime(seconds: s, preferredTimescale: 600)
    }

    // MARK: - The default

    @Test func videoDefaultsToAutomatic() {
        let video = Video { ImageClip(PlatformImage(), duration: seconds(1)) }
        #expect(video.quality == .automatic)
    }

    @Test func automaticResolvesToNoBitrate() {
        #expect(ExportQuality.automatic.resolvedBitrate(forDuration: seconds(10)) == nil)
    }

    // MARK: - Explicit bitrate

    @Test func explicitBitratePassesThrough() {
        #expect(ExportQuality.bitrate(4_000_000).resolvedBitrate(forDuration: seconds(10)) == 4_000_000)
    }

    /// A non-positive bitrate is not a request for a tiny file, it is a mistake.
    /// Resolving it to `nil` hands the decision back to the encoder rather than
    /// asking for zero bits.
    @Test func nonPositiveBitrateFallsBackToAutomatic() {
        #expect(ExportQuality.bitrate(0).resolvedBitrate(forDuration: seconds(10)) == nil)
        #expect(ExportQuality.bitrate(-1).resolvedBitrate(forDuration: seconds(10)) == nil)
    }

    // MARK: - File-size target

    /// 10 MB over 10 seconds: 80,000,000 bits total, less 128 kbps × 10s of audio
    /// (1,280,000), leaves 78,720,000 for video — 7,872,000 bps.
    @Test func fileSizeSolvesForBitrateWithAudioReserved() {
        let q = ExportQuality.fileSize(bytes: 10_000_000)
        #expect(q.resolvedBitrate(forDuration: seconds(10)) == 7_872_000)
    }

    @Test func fileSizeScalesInverselyWithDuration() {
        let q = ExportQuality.fileSize(bytes: 10_000_000)
        let short = try! #require(q.resolvedBitrate(forDuration: seconds(5)))
        let long = try! #require(q.resolvedBitrate(forDuration: seconds(20)))
        #expect(short > long, "The same file size over a longer video means fewer bits per second")
    }

    /// A duration of zero is not a bitrate problem, and dividing by it is not an
    /// answer. Hand it back to the encoder.
    @Test func fileSizeWithZeroDurationResolvesToNil() {
        #expect(ExportQuality.fileSize(bytes: 10_000_000).resolvedBitrate(forDuration: .zero) == nil)
    }

    /// A budget smaller than the audio allowance leaves nothing for video. Returning
    /// a tiny or negative bitrate would produce an unwatchable file that still missed
    /// the target; `nil` at least produces a working one.
    @Test func fileSizeTooSmallForAudioResolvesToNil() {
        // 60s at 128 kbps is 960,000 bytes of audio alone.
        #expect(ExportQuality.fileSize(bytes: 100_000).resolvedBitrate(forDuration: seconds(60)) == nil)
    }

    @Test func fileSizeWithNonPositiveBytesResolvesToNil() {
        #expect(ExportQuality.fileSize(bytes: 0).resolvedBitrate(forDuration: seconds(10)) == nil)
        #expect(ExportQuality.fileSize(bytes: -5).resolvedBitrate(forDuration: seconds(10)) == nil)
    }

    // MARK: - The modifier

    @Test func qualityIsChainableAndLastWins() {
        let video = Video { ImageClip(PlatformImage(), duration: seconds(1)) }
            .quality(.bitrate(1_000_000))
            .quality(.fileSize(bytes: 5_000_000))
        #expect(video.quality == .fileSize(bytes: 5_000_000))
    }

    /// Guards the copy-with refactor: quality must not disturb its neighbours.
    @Test func qualityPreservesEveryOtherProperty() {
        let base = Video { ImageClip(PlatformImage(), duration: seconds(2)) }
            .preset(.tiktok)
            .captions([Caption(text: "hi", timeRange: CMTimeRange(start: .zero, duration: seconds(1)))])

        let tuned = base.quality(.bitrate(3_000_000))

        #expect(tuned.quality == .bitrate(3_000_000))
        #expect(tuned.preset.resolution == base.preset.resolution)
        #expect(tuned.captions.count == base.captions.count)
        #expect(tuned.clips.count == base.clips.count)
        #expect(tuned.duration == base.duration)
    }

    @Test func presetAndQualityAreIndependent() {
        let video = Video { ImageClip(PlatformImage(), duration: seconds(1)) }
            .quality(.bitrate(2_000_000))
            .preset(.square)
        #expect(video.quality == .bitrate(2_000_000), "preset(_:) must not reset quality")
        #expect(video.preset.resolution.width == 1080)
    }
}
