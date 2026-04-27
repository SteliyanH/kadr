import Testing
import Foundation
import Kadr
import CoreImage
import CoreMedia

/// Tests for the v0.5.0 ``VideoClip/crop(at:size:anchor:)`` modifier — Tier 3 of the
/// v0.5 cycle, built as a thin wrapper over the public ``Compositor`` protocol.
///
/// Uses a non-`@testable` import to lock in the public-API contract.
struct ClipCropTests {

    // MARK: - Public surface

    @Test func cropAppendsACompositor() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url).crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
        #expect(clip.compositors.count == 1)
    }

    @Test func cropPreservesPriorCompositors() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .compositor { image, _ in image }   // a closure compositor
            .crop(at: .center, size: .normalized(width: 0.8, height: 0.8))
        #expect(clip.compositors.count == 2)
    }

    @Test func multipleCropsAccumulate() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
            .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
        #expect(clip.compositors.count == 2)
    }

    @Test func cropSurvivesModifierChain() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
            .trimmed(to: 0.0...5.0)
            .reversed()
            .speed(2.0)
            .filter(.brightness(0.1))
            .id("hero")
        // Crop compositor sits in the compositors array; subsequent modifiers preserve it.
        #expect(clip.compositors.count == 1)
        #expect(clip.clipID == ClipID("hero"))
    }

    @Test func defaultAnchorIsCenter() {
        // Sanity: the modifier compiles and runs with the anchor parameter omitted.
        // (Anchor inspection isn't possible from outside the module since CropCompositor
        // is internal — engine-side coverage handles the geometry.)
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url).crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
        #expect(clip.compositors.count == 1)
    }

    // MARK: - Geometry sanity (via custom Compositor that mirrors the contract)

    /// A user-written Compositor exercising the same `process(image:context:)` shape the
    /// internal `CropCompositor` uses. This test confirms the shape works end-to-end —
    /// the actual `CropCompositor`'s pixel math is covered by engine integration tests.
    @Test func customCompositorSeesNonZeroExtent() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url).compositor { image, ctx in
            #expect(image.extent.width > 0)
            #expect(ctx.renderSize.width > 0)
            return image
        }
        let dummy = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let ctx = CompositorContext(time: .zero, renderSize: CGSize(width: 1080, height: 1920))
        _ = clip.compositors[0].process(image: dummy, context: ctx)
    }
}
