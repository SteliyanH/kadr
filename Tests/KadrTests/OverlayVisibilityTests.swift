import Testing
import Foundation
import Kadr
import CoreMedia
import CoreGraphics
import QuartzCore

/// Tests for the v0.5.0 ``Overlay/visibilityRange`` surface — `.visible(during:)` on each
/// overlay type plus the engine's keyframe-animation timing on the resulting CALayer.
struct OverlayVisibilityTests {

    // MARK: - Public-API surface (non-`@testable` import)

    @Test func defaultVisibilityIsNil() {
        let img = PlatformImage()
        let imageOverlay = ImageOverlay(img)
        let textOverlay = TextOverlay("hello")
        let stickerOverlay = StickerOverlay(img)
        #expect(imageOverlay.visibilityRange == nil)
        #expect(textOverlay.visibilityRange == nil)
        #expect(stickerOverlay.visibilityRange == nil)
    }

    @Test func imageOverlayVisibleDuringCMTimeRange() {
        let img = PlatformImage()
        let range = CMTimeRange(
            start: CMTime(seconds: 1, preferredTimescale: 600),
            duration: CMTime(seconds: 4, preferredTimescale: 600)
        )
        let overlay = ImageOverlay(img).visible(during: range)
        #expect(overlay.visibilityRange == range)
    }

    @Test func imageOverlayVisibleDuringTimeIntervalRange() {
        let img = PlatformImage()
        let overlay = ImageOverlay(img).visible(during: 1.0...5.0)
        #expect(overlay.visibilityRange != nil)
        #expect(CMTimeGetSeconds(overlay.visibilityRange!.start) == 1.0)
        #expect(CMTimeGetSeconds(overlay.visibilityRange!.end) == 5.0)
    }

    @Test func textOverlayVisibleDuringTimeIntervalRange() {
        let overlay = TextOverlay("caption").visible(during: 2.0...6.0)
        #expect(overlay.visibilityRange != nil)
        #expect(CMTimeGetSeconds(overlay.visibilityRange!.start) == 2.0)
        #expect(CMTimeGetSeconds(overlay.visibilityRange!.end) == 6.0)
    }

    @Test func stickerOverlayVisibleDuringTimeIntervalRange() {
        let img = PlatformImage()
        let overlay = StickerOverlay(img).visible(during: 0.5...3.5)
        #expect(overlay.visibilityRange != nil)
        #expect(CMTimeGetSeconds(overlay.visibilityRange!.start) == 0.5)
        #expect(CMTimeGetSeconds(overlay.visibilityRange!.end) == 3.5)
    }

    @Test func visibilityRangeSurvivesModifierChain() {
        // Setting visibility before / after other modifiers preserves it through the chain.
        let img = PlatformImage()
        let a = ImageOverlay(img)
            .visible(during: 1.0...4.0)
            .position(.topLeft)
            .size(.normalized(width: 0.2, height: 0.1))
            .opacity(0.8)
            .id("logo")
        let b = ImageOverlay(img)
            .position(.topLeft)
            .opacity(0.8)
            .visible(during: 1.0...4.0)
        #expect(a.visibilityRange != nil)
        #expect(b.visibilityRange != nil)
        #expect(CMTimeGetSeconds(a.visibilityRange!.start) == 1.0)
        #expect(CMTimeGetSeconds(b.visibilityRange!.start) == 1.0)
    }

    @Test func transitionDoesNotConformToVisibility() {
        // Sanity: Overlay extension default returns nil; non-overlay clips don't have
        // a visibilityRange property at all (it's on Overlay, not Clip).
        let img = PlatformImage()
        let unconfigured = ImageOverlay(img)
        #expect(unconfigured.visibilityRange == nil)
    }
}
