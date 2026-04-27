import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia
import CoreGraphics

/// Engine-side tests for the v0.6 Tier 4a multi-track path. Verifies the dispatch in
/// `CompositionBuilder.build(...)` correctly identifies multi-track compositions and
/// produces an `AVMutableComposition` with the expected number of parallel video
/// tracks plus a `videoComposition` with the matching layer-instruction count.
///
/// Tier 4a covers default alpha-composite blending only — the v0.6 `MultiInputCompositor`
/// hook lands with 4b. These tests don't exercise blending semantics, just the
/// composition shape: track count + layer-instruction count.
struct MultiTrackEngineTests {

    private let preset: Preset = .auto

    private func loadTestImage() throws -> PlatformImage {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "png") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.png"))
        }
        #if canImport(UIKit)
        guard let image = PlatformImage(contentsOfFile: url.path) else {
            throw KadrError.invalidURL(url)
        }
        return image
        #elseif canImport(AppKit)
        guard let image = PlatformImage(contentsOf: url) else {
            throw KadrError.invalidURL(url)
        }
        return image
        #endif
    }

    // MARK: - Dispatch

    @Test func singleTrackCompositionUsesNonMultiTrackPath() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [ImageClip(img, duration: 1.0)],
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition == nil)
    }

    @Test func compositionWithFreeFloatingClipRoutesToMultiTrack() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 2.0),
                ImageClip(img, duration: 1.0).at(time: 1.0),
            ],
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition != nil)
        let videoTracks = result.composition.tracks(withMediaType: .video)
        #expect(videoTracks.count == 2)
        #expect(result.videoComposition?.instructions.count == 1)
        let inst = result.videoComposition?.instructions.first as? AVMutableVideoCompositionInstruction
        #expect(inst?.layerInstructions.count == 2)
    }

    @Test func compositionWithTrackBlockRoutesToMultiTrack() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 2.0),
                Track(at: 0.5) {
                    ImageClip(img, duration: 1.0)
                    ImageClip(img, duration: 1.0)
                },
            ],
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition != nil)
        let videoTracks = result.composition.tracks(withMediaType: .video)
        #expect(videoTracks.count == 2)
    }

    @Test func compositionWithFreeFloatingOnlyAndNoChain() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 1.0).at(time: 0),
                ImageClip(img, duration: 1.0).at(time: 2.0),
            ],
            audioTracks: [],
            preset: preset
        )
        let videoTracks = result.composition.tracks(withMediaType: .video)
        #expect(videoTracks.count == 2)
    }

    // MARK: - Restrictions surfaced as KadrError.notYetImplemented

    @Test func transitionInChainRejectedInMultiTrack() async throws {
        let img = try loadTestImage()
        await #expect(throws: KadrError.self) {
            _ = try await CompositionBuilder.build(
                from: [
                    ImageClip(img, duration: 1.0),
                    Kadr.Transition.dissolve(duration: 0.3),
                    ImageClip(img, duration: 1.0),
                    ImageClip(img, duration: 1.0).at(time: 5.0),
                ],
                audioTracks: [],
                preset: self.preset
            )
        }
    }

    @Test func transitionInsideTrackBlockRejected() async throws {
        let img = try loadTestImage()
        await #expect(throws: KadrError.self) {
            _ = try await CompositionBuilder.build(
                from: [
                    ImageClip(img, duration: 1.0),
                    Track(at: 0) {
                        ImageClip(img, duration: 1.0)
                        Kadr.Transition.dissolve(duration: 0.3)
                        ImageClip(img, duration: 1.0)
                    },
                ],
                audioTracks: [],
                preset: self.preset
            )
        }
    }

    @Test func nestedTrackRejected() async throws {
        let img = try loadTestImage()
        await #expect(throws: KadrError.self) {
            _ = try await CompositionBuilder.build(
                from: [
                    ImageClip(img, duration: 1.0),
                    Track(at: 0) {
                        Track(at: 0) {
                            ImageClip(img, duration: 1.0)
                        }
                    },
                ],
                audioTracks: [],
                preset: self.preset
            )
        }
    }

    // MARK: - Total duration

    @Test func totalDurationCoversFreeFloatingTail() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 2.0),                   // chain ends at t=2
                ImageClip(img, duration: 3.0).at(time: 3.0),     // free-floating ends at t=6
            ],
            audioTracks: [],
            preset: preset
        )
        let inst = result.videoComposition?.instructions.first as? AVMutableVideoCompositionInstruction
        #expect(inst != nil)
        let totalSec = CMTimeGetSeconds(inst!.timeRange.duration)
        #expect(totalSec >= 5.99 && totalSec <= 6.01)
    }
}
