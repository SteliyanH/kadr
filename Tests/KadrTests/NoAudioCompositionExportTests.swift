import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// Regression tests for https://github.com/SteliyanH/kadr/issues/201
///
/// When no clip contributes audio, `CompositionBuilder` used to leave an
/// empty audio track in the composition. That empty track fails the
/// `AVAssetExportSession` HEVC compatibility check, so `ExportEngine`
/// silently fell back to `AVAssetExportPresetPassthrough` — which cannot
/// apply a `videoComposition` and produced a plain copy of the first clip:
/// concatenation, trims, speed and transitions silently lost, with
/// `status == .completed` and no error.
///
/// `sample.mov` is video-only (h264, no audio track), so every test here
/// exercises the no-audio composition shape. All assertions run under an
/// HEVC preset, which is where the compatibility check rejects the
/// empty-audio-track composition.
struct NoAudioCompositionExportTests {

    private func testOutputURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func loadTestVideoURL() throws -> URL {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "sample", withExtension: "mov") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.mov"))
        }
        return url
    }

    /// The passthrough fallback copies the h264 source bitstream, so a
    /// successful HEVC re-encode is itself proof the fallback did not engage.
    private func expectHEVC(_ asset: AVURLAsset, _ sourceLocation: SourceLocation) async throws {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let track = try #require(videoTracks.first, sourceLocation: sourceLocation)
        let descriptions = try await track.load(.formatDescriptions)
        let subType = descriptions.map { CMFormatDescriptionGetMediaSubType($0) }.first
        #expect(subType == kCMVideoCodecType_HEVC, "expected HEVC output (passthrough fallback would copy the h264 source)", sourceLocation: sourceLocation)
    }

    @Test func noAudioClipsHevcExportConcatenatesAllClips() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("no_audio_hevc_merge")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...2)
            VideoClip(url: videoURL).trimmed(to: 5...7)
        }
        .preset(.reelsAndShorts) // HEVC
        .export(to: outputURL)
        defer { try? FileManager.default.removeItem(at: result) }

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        // Two 2s clips ⇒ ~4s. The passthrough bug yields ~2s (first clip only).
        #expect(CMTimeGetSeconds(duration) > 3.5)
        try await expectHEVC(asset, #_sourceLocation)
    }

    @Test func noAudioClipsHevcExportPreservesSpeed() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("no_audio_hevc_speed")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...4).speed(.flat(2.0))
        }
        .preset(.reelsAndShorts)
        .export(to: outputURL)
        defer { try? FileManager.default.removeItem(at: result) }

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        // 4s at 2x ⇒ ~2s. The passthrough bug yields ~4s (speed lost).
        #expect(CMTimeGetSeconds(duration) > 1.5)
        #expect(CMTimeGetSeconds(duration) < 3.0)
        try await expectHEVC(asset, #_sourceLocation)
    }

    @Test func noAudioClipsHevcExportPreservesTransition() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("no_audio_hevc_transition")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
            Transition.dissolve(duration: 1.0)
            VideoClip(url: videoURL).trimmed(to: 5...8)
        }
        .preset(.reelsAndShorts)
        .export(to: outputURL)
        defer { try? FileManager.default.removeItem(at: result) }

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        // 3s + 3s - 1s dissolve overlap ⇒ ~5s. The passthrough bug yields ~3s
        // (first clip only) because the transition path's videoComposition is dropped.
        #expect(CMTimeGetSeconds(duration) > 4.5)
        try await expectHEVC(asset, #_sourceLocation)
        // Passthrough would also copy both alternating transition video tracks
        // into the file; a real re-encode composites them into one.
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        #expect(videoTracks.count == 1, "expected a single composited video track, got \(videoTracks.count)")
    }

    @Test func mutedClipsHevcExportConcatenatesAllClips() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("no_audio_hevc_muted")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...2).muted()
            VideoClip(url: videoURL).trimmed(to: 5...7).muted()
        }
        .preset(.reelsAndShorts)
        .export(to: outputURL)
        defer { try? FileManager.default.removeItem(at: result) }

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        // Muted clips insert no audio either — same empty-audio-track shape.
        #expect(CMTimeGetSeconds(duration) > 3.5)
        try await expectHEVC(asset, #_sourceLocation)
    }
}
