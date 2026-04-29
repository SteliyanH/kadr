import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// Tests for v0.8.2 — `VideoClip.filter(_:animation:)` intensity animation +
/// inner-Track clip Transform / animation wiring.
struct FilterIntensityAnimationTests {

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

    // MARK: - Filter.withScalar

    @Test func withScalarRebuildsBrightness() {
        let f = Filter.brightness(0.0)
        let rebuilt = f.withScalar(0.5)
        if case .brightness(let v) = rebuilt {
            #expect(v == 0.5)
        } else {
            Issue.record("expected .brightness")
        }
    }

    @Test func withScalarRebuildsSepiaIntensity() {
        let f = Filter.sepia(intensity: 0.0)
        let rebuilt = f.withScalar(0.7)
        if case .sepia(let v) = rebuilt {
            #expect(v == 0.7)
        } else {
            Issue.record("expected .sepia")
        }
    }

    @Test func withScalarReturnsSelfForNoScalarFilters() {
        // .mono / .lut / .chromaKey have no primary scalar; withScalar is a no-op.
        let mono = Filter.mono
        #expect(mono.withScalar(0.5) == .mono)
    }

    // MARK: - Modifier composition

    @Test func filterAnimationsDefaultsToEmpty() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
        #expect(clip.filterAnimations.isEmpty)
    }

    @Test func staticFiltersGetNilAnimationSlots() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.brightness(0.1), .contrast(1.2))
        #expect(clip.filters.count == 2)
        #expect(clip.filterAnimations.count == 2)
        #expect(clip.filterAnimations[0] == nil)
        #expect(clip.filterAnimations[1] == nil)
    }

    @Test func filterWithAnimationStoresPair() {
        let anim = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(1.0, value: 1.0),
        ])
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.sepia(intensity: 0), animation: anim)
        #expect(clip.filters.count == 1)
        #expect(clip.filterAnimations.count == 1)
        #expect(clip.filterAnimations[0] != nil)
    }

    @Test func mixOfStaticAndAnimatedFiltersStaysAligned() {
        let anim = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(1.0, value: 1.0),
        ])
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.brightness(0.0))
            .filter(.sepia(intensity: 0), animation: anim)
            .filter(.contrast(1.1))
        #expect(clip.filters.count == 3)
        #expect(clip.filterAnimations.count == 3)
        #expect(clip.filterAnimations[0] == nil)
        #expect(clip.filterAnimations[1] != nil)
        #expect(clip.filterAnimations[2] == nil)
    }

    @Test func filterAnimationPreservedThroughModifierChain() {
        let anim = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(2.0, value: 1.0),
        ])
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.brightness(0.0), animation: anim)
            .trimmed(to: 0...3)
            .muted()
            .id(ClipID("hero"))
        #expect(clip.filterAnimations.count == 1)
        #expect(clip.filterAnimations[0] != nil)
        #expect(clip.clipID == ClipID("hero"))
    }

    // MARK: - Engine integration

    @Test func videoExportWithFilterAnimationCompletes() async throws {
        // End-to-end: clip with filter animation goes through FilterProcessor pre-render
        // and the parent composition. We just want to confirm the engine doesn't trip
        // up — pixel-level animation correctness would need frame extraction, out of
        // scope for unit tests.
        let videoURL = try loadTestVideoURL()
        let result = try await CompositionBuilder.build(
            from: [
                VideoClip(url: videoURL).trimmed(to: 0...2)
                    .filter(.sepia(intensity: 0), animation: .keyframes([
                        .at(0.0, value: 0.0),
                        .at(2.0, value: 1.0),
                    ])),
            ],
            audioTracks: [],
            preset: preset
        )
        #expect(result.composition.duration > .zero)
    }

    // MARK: - Inner-Track clip Transform (lifted deferral)

    @Test func innerTrackClipTransformIsAppliedInPureMediaFastPath() async throws {
        // Pure-media Track (no transitions, no nested Tracks) takes the fast path.
        // v0.8.2 wires inner-clip transforms into the parallel track's layer instructions.
        // We confirm the engine builds a videoComposition with layer instructions.
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 5.0),
                Track(at: 1.0) {
                    ImageClip(img, duration: 2.0).transform(Transform(scale: 0.5))
                },
            ],
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition != nil)
        // 2 video tracks: chain + parallel.
        #expect(result.composition.tracks(withMediaType: .video).count == 2)
    }

    @Test func innerTrackClipAnimationIsAppliedInPureMediaFastPath() async throws {
        let img = try loadTestImage()
        let result = try await CompositionBuilder.build(
            from: [
                ImageClip(img, duration: 5.0),
                Track(at: 1.0) {
                    ImageClip(img, duration: 2.0)
                        .transform(.identity, animation: .keyframes([
                            .at(0.0, value: Transform(scale: 1.0)),
                            .at(2.0, value: Transform(scale: 1.5)),
                        ]))
                },
            ],
            audioTracks: [],
            preset: preset
        )
        #expect(result.videoComposition != nil)
    }
}
