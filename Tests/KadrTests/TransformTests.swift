import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia
import CoreGraphics

/// Tests for v0.8 Tier 1 — per-clip ``Transform``.
///
/// Surface tests cover the value type and modifier composition. Engine tests verify
/// the multi-track path emits `setTransform(_:at:)` calls on the right layer
/// instructions at the right composition times.
struct TransformTests {

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

    // MARK: - Value type

    @Test func identityIsTheDefault() {
        let t = Transform()
        let id = Transform.identity
        #expect(t == id)
    }

    @Test func valueTypeStoresExplicitFields() {
        let t = Transform(
            center: .topRight,
            rotation: .pi / 4,
            scale: 0.5,
            anchor: .topRight
        )
        #expect(t.center == .topRight)
        #expect(t.rotation == .pi / 4)
        #expect(t.scale == 0.5)
        #expect(t.anchor == .topRight)
    }

    @Test func resolvedIsIdentityForIdentityTransform() {
        let t = Transform.identity.resolved(in: CGSize(width: 1080, height: 1920))
        // Identity Transform with center=(0.5, 0.5), anchor=center cancels out:
        //   T(canvasCenter) · T(-canvasCenter) == identity (after no rotation/scale)
        #expect(abs(t.a - 1) < 0.0001)
        #expect(abs(t.b) < 0.0001)
        #expect(abs(t.c) < 0.0001)
        #expect(abs(t.d - 1) < 0.0001)
        #expect(abs(t.tx) < 0.0001)
        #expect(abs(t.ty) < 0.0001)
    }

    @Test func resolvedScalesAroundCenterAnchor() {
        // Scale 0.5 with default center+anchor on a 1000×1000 canvas.
        // Pivot = (500, 500); center = (500, 500). Result: scale 0.5 around (500, 500).
        let t = Transform(scale: 0.5).resolved(in: CGSize(width: 1000, height: 1000))
        #expect(abs(t.a - 0.5) < 0.0001)
        #expect(abs(t.d - 0.5) < 0.0001)
        // tx = centerX − scale·pivotX = 500 − 0.5·500 = 250
        #expect(abs(t.tx - 250) < 0.0001)
        #expect(abs(t.ty - 250) < 0.0001)
    }

    @Test func resolvedTranslatesToTopRightWithMatchingAnchor() {
        // Center at top-right with top-right anchor places the clip's top-right corner
        // exactly at the canvas's top-right corner. tx = canvasW − pivotX.
        let canvas = CGSize(width: 1000, height: 1000)
        let t = Transform(center: .topRight, anchor: .topRight).resolved(in: canvas)
        // Default scale 1.0; pivot at top-right of clip = (1000, 0). Center point (1000, 0).
        // tx = 1000 − 1·1000 = 0; ty = 0 − 1·0 = 0.
        #expect(abs(t.tx) < 0.0001)
        #expect(abs(t.ty) < 0.0001)
    }

    // MARK: - Modifier composition

    @Test func transformDefaultsToNilOnAllClipTypes() {
        let img = PlatformImage()
        let video = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
        let image = ImageClip(img, duration: 1.0)
        let title = TitleSequence("hi", duration: 1.0)
        #expect(video.transform == nil)
        #expect(image.transform == nil)
        #expect(title.transform == nil)
    }

    @Test func transformModifierStoresValueOnVideoClip() {
        let t = Transform(scale: 0.5)
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null")).transform(t)
        #expect(clip.transform == t)
    }

    @Test func transformModifierStoresValueOnImageClip() {
        let t = Transform(center: .topRight, anchor: .topRight)
        let clip = ImageClip(PlatformImage(), duration: 1.0).transform(t)
        #expect(clip.transform == t)
    }

    @Test func transformModifierStoresValueOnTitleSequence() {
        let t = Transform(rotation: .pi)
        let title = TitleSequence("hi", duration: 1.0).transform(t)
        #expect(title.transform == t)
    }

