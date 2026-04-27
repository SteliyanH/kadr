import Testing
import Foundation
import Kadr
import CoreMedia
import CoreImage

/// Tests for the v0.5.0 ``Compositor`` protocol and the ``VideoClip/compositor(_:)``
/// modifiers. Uses a non-`@testable` import to lock in the public-API contract — a
/// regression that demotes any of the new public surface fails the build.
struct CompositorTests {

    /// A trivial Compositor used for assertions about the `[any Compositor]` storage
    /// flowing through the modifier chain. Tag carries through so tests can verify the
    /// right instances landed in the right order.
    private struct TaggedCompositor: Compositor {
        let tag: String
        func process(image: CIImage, context: CompositorContext) -> CIImage { image }
    }

    // MARK: - Public surface

    @Test func defaultCompositorsIsEmpty() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
        #expect(clip.compositors.isEmpty)
    }

    @Test func compositorProtocolFormAppends() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url).compositor(TaggedCompositor(tag: "a"))
        #expect(clip.compositors.count == 1)
        #expect((clip.compositors[0] as? TaggedCompositor)?.tag == "a")
    }

    @Test func compositorClosureFormWraps() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url).compositor { image, _ in image }
        #expect(clip.compositors.count == 1)
        // Closure form wraps in an internal ClosureCompositor — we can't inspect that
        // type from outside the module, but its presence in the array is observable.
    }

    @Test func multipleCompositorsAccumulateInOrder() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .compositor(TaggedCompositor(tag: "a"))
            .compositor(TaggedCompositor(tag: "b"))
            .compositor(TaggedCompositor(tag: "c"))
        let tags = clip.compositors.compactMap { ($0 as? TaggedCompositor)?.tag }
        #expect(tags == ["a", "b", "c"])
    }

    @Test func compositorsSurviveModifierChain() {
        // Setting compositors at any point in the chain preserves them through every
        // subsequent modifier — the same regression-prone pattern as filters / clipID.
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .compositor(TaggedCompositor(tag: "a"))
            .trimmed(to: 0.0...5.0)
            .reversed()
            .muted()
            .speed(2.0)
            .filter(.brightness(0.1))
            .id("hero")
        let tags = clip.compositors.compactMap { ($0 as? TaggedCompositor)?.tag }
        #expect(tags == ["a"])
        #expect(clip.clipID == ClipID("hero"))
    }

    @Test func compositorClosureContextPassesTimeAndRenderSize() {
        // Sanity: invoke a closure compositor manually with a known context and verify
        // both fields are accessible. Inline assertions inside the closure since the
        // @Sendable closure can't capture mutable vars.
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let expectedTime = CMTime(seconds: 1.5, preferredTimescale: 600)
        let expectedSize = CGSize(width: 1080, height: 1920)
        let clip = VideoClip(url: url).compositor { image, ctx in
            #expect(ctx.time == expectedTime)
            #expect(ctx.renderSize == expectedSize)
            return image
        }

        let dummy = CIImage(color: .red)
        let comp = clip.compositors[0]
        _ = comp.process(image: dummy, context: CompositorContext(time: expectedTime, renderSize: expectedSize))
    }

    @Test func compositorContextIsConstructible() {
        // The context's public init is the API consumers use when writing their own
        // unit tests for Compositor conformers.
        let ctx = CompositorContext(
            time: .zero,
            renderSize: CGSize(width: 100, height: 200)
        )
        #expect(ctx.time == .zero)
        #expect(ctx.renderSize == CGSize(width: 100, height: 200))
    }
}
