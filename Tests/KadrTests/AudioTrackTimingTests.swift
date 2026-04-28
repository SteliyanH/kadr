import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// Tests for v0.7 ``AudioTrack`` timing — `at(time:)` and `duration(_:)`.
///
/// Modifier-storage tests are pure unit tests; engine-integration tests use the
/// shared `sample.mp3` fixture (or `sample.wav` fallback) and assert on the resulting
/// `AVMutableComposition`'s audio track time ranges.
struct AudioTrackTimingTests {

    private let preset: Preset = .auto

    private func loadTestVideoURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "mov") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.mov"))
        }
        return url
    }

    private func loadTestAudioURL() throws -> URL {
        if let url = Bundle.module.url(forResource: "sample", withExtension: "mp3") {
            return url
        }
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "wav") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.wav"))
        }
        return url
    }

    // MARK: - Modifier storage (pure)

    @Test func startTimeDefaultsToNil() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
        #expect(track.startTime == nil)
    }

    @Test func explicitDurationDefaultsToNil() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
        #expect(track.explicitDuration == nil)
    }

    @Test func atCMTimeStoresValue() {
        let t = CMTime(seconds: 2.5, preferredTimescale: 600)
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null")).at(time: t)
        #expect(track.startTime == t)
    }

    @Test func atTimeIntervalStoresValue() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null")).at(time: 1.5)
        #expect(abs(CMTimeGetSeconds(track.startTime!) - 1.5) < 0.001)
    }

    @Test func durationCMTimeStoresValue() {
        let d = CMTime(seconds: 1.5, preferredTimescale: 600)
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null")).duration(d)
        #expect(track.explicitDuration == d)
    }

    @Test func durationTimeIntervalStoresValue() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null")).duration(1.5)
        #expect(abs(CMTimeGetSeconds(track.explicitDuration!) - 1.5) < 0.001)
    }

    @Test func timingComposesWithVolumeFadesAndDucking() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .at(time: 2.0)
            .duration(1.5)
            .volume(0.8)
            .fadeIn(0.3)
            .fadeOut(0.3)
            .ducking(0.4)
        #expect(abs(CMTimeGetSeconds(track.startTime!) - 2.0) < 0.001)
        #expect(abs(CMTimeGetSeconds(track.explicitDuration!) - 1.5) < 0.001)
        #expect(track.volumeLevel == 0.8)
        #expect(track.duckingLevel == 0.4)
    }

    @Test func timingPreservedThroughModifierChainInAnyOrder() {
        // Order should not matter — timing fields survive every modifier call.
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .volume(0.5)
            .at(time: 1.0)
            .fadeIn(0.2)
            .duration(2.0)
            .fadeOut(0.2)
            .ducking(0.5)
        #expect(abs(CMTimeGetSeconds(track.startTime!) - 1.0) < 0.001)
        #expect(abs(CMTimeGetSeconds(track.explicitDuration!) - 2.0) < 0.001)
    }

    // MARK: - Engine integration

    @Test func audioInsertedAtStartTime() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let result = try await CompositionBuilder.build(
            from: [
                VideoClip(url: videoURL).trimmed(to: 0...3),
            ],
            audioTracks: [
                AudioTrack(url: audioURL).at(time: 1.0),
            ],
            preset: preset
        )
        let audioTracks = result.composition.tracks(withMediaType: .audio)
        let bgTrack = try #require(audioTracks.last)
        // AVMutableComposition inserts a leading empty segment when content starts past
        // t=0. Find the first non-empty segment and assert it begins at 1.0s.
        let firstNonEmpty = try #require(bgTrack.segments.first(where: { !$0.isEmpty }))
        let targetStart = firstNonEmpty.timeMapping.target.start
        #expect(abs(CMTimeGetSeconds(targetStart) - 1.0) < 0.05)
    }

    @Test func audioCappedToExplicitDuration() async throws {
        // Use a clip-audio length comfortably > 1.5s so the explicit cap is the binding
        // constraint. We loop / extend by trimming a longer video; sample.mp3 may itself
        // be shorter than 1.5s, so we assert relative behavior: the cap is honored
        // *or* the asset's natural length wins, whichever is smaller. The point of this
        // test is that explicit cap shortens — not that it can extend past the asset.
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let audioAsset = AVURLAsset(url: audioURL)
        let assetDuration = try await audioAsset.load(.duration)

        let cap = CMTime(seconds: 0.3, preferredTimescale: 600)  // shorter than any plausible asset
        let result = try await CompositionBuilder.build(
            from: [
                VideoClip(url: videoURL).trimmed(to: 0...5),
            ],
            audioTracks: [
                AudioTrack(url: audioURL).at(time: 1.0).duration(cap),
            ],
            preset: preset
        )
        let audioTracks = result.composition.tracks(withMediaType: .audio)
        let bgTrack = try #require(audioTracks.last)
        let nonEmpty = bgTrack.segments.filter { !$0.isEmpty }
        let total = nonEmpty.reduce(CMTime.zero) {
            CMTimeAdd($0, $1.timeMapping.target.duration)
        }
        let expected = CMTimeGetSeconds(CMTimeMinimum(cap, assetDuration))
        #expect(abs(CMTimeGetSeconds(total) - expected) < 0.05)
    }

    @Test func audioStartingAfterCompositionEndIsSkipped() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        // Composition is 2s; the audio is pinned to t=10s (way past the end).
        let result = try await CompositionBuilder.build(
            from: [
                VideoClip(url: videoURL).trimmed(to: 0...2),
            ],
            audioTracks: [
                AudioTrack(url: audioURL).at(time: 10.0),
            ],
            preset: preset
        )
        let audioTracks = result.composition.tracks(withMediaType: .audio)
        // Only the clip-audio track. The skipped bg track should not appear.
        // (Clip audio may or may not exist depending on the asset; we assert no
        // bg audio exists by counting tracks <= 1.)
        #expect(audioTracks.count <= 1)
    }
}
