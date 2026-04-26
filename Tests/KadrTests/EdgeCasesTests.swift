import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// Edge-case bug bash for the v0.2 surface — combinations and boundaries that the
/// individual feature suites don't exercise.
struct EdgeCasesTests {

    private func testOutputURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func loadTestVideoURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "mov") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.mov"))
        }
        return url
    }

    private func loadTestAudioURL() throws -> URL {
        if let url = Bundle.module.url(forResource: "sample", withExtension: "mp3") { return url }
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "wav") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.wav"))
        }
        return url
    }

    // MARK: - 1. Mixed-timescale CMTime

    /// Trim with timescale-30, fade with timescale-60. Validates that CMTimeCompare
    /// and CMTimeMultiplyByRatio handle different timescales correctly without losing
    /// frame precision when comparing.
    @Test func mixedTimescaleTrimAndFade() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("mixed_timescale")

        // 90 frames @ 30fps = exactly 3.0 seconds
        let clipRange = CMTimeRange(
            start: .zero,
            duration: CMTime(value: 90, timescale: 30)
        )
        // 30 frames @ 60fps = exactly 0.5 seconds — but expressed at a different timescale
        let fadeDur = CMTime(value: 30, timescale: 60)

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: clipRange)
            Transition.fade(duration: fadeDur)
            VideoClip(url: videoURL).trimmed(to: clipRange)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        // Total = 3 + 3 = 6 (fade has no overlap)
        let asset = AVURLAsset(url: result)
        let actual = CMTimeGetSeconds(try await asset.load(.duration))
        #expect(actual > 5.5)
        #expect(actual < 6.5)

        try? FileManager.default.removeItem(at: result)
    }

    /// Dissolve overlap math across mismatched timescales.
    @Test func mixedTimescaleDissolve() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("mixed_dissolve")

        // 60 frames @ 30fps = 2.0s
        let clipRange = CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30))
        // 12 frames @ 24fps = 0.5s
        let dissolveDur = CMTime(value: 12, timescale: 24)

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: clipRange)
            Transition.dissolve(duration: dissolveDur)
            VideoClip(url: videoURL).trimmed(to: clipRange)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        // Total = 2 + 2 - 0.5 = 3.5
        let actual = CMTimeGetSeconds(try await AVURLAsset(url: result).load(.duration))
        #expect(actual > 3.0)
        #expect(actual < 4.0)

        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - 2. Speed × reverse

    @Test func speedAndReversedCombined() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("speed_reversed")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3).reversed().speed(2.0)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        // 3s reversed → 3s. 3s @ 2x → 1.5s.
        let actual = CMTimeGetSeconds(try await AVURLAsset(url: result).load(.duration))
        #expect(actual > 1.0)
        #expect(actual < 2.0)

        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - 3. Speed × transition with non-trivial rates

    /// Speed of 1.5 (irrational ratio) combined with a fade transition. CMTimeMultiplyByFloat64
    /// is the one place where Float64 touches the math; this covers it.
    @Test func irrationalSpeedWithFade() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("speed_irrational")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3).speed(1.5)
            Transition.fade(duration: 0.4)
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        // Clip A: 3 / 1.5 = 2s scaled. Clip B: 3s. Fade: no overlap. Total ≈ 5s
        let actual = CMTimeGetSeconds(try await AVURLAsset(url: result).load(.duration))
        #expect(actual > 4.5)
        #expect(actual < 5.5)

        try? FileManager.default.removeItem(at: result)
    }

    /// Speed scaling combined with dissolve overlap. Tests whether the scaled duration
    /// flows correctly into the transition validation path.
    @Test func speedThenDissolve() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("speed_dissolve_combo")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...4).speed(0.5)  // becomes 8s
            Transition.dissolve(duration: 0.5)
            VideoClip(url: videoURL).trimmed(to: 0...3)             // 3s
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        // 8 + 3 - 0.5 overlap = 10.5
        let actual = CMTimeGetSeconds(try await AVURLAsset(url: result).load(.duration))
        #expect(actual > 9.5)
        #expect(actual < 11.5)

        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - 4. Boundary clips

    /// Clip duration exactly equal to the transition's per-side requirement. The validation
    /// uses `>` (strict greater), so this should succeed (boundary is inclusive).
    @Test func clipExactlyMatchesTransitionPerSide() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("exact_boundary")

        // fade(2.0) → perSide = 1.0. Clip A is exactly 1.0s.
        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...1)
            Transition.fade(duration: 2.0)
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    /// Dissolve duration exactly equal to the shorter clip's duration. perSide = duration,
    /// so duration == clipDur should pass (the entire clip becomes the cross-fade region).
    @Test func dissolveEqualsShorterClip() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("dissolve_equals_clip")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...1)
            Transition.dissolve(duration: 1.0)  // = full duration of clip A
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - 5. Multiple background tracks with ducking

    /// Two background tracks both with ducking — they should each get their own
    /// independent volume-ramp params on their own AVMutableCompositionTrack.
    @Test func multipleBackgroundTracksWithDucking() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let outputURL = testOutputURL("multi_bg_ducking")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...4)
        }
        .audio {
            AudioTrack(url: audioURL).volume(0.6).ducking(0.2)
            AudioTrack(url: audioURL).volume(0.4).ducking(0.1)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        // Verify both audio tracks made it into the output composition
        let asset = AVURLAsset(url: result)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        // The output mp4 may flatten to a single audio track via mixdown — we just
        // require *some* audio survived; the ducking ramps don't expose themselves
        // structurally here, only audibly.
        #expect(!audioTracks.isEmpty)

        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - 6. Interactions surfaced during the audit

    /// `Video.duration` for a composition mixing trimmed and untrimmed VideoClips:
    /// the untrimmed clip contributes .zero (synchronously), so the total will be wrong
    /// — but it shouldn't crash or produce a negative value.
    @Test func videoDurationWithUntrimmedClip() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let video = Video {
            VideoClip(url: url).trimmed(to: 0...5)
            VideoClip(url: url)  // duration = .zero
        }
        let total = CMTimeGetSeconds(video.duration)
        // Should equal the trimmed contribution alone — 5.0
        #expect(abs(total - 5.0) < 0.001)
        #expect(total >= 0)
    }

    /// Untrimmed VideoClip combined with a transition. The clip's synchronous
    /// `.duration` is `.zero` (asset isn't loaded yet), so transition validation
    /// will see perSide > .zero and reject — even when the underlying asset is
    /// plenty long. This is surprising behavior worth documenting.
    @Test func untrimmedClipInTransitionThrows() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("untrimmed_in_trans")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL)  // untrimmed → duration .zero synchronously
                Transition.fade(duration: 0.5)
                VideoClip(url: videoURL).trimmed(to: 0...3)
            }
            .export(to: outputURL)
        }
    }

    /// fade(duration:) of zero should be rejected by validation (positive-duration check).
    @Test func zeroDurationTransitionThrows() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("zero_dur")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL).trimmed(to: 0...3)
                Transition.fade(duration: .zero)
                VideoClip(url: videoURL).trimmed(to: 0...3)
            }
            .export(to: outputURL)
        }
    }
}
