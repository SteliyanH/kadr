import Testing
import Foundation
import Kadr
import CoreImage
import CoreMedia
import CoreGraphics

/// Tests for the v0.6 ``MultiInputCompositor`` protocol and the ``Video/compositor(_:)``
/// modifiers — Tier 3 of the v0.6 multi-track timeline cycle.
///
/// Surface only — engine wiring lands in Tier 4. These tests cover the public-API
/// contract via a non-`@testable` import so a regression that demotes any of the new
/// public surface fails the build, plus the engine-side default blender via an
/// `@testable` test below.
struct MultiInputCompositorTests {

    /// A trivial conformer that records its input count for assertions.
    private struct PassThroughCompositor: MultiInputCompositor {
        let tag: String
        func process(images: [CIImage], context: CompositorContext) -> CIImage {
            images.first ?? CIImage(color: .clear)
        }
    }

    // MARK: - Public surface

    @Test func defaultMultiInputCompositorIsNil() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        #expect(video.multiInputCompositor == nil)
    }

    @Test func protocolFormSetsCompositor() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .compositor(PassThroughCompositor(tag: "test"))
        #expect(video.multiInputCompositor != nil)
        #expect((video.multiInputCompositor as? PassThroughCompositor)?.tag == "test")
    }

    @Test func closureFormWraps() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .compositor { images, _ in images.first ?? CIImage(color: .clear) }
        #expect(video.multiInputCompositor != nil)
    }

    @Test func compositorReplacesPriorCompositor() {
        // Calling .compositor again replaces the prior one (single-compositor model).
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .compositor(PassThroughCompositor(tag: "first"))
        .compositor(PassThroughCompositor(tag: "second"))
        #expect((video.multiInputCompositor as? PassThroughCompositor)?.tag == "second")
    }

    @Test func multiInputCompositorSurvivesOtherModifiers() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .compositor(PassThroughCompositor(tag: "keep"))
        .audio(url: URL(fileURLWithPath: "/tmp/x.m4a"))
        .preset(.cinema)
        .overlay(TextOverlay("hi"))
        .crop(at: .center, size: .normalized(width: 0.8, height: 0.8))

        #expect((video.multiInputCompositor as? PassThroughCompositor)?.tag == "keep")
    }

    @Test func compositorClosureContextPassesTimeAndRenderSize() {
        let img = PlatformImage()
        let expectedTime = CMTime(seconds: 1.5, preferredTimescale: 600)
        let expectedSize = CGSize(width: 1080, height: 1920)
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .compositor { images, ctx in
            #expect(ctx.time == expectedTime)
            #expect(ctx.renderSize == expectedSize)
            return images.first ?? CIImage(color: .clear)
        }

        // Manually invoke the closure with a known context — closure can't capture
        // mutable vars under @Sendable, so #expect inline.
        let comp = video.multiInputCompositor!
        let dummy = CIImage(color: .red)
        _ = comp.process(
            images: [dummy],
            context: CompositorContext(time: expectedTime, renderSize: expectedSize)
        )
    }
}

// MARK: - Default blender (engine-side, @testable)

import Foundation
@testable import Kadr

struct AlphaCompositeBlenderTests {

    private let context = CompositorContext(
        time: .zero,
        renderSize: CGSize(width: 100, height: 100)
    )

    @Test func emptyInputsReturnsTransparentAtRenderSize() {
        let blender = AlphaCompositeBlender()
        let result = blender.process(images: [], context: context)
        // Blender returns a clear image cropped to the render size when there are no
        // inputs. Sanity: result extent matches the render size.
        #expect(result.extent.size == context.renderSize)
    }

    @Test func singleInputPassesThrough() {
        let blender = AlphaCompositeBlender()
        let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        let result = blender.process(images: [red], context: context)
        // Single-input fast path returns the input unchanged.
        #expect(result === red || result == red)   // CIImage equality is structural
    }

    @Test func multipleInputsCompositeWithoutCrash() {
        // Source-over compositing of three solid-color images. The exact pixel result
        // is not what we're testing — just that the compositor walks all inputs and
        // returns a valid CIImage.
        let blender = AlphaCompositeBlender()
        let bounds = CGRect(x: 0, y: 0, width: 50, height: 50)
        let layers = [
            CIImage(color: .red).cropped(to: bounds),
            CIImage(color: .green).cropped(to: bounds),
            CIImage(color: .blue).cropped(to: bounds),
        ]
        let result = blender.process(images: layers, context: context)
        #expect(result.extent.size.width > 0)
    }
}
