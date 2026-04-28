import Testing
import Foundation
@testable import Kadr
import QuartzCore
import AVFoundation
import CoreMedia
import CoreGraphics

/// Tests for v0.8.1 — public `Animatable` on `Position` / `Size`, plus animated
/// `.position(_:animation:)` / `.size(_:animation:)` on image / sticker overlays.
struct OverlayLayoutAnimationTests {

    // MARK: - Position Animatable conformance (now public)

    @Test func positionInterpolatesNormalizedComponentsLinearly() {
        let a = Position.normalized(x: 0.0, y: 0.0)
        let b = Position.normalized(x: 1.0, y: 1.0)
        let mid = Position.interpolate(a, b, t: 0.5)
        guard case .normalized(let x, let y) = mid else {
            Issue.record("expected normalized result")
            return
        }
        #expect(x == 0.5)
        #expect(y == 0.5)
    }

    @Test func positionInterpolatesPixelComponentsLinearly() {
        let a = Position.pixels(x: 0, y: 0)
        let b = Position.pixels(x: 100, y: 200)
        let mid = Position.interpolate(a, b, t: 0.25)
        guard case .pixels(let x, let y) = mid else {
            Issue.record("expected pixels result")
            return
        }
        #expect(x == 25)
        #expect(y == 50)
    }

    @Test func positionMixedTypesResolveToNormalized() {
        let a = Position.normalized(x: 0.0, y: 0.0)
        let b = Position.pixels(x: 1, y: 1)  // resolved at unit canvas → (1, 1)
        let mid = Position.interpolate(a, b, t: 0.5)
        guard case .normalized(let x, let y) = mid else {
            Issue.record("mixed-type interpolation should yield .normalized")
            return
        }
        #expect(x == 0.5)
        #expect(y == 0.5)
    }

    // MARK: - Size Animatable conformance

    @Test func sizeInterpolatesNormalizedComponentsLinearly() {
        let a = Size.normalized(width: 0.2, height: 0.2)
        let b = Size.normalized(width: 0.8, height: 0.8)
        let mid = Size.interpolate(a, b, t: 0.5)
        guard case .normalized(let w, let h) = mid else {
            Issue.record("expected normalized result")
            return
        }
        #expect(w == 0.5)
        #expect(h == 0.5)
    }

    @Test func sizeInterpolatesPixelComponentsLinearly() {
        let a = Size.pixels(width: 100, height: 200)
        let b = Size.pixels(width: 200, height: 400)
        let mid = Size.interpolate(a, b, t: 0.5)
        guard case .pixels(let w, let h) = mid else {
            Issue.record("expected pixels result")
            return
        }
        #expect(w == 150)
        #expect(h == 300)
    }

    @Test func sizeMixedTypesResolveToNormalized() {
        // .normalized(0.5, 0.5) ↔ .pixels(1, 1) at unit canvas → both (1, 1) and (0.5, 0.5).
        // Lerp at t=0.5 produces normalized (0.75, 0.75).
        let a = Size.normalized(width: 0.5, height: 0.5)
        let b = Size.pixels(width: 1, height: 1)
        let mid = Size.interpolate(a, b, t: 0.5)
        guard case .normalized = mid else {
            Issue.record("mixed-type interpolation should yield .normalized")
            return
        }
    }

    // MARK: - Modifier composition

    @Test func imageOverlayPositionAnimationDefaultsToNil() {
        let overlay = ImageOverlay(PlatformImage())
        #expect(overlay.positionAnimation == nil)
        #expect(overlay.sizeAnimation == nil)
    }

    @Test func imageOverlayPositionAnimationModifierStoresValue() {
        let anim = Animation<Position>.keyframes([
            .at(0.0, value: .topLeft),
            .at(1.0, value: .bottomRight),
        ])
        let overlay = ImageOverlay(PlatformImage()).position(.center, animation: anim)
        #expect(overlay.positionAnimation != nil)
    }

    @Test func imageOverlaySizeAnimationModifierStoresValue() {
        let anim = Animation<Size>.keyframes([
            .at(0.0, value: .normalized(width: 0.2, height: 0.2)),
            .at(1.0, value: .normalized(width: 0.5, height: 0.5)),
        ])
        let overlay = ImageOverlay(PlatformImage()).size(
            .normalized(width: 0.2, height: 0.2),
            animation: anim
        )
        #expect(overlay.sizeAnimation != nil)
    }

