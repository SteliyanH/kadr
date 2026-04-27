import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// Tier 4c tests — recursive composition for `Track {}` blocks containing transitions
/// and / or nested Tracks. The engine pre-renders such Tracks to a temp `.mp4` (mirroring
/// `FilterProcessor`'s pre-render pattern), then inserts the temp file as a single piece
/// on the parent's parallel video track.
///
/// Pre-render is a real `AVAssetExportSession` round-trip — these tests therefore exercise
/// the full export pipeline for the inner Track. Treat them as integration tests; they
/// take longer than the structural ones in `MultiTrackEngineTests`.
struct MultiTrackRecursiveTests {

    private let preset: Preset = .auto

    private func loadTestVideoURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "mov") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.mov"))
        }
        return url
    }

    private func loadTestImage() throws -> PlatformImage {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "png") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.png"))
        }
        #if canImport(UIKit)
        guard let image = PlatformImage(contentsOfFile: url.path) else { throw KadrError.invalidURL(url) }
        return image
        #elseif canImport(AppKit)
        guard let image = PlatformImage(contentsOf: url) else { throw KadrError.invalidURL(url) }
        return image
        #endif
    }

    @Test func trackWithTransitionPreRendersAndComposes() async throws {
        // Track with a transition inside — pre-renders to a temp .mp4 and the result
        // is inserted as a single piece on the parallel video track at the parent level.
        // Uses real video clips because the pre-render goes through AVAssetExportSession,
        // which rejects synthetic image-only compositions (-11838 "media not supported").
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 4.0),                            // chain (parent)
                Track(at: 0.5) {                                          // Track w/ transition
                    VideoClip(url: videoURL).trimmed(to: 0...1)
                    Kadr.Transition.dissolve(duration: 0.3)
                    VideoClip(url: videoURL).trimmed(to: 1...2)
                },
            ],
            audioTracks: [],
            preset: preset
        )
        // Parent: 2 video tracks (chain + Track-as-one-piece).
        let videoTracks = result.composition.tracks(withMediaType: .video)
        #expect(videoTracks.count == 2)
    }

    @Test func nestedTrackPreRendersAndComposes() async throws {
        // Nested Track — outer Track contains an inner Track. The outer triggers
        // pre-rendering because its clips contain another Track.
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 4.0),
                Track(at: 0) {
                    Track(at: 0) {
                        VideoClip(url: videoURL).trimmed(to: 0...1)
                    }
                    VideoClip(url: videoURL).trimmed(to: 1...2)
                },
            ],
            audioTracks: [],
            preset: preset
        )
        let videoTracks = result.composition.tracks(withMediaType: .video)
        #expect(videoTracks.count == 2)
    }

    @Test func pureMediaTrackUsesFastPath() async throws {
        // A Track with only media clips (no transitions, no nested Tracks) doesn't
        // trigger pre-render — it uses the existing Tier 4a sequential-insert path.
        // We can't observe the path directly, but composition shape is the same.
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
        let videoTracks = result.composition.tracks(withMediaType: .video)
        #expect(videoTracks.count == 2)
    }
}
