import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia
import CoreImage
import CoreGraphics

/// Tier 4b tests — engine wiring of the custom `AVVideoCompositing` implementation.
///
/// Full end-to-end blending is exercised manually (real assets + visual verification);
/// these tests cover the wiring contract: when a user sets a `MultiInputCompositor` on
/// a multi-track `Video`, the resulting `AVMutableVideoComposition` has the custom
/// compositor class attached and its instruction is upgraded to a
/// `KadrVideoCompositionInstruction` carrying the compositor reference.
struct KadrVideoCompositorTests {

    private let preset: Preset = .auto

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

    private struct PassThrough: MultiInputCompositor {
        func process(images: [CIImage], context: CompositorContext) -> CIImage {
            images.first ?? CIImage(color: .clear)
        }
    }

    // MARK: - Wiring

    @Test func multiTrackWithoutCompositorSkipsCustomClass() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 2.0),
                ImageClip(img, duration: 1.0).at(time: 1.0),
            ],
            audioTracks: [],
            preset: preset,
            multiInputCompositor: nil
        )
        // Default path — no custom compositor class.
        #expect(result.videoComposition?.customVideoCompositorClass == nil)
        // Standard AVMutableVideoCompositionInstruction (not our subclass).
        let inst = result.videoComposition?.instructions.first
        #expect((inst as? KadrVideoCompositionInstruction) == nil)
    }

    @Test func multiTrackWithCompositorAttachesCustomClass() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 2.0),
                ImageClip(img, duration: 1.0).at(time: 1.0),
            ],
            audioTracks: [],
            preset: preset,
            multiInputCompositor: PassThrough()
        )
        // Custom compositor class wired.
        #expect(result.videoComposition?.customVideoCompositorClass == KadrVideoCompositor.self)
        // Instruction upgraded to our subclass.
        let inst = try #require(result.videoComposition?.instructions.first as? KadrVideoCompositionInstruction)
        // Compositor threaded through.
        #expect(inst.multiInputCompositor is PassThrough)
    }

    @Test func instructionExposesAllTrackIDsAsRequiredSources() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 1.0),
                ImageClip(img, duration: 1.0).at(time: 0),
                ImageClip(img, duration: 1.0).at(time: 0),
            ],
            audioTracks: [],
            preset: preset,
            multiInputCompositor: PassThrough()
        )
        let inst = try #require(result.videoComposition?.instructions.first as? KadrVideoCompositionInstruction)
        // 3 video tracks → 3 required source track IDs.
        #expect(inst.requiredSourceTrackIDs.count == 3)
    }

    @Test func instructionPassthroughIsInvalid() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 1.0),
                ImageClip(img, duration: 1.0).at(time: 0),
            ],
            audioTracks: [],
            preset: preset,
            multiInputCompositor: PassThrough()
        )
        let inst = try #require(result.videoComposition?.instructions.first as? KadrVideoCompositionInstruction)
        // We're compositing, not passing one track through unchanged.
        #expect(inst.passthroughTrackID == kCMPersistentTrackID_Invalid)
    }

    @Test func videoExportThreadsCompositorThroughBuild() async throws {
        // Sanity: Video.exporter(to:) creates an Exporter with multiInputCompositor set
        // when Video.compositor(_:) was called. We can't drive a full export here without
        // sample assets, but verifying the Exporter retains the reference confirms the
        // plumbing from Video → Exporter is intact.
        let img = try loadTestImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
            ImageClip(img, duration: 1.0).at(time: 0)
        }
        .compositor(PassThrough())

        let url = URL(fileURLWithPath: "/tmp/v06b_export_test.mp4")
        let exporter = video.exporter(to: url)
        #expect(exporter.multiInputCompositor is PassThrough)
    }
}
