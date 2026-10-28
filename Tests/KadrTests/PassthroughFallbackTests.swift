import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// When the export preset can't encode a composition, the engine used to fall back to
/// `AVAssetExportPresetPassthrough` unconditionally. Passthrough can't apply a video
/// composition, so the export "succeeded" with transitions, track layout, crop and
/// overlays silently missing (https://github.com/SteliyanH/kadr/issues/201). It now
/// throws instead whenever the copy would drop any of those.
struct PassthroughFallbackTests {

    // MARK: - Decision

    @Test func plainCompositionMayFallBack() {
        #expect(ExportEngine.passthroughLoss(hasVideoComposition: false) == nil)
    }

    @Test func eachDroppedFeatureBlocksTheFallback() throws {
        let composition = try #require(ExportEngine.passthroughLoss(hasVideoComposition: true))
        #expect(composition.contains("video composition"))
        let overlays = try #require(ExportEngine.passthroughLoss(hasVideoComposition: false, hasOverlays: true))
        #expect(overlays.contains("overlays"))
        let crop = try #require(ExportEngine.passthroughLoss(hasVideoComposition: false, hasCrop: true))
        #expect(crop.contains("crop"))
    }

    @Test func errorNamesThePresetAndWhatWouldBeLost() {
        let error = ExportEngine.incompatiblePresetError(
            presetName: AVAssetExportPresetHEVCHighestQuality,
            lost: "overlays"
        )
        guard case .exportFailed(let underlying) = error else {
            Issue.record("expected .exportFailed, got \(error)")
            return
        }
        let message = (underlying as NSError).localizedDescription
        #expect(message.contains(AVAssetExportPresetHEVCHighestQuality))
        #expect(message.contains("overlays"))
    }

    // MARK: - Export

    /// Recreates the composition shape from #201: a transition composition with an
    /// empty audio track, which the HEVC preset rejects. The export must throw rather
    /// than hand back a passthrough copy of the first clip.
    @Test func incompatibleCompositionWithVideoCompositionThrows() async throws {
        let videoURL = try #require(Bundle.module.url(forResource: "sample", withExtension: "mov"))
        let preset: Preset = .reelsAndShorts // HEVC
        let result = try await CompositionBuilder.build(
            from: [
                VideoClip(url: videoURL).trimmed(to: 0...3),
                Transition.dissolve(duration: 1.0),
                VideoClip(url: videoURL).trimmed(to: 5...8),
            ],
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition != nil)
        _ = result.composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let compatible = await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetHEVCHighestQuality,
            with: result.composition,
            outputFileType: .mp4
        )
        // The empty audio track is what makes AVFoundation reject the preset (verified
        // on macOS 26.5). If a later OS accepts it, this test can no longer force the
        // fallback and has nothing to check.
        guard !compatible else { return }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("passthrough_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        await #expect(throws: KadrError.self) {
            for try await _ in ExportEngine.export(
                composition: result.composition,
                audioMix: result.audioMix,
                videoComposition: result.videoComposition,
                preset: preset,
                to: outputURL
            ) {}
        }
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }
}
