import Testing
import Foundation
import Kadr
import CoreGraphics

/// Public-API tests for the v0.4.0 ``Layout`` namespace. Uses a non-`@testable` import so a
/// regression that demotes ``Layout/resolveFrame(position:size:anchor:in:)`` to internal
/// fails the build.
///
/// Numerical correctness of the underlying ``Position`` / ``Size`` / ``Anchor`` math is
/// covered by `LayoutTests` against the internal `FrameResolver`; these tests focus on the
/// public-surface contract and on confirming the public helper produces the same values as
/// the engine's internal resolver for a representative spread of cases.
struct LayoutHelpersTests {

    private let renderSize = CGSize(width: 1080, height: 1920)

    @Test func centerNormalizedDefaultAnchor() {
        let frame = Layout.resolveFrame(
            position: .center,
            size: .normalized(width: 0.5, height: 0.25),
            in: renderSize
        )
        // .center anchor on the size means the rectangle is centered on the position.
        #expect(frame.size.width == 540)
        #expect(frame.size.height == 480)
        #expect(frame.midX == 540)
        #expect(frame.midY == 960)
    }

    @Test func topLeftAnchorAtTopLeftPosition() {
        let frame = Layout.resolveFrame(
            position: .topLeft,
            size: .normalized(width: 0.5, height: 0.5),
            anchor: .topLeft,
            in: renderSize
        )
        #expect(frame.origin.x == 0)
        #expect(frame.origin.y == 0)
        #expect(frame.size.width == 540)
        #expect(frame.size.height == 960)
    }

    @Test func bottomRightAnchorAtBottomRightPosition() {
        let frame = Layout.resolveFrame(
            position: .bottomRight,
            size: .normalized(width: 0.25, height: 0.25),
            anchor: .bottomRight,
            in: renderSize
        )
        // The rectangle's bottom-right corner sits at (renderSize.width, renderSize.height).
        #expect(frame.maxX == renderSize.width)
        #expect(frame.maxY == renderSize.height)
    }

    @Test func pixelsResolveToExactPixelOrigin() {
        let frame = Layout.resolveFrame(
            position: .pixels(x: 100, y: 200),
            size: .pixels(width: 300, height: 400),
            anchor: .topLeft,
            in: renderSize
        )
        #expect(frame.origin.x == 100)
        #expect(frame.origin.y == 200)
        #expect(frame.size.width == 300)
        #expect(frame.size.height == 400)
    }

    @Test func percentMatchesNormalized() {
        let percent = Layout.resolveFrame(
            position: .percent(x: 50, y: 50),
            size: .percent(width: 50, height: 50),
            in: renderSize
        )
        let normalized = Layout.resolveFrame(
            position: .normalized(x: 0.5, y: 0.5),
            size: .normalized(width: 0.5, height: 0.5),
            in: renderSize
        )
        #expect(percent == normalized)
    }

    @Test func aspectFitConstrainsToFit() {
        // 1:1 source inside a 1080x1920 canvas with .aspectFit should fit by the smaller
        // dimension (width here).
        let frame = Layout.resolveFrame(
            position: .center,
            size: .aspectFit(within: .normalized(width: 1, height: 1), sourceAspect: 1),
            in: renderSize
        )
        #expect(frame.size.width == 1080)
        #expect(frame.size.height == 1080)
    }

    @Test func differentRenderSizesProduceConsistentRelativeFrames() {
        // Same .normalized layout should occupy the same fraction of any canvas.
        let small = CGSize(width: 540, height: 960)
        let large = CGSize(width: 1080, height: 1920)
        let smallFrame = Layout.resolveFrame(
            position: .center,
            size: .normalized(width: 0.5, height: 0.5),
            in: small
        )
        let largeFrame = Layout.resolveFrame(
            position: .center,
            size: .normalized(width: 0.5, height: 0.5),
            in: large
        )
        #expect(smallFrame.size.width / small.width == largeFrame.size.width / large.width)
        #expect(smallFrame.size.height / small.height == largeFrame.size.height / large.height)
    }
}
