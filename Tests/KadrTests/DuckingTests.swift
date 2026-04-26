import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

struct DuckingTests {

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
        if let url = Bundle.module.url(forResource: "sample", withExtension: "mp3") {
            return url
        }
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "wav") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.wav"))
        }
        return url
    }

    // MARK: - Modifier composition

    @Test func duckingDefaultIsNil() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
        #expect(track.duckingLevel == nil)
    }

    @Test func duckingStoresValue() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null")).ducking(0.3)
        #expect(track.duckingLevel == 0.3)
    }

    @Test func duckingComposesWithVolumeAndFades() {
        let track = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .volume(0.8)
            .fadeIn(1.0)
            .fadeOut(1.0)
            .ducking(0.4)
        #expect(track.volumeLevel == 0.8)
        #expect(abs(CMTimeGetSeconds(track.fadeInDuration) - 1.0) < 0.001)
        #expect(abs(CMTimeGetSeconds(track.fadeOutDuration) - 1.0) < 0.001)
        #expect(track.duckingLevel == 0.4)
    }

    // MARK: - Export

    @Test func exportWithDucking() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let outputURL = testOutputURL("ducking_basic")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)  // contributes audio
        }
        .audio { AudioTrack(url: audioURL).ducking(0.3) }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func duckingWithMutedClipDoesNotDuck() async throws {
        // Muted clip contributes no audio → music should play at full level (no clip-audio range to duck around)
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let outputURL = testOutputURL("ducking_muted")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3).muted()
        }
        .audio { AudioTrack(url: audioURL).ducking(0.3) }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func duckingWithTransition() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let outputURL = testOutputURL("ducking_transition")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
            Transition.dissolve(duration: 0.4)
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .audio { AudioTrack(url: audioURL).volume(0.8).ducking(0.2) }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - Validation

    @Test func duckingNegativeThrows() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let outputURL = testOutputURL("ducking_neg")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL).trimmed(to: 0...2)
            }
            .audio { AudioTrack(url: audioURL).ducking(-0.1) }
            .export(to: outputURL)
        }
    }

    @Test func duckingAboveOneThrows() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let outputURL = testOutputURL("ducking_high")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL).trimmed(to: 0...2)
            }
            .audio { AudioTrack(url: audioURL).ducking(1.5) }
            .export(to: outputURL)
        }
    }

    @Test func duckingAtBoundsExports() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()

        let zero = testOutputURL("ducking_zero")
        _ = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...2)
        }
        .audio { AudioTrack(url: audioURL).ducking(0.0) }
        .export(to: zero)
        #expect(FileManager.default.fileExists(atPath: zero.path))
        try? FileManager.default.removeItem(at: zero)

        let one = testOutputURL("ducking_one")
        _ = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...2)
        }
        .audio { AudioTrack(url: audioURL).ducking(1.0) }
        .export(to: one)
        #expect(FileManager.default.fileExists(atPath: one.path))
        try? FileManager.default.removeItem(at: one)
    }
}
