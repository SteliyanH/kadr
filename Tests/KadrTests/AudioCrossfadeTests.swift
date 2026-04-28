import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// Tests for v0.8 Tier 4 — `AudioTrack.crossfade(_:)`.
///
/// Modifier-storage tests are pure unit tests. Engine integration uses the existing
/// sample audio fixture and asserts on `AVMutableAudioMixInputParameters` shape.
struct AudioCrossfadeTests {

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

    @Test func crossfadeDefaultsToNil() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
        #expect(track.crossfadeDuration == nil)
    }

    @Test func crossfadeCMTimeStoresValue() {
        let dur = CMTime(seconds: 1.5, preferredTimescale: 600)
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null")).crossfade(dur)
        #expect(track.crossfadeDuration == dur)
    }

    @Test func crossfadeTimeIntervalStoresValue() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null")).crossfade(0.75)
        #expect(abs(CMTimeGetSeconds(track.crossfadeDuration!) - 0.75) < 0.001)
    }

    @Test func crossfadeComposesWithVolumeFadesAndDucking() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .volume(0.8)
            .fadeIn(0.5)
            .fadeOut(0.5)
            .ducking(0.3)
            .crossfade(1.0)
        #expect(track.volumeLevel == 0.8)
        #expect(abs(CMTimeGetSeconds(track.fadeInDuration) - 0.5) < 0.001)
        #expect(abs(CMTimeGetSeconds(track.fadeOutDuration) - 0.5) < 0.001)
        #expect(track.duckingLevel == 0.3)
        #expect(abs(CMTimeGetSeconds(track.crossfadeDuration!) - 1.0) < 0.001)
    }

    @Test func crossfadePreservedThroughModifierChainInAnyOrder() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .crossfade(1.0)
            .at(time: 2.0)
            .duration(5.0)
            .volume(0.6)
        #expect(abs(CMTimeGetSeconds(track.crossfadeDuration!) - 1.0) < 0.001)
        #expect(abs(CMTimeGetSeconds(track.startTime!) - 2.0) < 0.001)
        #expect(abs(CMTimeGetSeconds(track.explicitDuration!) - 5.0) < 0.001)
        #expect(track.volumeLevel == 0.6)
    }

    @Test func crossfadeReplacesPreviousValueOnReCall() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .crossfade(1.0)
            .crossfade(0.5)
        #expect(abs(CMTimeGetSeconds(track.crossfadeDuration!) - 0.5) < 0.001)
    }

    // MARK: - Engine integration

    @Test func crossfadeEmitsAudioMixParametersForBothTracks() async throws {
        // Two overlapping background-audio tracks with crossfade on the first. Both
        // should produce mix params (= 2 entries in result.audioMix?.inputParameters).
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let result = try await CompositionBuilder.build(
            from: [
                VideoClip(url: videoURL).trimmed(to: 0...8),
            ],
            audioTracks: [
                AudioTrack(url: audioURL).at(time: 0).duration(5.0).crossfade(1.0),
                AudioTrack(url: audioURL).at(time: 4.0).duration(4.0),
            ],
            preset: preset
        )
        let mix = try #require(result.audioMix)
        #expect(mix.inputParameters.count == 2)
    }

    @Test func crossfadeOnNonOverlappingTracksFallsBackToNoOpRamp() async throws {
        // First track ends at t=3, second starts at t=5 — no overlap. Crossfade is
        // declared but doesn't apply. Engine treats it as no-op (no extra ramp).
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let result = try await CompositionBuilder.build(
            from: [VideoClip(url: videoURL).trimmed(to: 0...8)],
            audioTracks: [
                AudioTrack(url: audioURL).at(time: 0).duration(3.0).crossfade(1.0),
                AudioTrack(url: audioURL).at(time: 5.0).duration(2.0),
            ],
            preset: preset
        )
        // Mix params are still produced (each track contributes), but no engine error.
        let mix = try #require(result.audioMix)
        #expect(mix.inputParameters.count == 2)
    }

    @Test func crossfadeWithNoNextTrackIsNoOp() async throws {
        // Last track in the array can declare crossfade; engine ignores it (no next
        // track to fade to). Should still build successfully.
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let result = try await CompositionBuilder.build(
            from: [VideoClip(url: videoURL).trimmed(to: 0...3)],
            audioTracks: [
                AudioTrack(url: audioURL).crossfade(1.0),
            ],
            preset: preset
        )
        // Single mix param entry; no error from missing next track.
        let mix = try #require(result.audioMix)
        #expect(mix.inputParameters.count == 1)
    }
}