    @Test func stickerOverlayPositionAndSizeAnimationsCompose() {
        let posAnim = Animation<Position>.keyframes([
            .at(0.0, value: .topLeft),
            .at(2.0, value: .topRight),
        ])
        let sizeAnim = Animation<Size>.keyframes([
            .at(0.0, value: .normalized(width: 0.1, height: 0.1)),
            .at(2.0, value: .normalized(width: 0.3, height: 0.3)),
        ])
        let overlay = StickerOverlay(PlatformImage())
            .position(.center, animation: posAnim)
            .size(.normalized(width: 0.2, height: 0.2), animation: sizeAnim)
            .opacity(0.8)
            .id("animated-sticker")
        #expect(overlay.positionAnimation != nil)
        #expect(overlay.sizeAnimation != nil)
        #expect(overlay.layerID == "animated-sticker")
    }

    @Test func textOverlayPositionAndSizeAnimationsAreNilByDefault() {
        // TextOverlay doesn't override the Overlay protocol's defaults in v0.8.1,
        // so its layout animation getters return nil. Engine should treat them as
        // unanimated. (Animated text overlays ship via TextAnimation in v0.8.0.)
        let overlay = TextOverlay("hi")
        #expect(overlay.positionAnimation == nil)
        #expect(overlay.sizeAnimation == nil)
    }

    // MARK: - Engine integration (smoke)

    @Test @MainActor func overlayRendererAttachesPositionAnimation() {
        let posAnim = Animation<Position>.keyframes([
            .at(0.0, value: .topLeft),
            .at(2.0, value: .bottomRight),
        ])
        let overlays: [any Overlay] = [
            ImageOverlay(PlatformImage())
                .position(.center, animation: posAnim)
        ]
        let tree = OverlayRenderer.buildLayerTree(
            overlays: overlays,
            renderSize: CGSize(width: 1080, height: 1920),
            compositionDuration: CMTime(seconds: 5, preferredTimescale: 600)
        )
        let overlayLayer = tree.parent.sublayers?.last
        #expect(overlayLayer?.animation(forKey: "kadr.positionAnimation") != nil)
        // No size animation declared, so no bounds.size keyframes attached.
        #expect(overlayLayer?.animation(forKey: "kadr.sizeAnimation") == nil)
    }

    @Test @MainActor func overlayRendererAttachesBothPositionAndSizeAnimationsWhenSizeIsAnimated() {
        let sizeAnim = Animation<Size>.keyframes([
            .at(0.0, value: .normalized(width: 0.2, height: 0.2)),
            .at(2.0, value: .normalized(width: 0.5, height: 0.5)),
        ])
        let overlays: [any Overlay] = [
            ImageOverlay(PlatformImage())
                .size(.normalized(width: 0.2, height: 0.2), animation: sizeAnim)
        ]
        let tree = OverlayRenderer.buildLayerTree(
            overlays: overlays,
            renderSize: CGSize(width: 1080, height: 1920),
            compositionDuration: CMTime(seconds: 5, preferredTimescale: 600)
        )
        let overlayLayer = tree.parent.sublayers?.last
        // Size animation also implies position animation (the resolved frame's center
        // shifts as size grows around the anchor).
        #expect(overlayLayer?.animation(forKey: "kadr.positionAnimation") != nil)
        #expect(overlayLayer?.animation(forKey: "kadr.sizeAnimation") != nil)
    }

    @Test @MainActor func staticOverlayHasNoLayoutAnimationsAttached() {
        let overlays: [any Overlay] = [
            ImageOverlay(PlatformImage()).position(.topRight)
        ]
        let tree = OverlayRenderer.buildLayerTree(
            overlays: overlays,
            renderSize: CGSize(width: 1080, height: 1920),
            compositionDuration: CMTime(seconds: 3, preferredTimescale: 600)
        )
        let overlayLayer = tree.parent.sublayers?.last
        #expect(overlayLayer?.animation(forKey: "kadr.positionAnimation") == nil)
        #expect(overlayLayer?.animation(forKey: "kadr.sizeAnimation") == nil)
    }
}
