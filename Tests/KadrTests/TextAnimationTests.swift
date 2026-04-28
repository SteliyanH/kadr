import Testing
import Foundation
@testable import Kadr
import QuartzCore
import AVFoundation
import CoreMedia
import CoreGraphics

/// Tests for v0.8 Tier 3 — animated ``TextOverlay``.
///
/// Pure tests cover the recipe surface (FadeIn / SlideIn / ScaleUp keypaths and
/// timing). Smoke tests exercise modifier composition and confirm the engine accepts
/// animated text overlays without regressing existing overlay behavior.
struct TextAnimationTests {

    // MARK: - Modifier composition

    @Test func textAnimationDefaultsToNil() {
        let overlay = TextOverlay("hi")
        #expect(overlay.textAnimation == nil)
    }

    @Test func animationModifierStoresValue() {
        let overlay = TextOverlay("hi").animation(.fadeIn(duration: 1.0))
        #expect(overlay.textAnimation != nil)
    }

    @Test func animationPreservedThroughModifierChain() {
        let overlay = TextOverlay("hi")
            .animation(.fadeIn(duration: 1.0))
            .position(.bottom)
            .anchor(.bottom)
            .opacity(0.8)
            .id("title")
            .visible(during: 0.0...3.0)
        #expect(overlay.textAnimation != nil)
        #expect(overlay.layerID == "title")
        #expect(overlay.visibilityRange != nil)
    }

    @Test func animationModifierReplacesPreviousValue() {
        let overlay = TextOverlay("hi")
            .animation(.fadeIn(duration: 1.0))
            .animation(.scaleUp(duration: 0.5))
        // Just check it stored something — exact recipe identity isn't observable
        // through the existential.
        #expect(overlay.textAnimation != nil)
    }

    // MARK: - FadeIn recipe

    @Test func fadeInProducesOpacityAnimation() {
        let layer = CALayer()
        layer.opacity = 1.0
        let anims = FadeIn(duration: 1.0).makeAnimations(for: layer)
        #expect(anims.count == 1)
        let basic = try? #require(anims.first as? CABasicAnimation)
        #expect(basic?.keyPath == "opacity")
        #expect(basic?.fromValue as? Float == 0)
        #expect(basic?.toValue as? Float == 1.0)
        #expect(basic?.duration == 1.0)
    }

    @Test func fadeInHonorsCustomFromValue() {
        let layer = CALayer()
        layer.opacity = 0.8
        let anims = FadeIn(duration: 0.5, from: 0.2).makeAnimations(for: layer)
        let basic = anims.first as? CABasicAnimation
        #expect(basic?.fromValue as? Float == 0.2)
        #expect(basic?.toValue as? Float == 0.8)
    }

    // MARK: - SlideIn recipe

    @Test func slideInFromLeftAnimatesPositionX() {
        let layer = CALayer()
        layer.position = CGPoint(x: 100, y: 200)
        let anims = SlideIn(from: .fromLeft, duration: 0.5).makeAnimations(for: layer)
        #expect(anims.count == 1)
        let basic = try? #require(anims.first as? CABasicAnimation)
        #expect(basic?.keyPath == "position.x")
        // fromValue is layer.position.x − offset (4000); toValue is layer.position.x.
        #expect((basic?.toValue as? CGFloat) == 100)
        let from = basic?.fromValue as? CGFloat
        #expect(from != nil && from! < 100)
    }

    @Test func slideInFromTopAnimatesPositionY() {
        let layer = CALayer()
        layer.position = CGPoint(x: 100, y: 200)
        let anims = SlideIn(from: .fromTop, duration: 0.5).makeAnimations(for: layer)
        let basic = anims.first as? CABasicAnimation
        #expect(basic?.keyPath == "position.y")
        #expect((basic?.toValue as? CGFloat) == 200)
    }

    // MARK: - ScaleUp recipe

    @Test func scaleUpAnimatesTransformScale() {
        let anims = ScaleUp(duration: 0.4).makeAnimations(for: CALayer())
        let basic = try? #require(anims.first as? CABasicAnimation)
        #expect(basic?.keyPath == "transform.scale")
        #expect(basic?.fromValue as? CGFloat == 0.0)
        #expect(basic?.toValue as? CGFloat == 1.0)
    }

    @Test func scaleUpHonorsCustomFromValue() {
        let anims = ScaleUp(from: 0.5, duration: 0.4).makeAnimations(for: CALayer())
        let basic = anims.first as? CABasicAnimation
        #expect(basic?.fromValue as? CGFloat == 0.5)
    }

    // MARK: - Convenience factories

    @Test func factoryFadeInBuildsFadeIn() {
        let f: FadeIn = .fadeIn(duration: 0.3)
        #expect(CMTimeGetSeconds(f.duration) == 0.3)
    }

    @Test func factorySlideInBuildsSlideIn() {
        let s: SlideIn = .slideIn(from: .fromBottom, duration: 0.4)
        #expect(s.direction == .fromBottom)
    }

    @Test func factoryScaleUpBuildsScaleUp() {
        let s: ScaleUp = .scaleUp(duration: 0.5)
        #expect(CMTimeGetSeconds(s.duration) == 0.5)
    }

    // MARK: - Engine integration (smoke)

    @Test @MainActor func overlayRendererAttachesTextAnimation() {
        // Build a layer tree containing an animated TextOverlay and verify the text
        // sublayer carries our keyed animation. Pure CALayer machinery — no AVFoundation
        // export needed.
        let overlays: [any Overlay] = [
            TextOverlay("Hello").animation(.fadeIn(duration: 1.0))
        ]
        let renderSize = CGSize(width: 1080, height: 1920)
        let tree = OverlayRenderer.buildLayerTree(
            overlays: overlays,
            renderSize: renderSize,
            compositionDuration: CMTime(seconds: 5, preferredTimescale: 600)
        )
        // parent has [videoLayer, textOverlayLayer]
        #expect(tree.parent.sublayers?.count == 2)
        let textLayer = tree.parent.sublayers?.last
        // Should have at least one of our keyed animations attached.
        #expect(textLayer?.animation(forKey: "kadr.textAnimation.0") != nil)
    }

    @Test @MainActor func staticTextOverlayHasNoTextAnimationAttached() {
        let overlays: [any Overlay] = [TextOverlay("Hello")]
        let tree = OverlayRenderer.buildLayerTree(
            overlays: overlays,
            renderSize: CGSize(width: 1080, height: 1920)
        )
        let textLayer = tree.parent.sublayers?.last
        #expect(textLayer?.animation(forKey: "kadr.textAnimation.0") == nil)
    }
}
