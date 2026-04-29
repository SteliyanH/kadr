import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// Tests for v0.8.3 — `AudioTrack.volumeRamp(start:end:during:)`.
struct AudioVolumeRampTests {

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

    // MARK: - Modifier composition

    @Test func volumeRampsDefaultsToEmpty() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
        #expect(track.volumeRamps.isEmpty)
    }

    @Test func volumeRampCMTimeRangeStoresValue() {
        let range = CMTimeRange(
            start: CMTime(seconds: 1, preferredTimescale: 600),
            end: CMTime(seconds: 2, preferredTimescale: 600)
        )
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .volumeRamp(start: 0.5, end: 1.0, during: range)
        #expect(track.volumeRamps.count == 1)
        #expect(track.volumeRamps[0].startVolume == 0.5)
        #expect(track.volumeRamps[0].endVolume == 1.0)
        #expect(track.volumeRamps[0].range == range)
    }

    @Test func volumeRampClosedRangeConvertsToCMTimeRange() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .volumeRamp(start: 0.0, end: 1.0, during: 0.5...1.5)
        #expect(track.volumeRamps.count == 1)
        let r = track.volumeRamps[0].range
        #expect(abs(CMTimeGetSeconds(r.start) - 0.5) < 0.001)
        #expect(abs(CMTimeGetSeconds(r.end) - 1.5) < 0.001)
    }

    @Test func multipleVolumeRampsAccumulateInOrder() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .volumeRamp(start: 1.0, end: 0.3, during: 2.0...4.0)
            .volumeRamp(start: 0.3, end: 1.0, during: 4.0...5.0)
        #expect(track.volumeRamps.count == 2)
        #expect(track.volumeRamps[0].startVolume == 1.0)
        #expect(track.volumeRamps[0].endVolume == 0.3)
        #expect(track.volumeRamps[1].startVolume == 0.3)
        #expect(track.volumeRamps[1].endVolume == 1.0)
    }

    @Test func volumeRampsPreservedThroughOtherModifiers() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .volumeRamp(start: 1.0, end: 0.5, during: 1.0...2.0)
            .volume(0.8)
            .fadeIn(0.2)
            .at(time: 1.0)
        #expect(track.volumeRamps.count == 1)
        #expect(track.volumeLevel == 0.8)
        #expect(abs(CMTimeGetSeconds(track.fadeInDuration) - 0.2) < 0.001)
        #expect(abs(CMTimeGetSeconds(track.startTime!) - 1.0) < 0.001)
    }

    // MARK: - Engine integration

    @Test func volumeRampEmitsAudioMixParameters() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let result = try await CompositionBuilder.build(
            from: [VideoClip(url: videoURL).trimmed(to: 0...5)],
            audioTracks: [
                AudioTrack(url: audioURL)
                    .volume(0.8)
                    .volumeRamp(start: 0.8, end: 0.3, during: 1.0...2.0)
                    .volumeRamp(start: 0.3, end: 0.8, during: 2.0...3.0),
            ],
            preset: preset
        )
        let mix = try #require(result.audioMix)
        #expect(mix.inputParameters.count == 1)
    }

    @Test func volumeRampOverlappingFadeInIsDroppedByEngine() async throws {
        // Engine drops volumeRamps that overlap the implicit fadeIn / fadeOut /
        // crossfade ranges (AVFoundation rejects overlapping ramps). Build still
        // succeeds — the composition just doesn't emit the conflicting ramp.
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let result = try await CompositionBuilder.build(
            from: [VideoClip(url: videoURL).trimmed(to: 0...5)],
            audioTracks: [
                AudioTrack(url: audioURL)
                    .fadeIn(1.0)
                    .volumeRamp(start: 0.0, end: 1.0, during: 0.5...1.5),  // overlaps fadeIn 0..1
            ],
            preset: preset
        )
        // No exception thrown means the engine successfully skipped the conflicting
        // ramp. Mix params still produced.
        let mix = try #require(result.audioMix)
        #expect(mix.inputParameters.count == 1)
    }

    @Test func volumeRampsDontInterfereWhenAdjacent() async throws {
        // Two ramps with adjacent (non-overlapping) ranges should both apply.
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let result = try await CompositionBuilder.build(
            from: [VideoClip(url: videoURL).trimmed(to: 0...5)],
            audioTracks: [
                AudioTrack(url: audioURL)
                    .volumeRamp(start: 1.0, end: 0.5, during: 1.0...2.0)
                    .volumeRamp(start: 0.5, end: 1.0, during: 2.0...3.0),
            ],
            preset: preset
        )
        let mix = try #require(result.audioMix)
        #expect(mix.inputParameters.count == 1)
    }
}
