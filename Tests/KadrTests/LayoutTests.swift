import Testing
import Foundation
@testable import Kadr
import CoreGraphics

/// Tests the v0.3.0 foundational coordinate types: Position, Size, Anchor, and the
/// FrameResolver that composes them into a final render-space CGRect.
struct LayoutTests {

    private let renderSize = CGSize(width: 1080, height: 1920)

    // MARK: - Position

    @Test func normalizedResolves() {
        let p = Position.normalized(x: 0.5, y: 0.25)
        let resolved = p.resolved(in: renderSize)
        #expect(resolved.x == 540)
        #expect(resolved.y == 480)
    }

    @Test func pixelsPassThrough() {
        let p = Position.pixels(x: 100, y: 200)
        let resolved = p.resolved(in: renderSize)
        #expect(resolved.x == 100)
        #expect(resolved.y == 200)
    }

    @Test func percentResolves() {
        let p = Position.percent(x: 50, y: 25)
        let resolved = p.resolved(in: renderSize)
        #expect(resolved.x == 540)
        #expect(resolved.y == 480)
    }

    @Test func percentMatchesNormalized() {
        // .percent(50, 50) should equal .normalized(0.5, 0.5) when resolved
        let percent = Position.percent(x: 50, y: 50).resolved(in: renderSize)
        let normalized = Position.normalized(x: 0.5, y: 0.5).resolved(in: renderSize)
        #expect(percent == normalized)
    }

    @Test func centerConvenienceAnchor() {
        let resolved = Position.center.resolved(in: renderSize)
        #expect(resolved.x == 540)
        #expect(resolved.y == 960)
    }

    @Test func topLeftConvenienceAnchor() {
        let resolved = Position.topLeft.resolved(in: renderSize)
        #expect(resolved.x == 0)
        #expect(resolved.y == 0)
    }

    @Test func bottomRightConvenienceAnchor() {
        let resolved = Position.bottomRight.resolved(in: renderSize)
        #expect(resolved.x == 1080)
        #expect(resolved.y == 1920)
    }

    @Test func resolutionIndependence() {
        // The same .normalized position resolves to different pixels at different render sizes
        let p = Position.normalized(x: 0.5, y: 0.5)
        let square = p.resolved(in: CGSize(width: 1080, height: 1080))
        let portrait = p.resolved(in: CGSize(width: 1080, height: 1920))
        #expect(square.y == 540)
        #expect(portrait.y == 960)
    }

    // MARK: - Size

    @Test func sizeNormalizedResolves() {
        let s = Size.normalized(width: 0.4, height: 0.1)
        let resolved = s.resolved(in: renderSize)
        #expect(resolved.width == 432)
        #expect(resolved.height == 192)
    }

    @Test func sizePixelsPassThrough() {
        let s = Size.pixels(width: 480, height: 100)
        let resolved = s.resolved(in: renderSize)
        #expect(resolved.width == 480)
        #expect(resolved.height == 100)
    }

    @Test func sizePercentResolves() {
        let s = Size.percent(width: 50, height: 25)
        let resolved = s.resolved(in: renderSize)
        #expect(resolved.width == 540)
        #expect(resolved.height == 480)
    }

    @Test func aspectFitWiderSource() {
        // Source aspect 16:9 (1.778) fits inside 0.5×0.5 bounds (1:1 in normalized × renderSize aspect)
        // bounds = 540×960 (square in normalized terms but rendered at 1080×1920 aspect)
        // Source wider than bounds → constrained by width
        let bounds = Size.normalized(width: 0.5, height: 0.5)
        let resolved = Size.aspectFit(within: bounds, sourceAspect: 16.0/9.0).resolved(in: renderSize)
        // bounds resolved: 540 × 960 (aspect 0.5625). source (1.778) wider → fit to bounds width
        #expect(resolved.width == 540)
        #expect(abs(resolved.height - 540 / (16.0/9.0)) < 0.01)
    }

    @Test func aspectFillTallerSource() {
        // Source aspect 9:16 (0.5625) fills bounds 0.5×0.5
        let bounds = Size.normalized(width: 0.5, height: 0.5)
        let resolved = Size.aspectFill(covering: bounds, sourceAspect: 9.0/16.0).resolved(in: renderSize)
        // bounds: 540 × 960 (aspect 0.5625). source (0.5625) equals bounds aspect → both ≤
        // Actually source.aspect == bounds.aspect, so the case branches to width-fit
        #expect(resolved.width == 540)
        #expect(abs(resolved.height - 960) < 0.01)
    }

    // MARK: - Anchor

    @Test func anchorOffsets() {
        #expect(Anchor.topLeft.normalizedOffset == CGPoint(x: 0, y: 0))
        #expect(Anchor.center.normalizedOffset == CGPoint(x: 0.5, y: 0.5))
        #expect(Anchor.bottomRight.normalizedOffset == CGPoint(x: 1, y: 1))
    }

    // MARK: - FrameResolver

    @Test func centeredOverlay() {
        // .center anchor + .center position → overlay centered on render canvas
        let frame = FrameResolver.resolve(
            position: .center,
            size: .normalized(width: 0.5, height: 0.5),
            anchor: .center,
            in: renderSize
        )
        // render is 1080×1920. size resolves to 540×960. centered → origin at (270, 480).
        #expect(frame.origin.x == 270)
        #expect(frame.origin.y == 480)
        #expect(frame.size.width == 540)
        #expect(frame.size.height == 960)
    }

    @Test func topLeftAnchorPlacesCornerAtPosition() {
        // .topLeft anchor + (10px, 10px) position → overlay's top-left at (10, 10)
        let frame = FrameResolver.resolve(
            position: .pixels(x: 10, y: 10),
            size: .pixels(width: 200, height: 100),
            anchor: .topLeft,
            in: renderSize
        )
        #expect(frame.origin.x == 10)
        #expect(frame.origin.y == 10)
        #expect(frame.size.width == 200)
        #expect(frame.size.height == 100)
    }

    @Test func bottomRightAnchorPlacesCornerAtPosition() {
        // .bottomRight anchor + .bottomRight position → overlay's bottom-right at render's bottom-right
        let frame = FrameResolver.resolve(
            position: .bottomRight,
            size: .pixels(width: 200, height: 100),
            anchor: .bottomRight,
            in: renderSize
        )
        #expect(frame.origin.x == 880)
        #expect(frame.origin.y == 1820)
    }

    @Test func defaultAnchorIsCenter() {
        // FrameResolver.resolve uses .center as the default anchor
        let withDefault = FrameResolver.resolve(
            position: .center,
            size: .pixels(width: 100, height: 100),
            in: renderSize
        )
        let explicit = FrameResolver.resolve(
            position: .center,
            size: .pixels(width: 100, height: 100),
            anchor: .center,
            in: renderSize
        )
        #expect(withDefault == explicit)
    }
}