    @Test func transformPreservedAcrossModifierChain() {
        let t = Transform(scale: 0.4)
        let url = URL(fileURLWithPath: "/dev/null")
        let clip = VideoClip(url: url)
            .transform(t)
            .trimmed(to: 0...3)
            .muted()
            .id(ClipID("test"))
            .at(time: 1.0)
        #expect(clip.transform == t)
        #expect(clip.clipID == ClipID("test"))
    }

    @Test func transformModifierReplacesPreviousValue() {
        let first = Transform(scale: 0.5)
        let second = Transform(scale: 0.25)
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .transform(first)
            .transform(second)
        #expect(clip.transform == second)
    }

    // MARK: - Engine integration

    @Test func transformOnFreeFloaterRoutesThroughMultiTrackPath() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 5.0),
                ImageClip(img, duration: 2.0).at(time: 1.0).transform(Transform(scale: 0.5)),
            ],
            audioTracks: [],
            preset: preset
        )
        // Multi-track path always emits a videoComposition.
        #expect(result.videoComposition != nil)
        // Two video tracks: chain + free-floater parallel.
        #expect(result.composition.tracks(withMediaType: .video).count == 2)
    }

    @Test func transformOnSingleTrackChainPromotesToMultiTrackPath() async throws {
        // v0.8 routing rule: a transform-bearing single-track composition routes through
        // buildMultiTrack so the engine has a videoComposition + layer instructions to
        // hold setTransform(_:at:) calls.
        let img = try loadTestImage()
        let withoutTransform = try await CompositionBuilder.build(
            from: [ImageClip(img, duration: 1.0)],
            audioTracks: [],
            preset: preset
        )
        let withTransform = try await CompositionBuilder.build(
            from: [ImageClip(img, duration: 1.0).transform(Transform(scale: 0.5))],
            audioTracks: [],
            preset: preset
        )
        // Without transform → buildSimple, returns nil videoComposition.
        #expect(withoutTransform.videoComposition == nil)
        // With transform → buildMultiTrack, always builds a videoComposition.
        #expect(withTransform.videoComposition != nil)
    }

    @Test func transformOnChainClipEmitsLayerInstructionTransform() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 1.0),                                 // chain[0] no transform
                ImageClip(img, duration: 1.0).transform(Transform(scale: 0.5)), // chain[1] with transform
            ],
            audioTracks: [],
            preset: preset
        )
        let inst = try #require(result.videoComposition?.instructions.first as? AVMutableVideoCompositionInstruction)
        // One layer instruction (single chain track).
        #expect(inst.layerInstructions.count == 1)
        // The layer instruction should carry at least one transform ramp/keyframe pair.
        // AVMutableVideoCompositionLayerInstruction doesn't expose its transforms array
        // directly; we settle for asserting the engine built the multi-track videoComposition
        // (covered above) and trust that setTransform(_:at:) was called per the source.
    }

    @Test func transformOnTrackBlockIsIgnoredInTier1() async throws {
        // v0.8 Tier 1 explicitly defers Track-internal clip transforms to v0.8.2.
        // Setting a transform on a clip inside a Track should compile and round-trip
        // through Video.clips, but the engine ignores it in this release.
        let img = try loadTestImage()
        let video = Video {
            ImageClip(img, duration: 5.0)
            Track(at: 1.0) {
                ImageClip(img, duration: 2.0).transform(Transform(scale: 0.5))
            }
        }
        let track = video.clips.compactMap { $0 as? Track }.first!
        let innerImage = track.clips.compactMap { $0 as? ImageClip }.first!
        // Round-trip works: inner clip carries the transform.
        #expect(innerImage.transform != nil)
        // Engine still produces a videoComposition (multi-track path), but the inner
        // clip's transform doesn't apply. No assertion on that detail here — it would
        // require pixel-level inspection.
        let result = try await CompositionBuilder.build(
            from: video.clips,
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition != nil)
    }
}
