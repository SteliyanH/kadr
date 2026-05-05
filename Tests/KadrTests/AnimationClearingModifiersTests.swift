import Testing
import Foundation
@testable import Kadr
import CoreMedia
import CoreGraphics

/// Tests for v0.10.1 — `transformAnimation(_:)` / `opacityAnimation(_:)` /
/// `filterAnimation(at:_:)` / `positionAnimation(_:)` / `sizeAnimation(_:)`
/// setter modifiers across `VideoClip` / `ImageClip` / `TitleSequence` /
/// `ImageOverlay` / `StickerOverlay`.
struct AnimationClearingModifiersTests {

    // MARK: - Fixtures

    private func videoClip() -> VideoClip {
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        return VideoClip(url: url)
            .trimmed(to: 0...4)
            .filter(.brightness(0.3))
            .filter(.contrast(1.5))
            .transform(.identity)
            .opacity(0.8)
            .id("vid-1")
    }

    private func imageClip() -> ImageClip {
        ImageClip(PlatformImage(), duration: 2.0)
            .transform(.identity)
            .opacity(0.5)
            .id("img-1")
    }

    private func titleSequence() -> TitleSequence {
        TitleSequence("Hi", duration: 1.0, style: .default)
            .transform(.identity)
            .opacity(0.7)
            .id("title-1")
    }

    private func imageOverlay() -> ImageOverlay {
        ImageOverlay(PlatformImage())
            .position(.center)
            .opacity(0.9)
            .id("overlay-1")
    }

    private func stickerOverlay() -> StickerOverlay {
        StickerOverlay(PlatformImage())
            .position(.topRight)
            .rotation(0.5)
            .opacity(0.6)
            .id("sticker-1")
    }

    private func transformAnim() -> Animation<Transform> {
        .keyframes([
            .at(0.0, value: .identity),
            .at(2.0, value: Transform(center: .center, rotation: 0, scale: 1.5, anchor: .center))
        ])
    }

    private func doubleAnim() -> Animation<Double> {
        .keyframes([
            .at(0.0, value: 0.0),
            .at(2.0, value: 1.0)
        ])
    }

    // MARK: - VideoClip.transformAnimation

    @Test func videoTransformAnimationSetsField() {
        let clip = videoClip().transformAnimation(transformAnim())
        #expect(clip.transformAnimation != nil)
        #expect(clip.transformAnimation?.keyframes.count == 2)
    }

    @Test func videoTransformAnimationNilClearsField() {
        let withAnim = videoClip().transformAnimation(transformAnim())
        let cleared = withAnim.transformAnimation(nil)
        #expect(cleared.transformAnimation == nil)
    }

    @Test func videoTransformAnimationPreservesOtherFields() {
        let original = videoClip()
        let withAnim = original.transformAnimation(transformAnim())
        #expect(withAnim.url == original.url)
        #expect(withAnim.trimRange == original.trimRange)
        #expect(withAnim.filters.count == original.filters.count)
        #expect(withAnim.transform != nil)  // static base preserved
        #expect(withAnim.opacity == original.opacity)
        #expect(withAnim.clipID == original.clipID)
    }

    // MARK: - VideoClip.opacityAnimation

    @Test func videoOpacityAnimationSetsField() {
        let clip = videoClip().opacityAnimation(doubleAnim())
        #expect(clip.opacityAnimation != nil)
    }

    @Test func videoOpacityAnimationNilClearsField() {
        let cleared = videoClip().opacityAnimation(doubleAnim()).opacityAnimation(nil)
        #expect(cleared.opacityAnimation == nil)
        #expect(cleared.opacity == 0.8)  // static base preserved
    }

    // MARK: - VideoClip.filterAnimation(at:)

    @Test func filterAnimationAtIndexSetsCorrectSlot() {
        let clip = videoClip().filterAnimation(at: 0, doubleAnim())
        #expect(clip.filterAnimations.count == 2)
        #expect(clip.filterAnimations[0] != nil)
        #expect(clip.filterAnimations[1] == nil)
    }

    @Test func filterAnimationAtIndexNilClearsSlot() {
        let withAnim = videoClip().filterAnimation(at: 0, doubleAnim())
        let cleared = withAnim.filterAnimation(at: 0, nil)
        #expect(cleared.filterAnimations[0] == nil)
        #expect(cleared.filters.count == 2)  // filters preserved
    }

    @Test func filterAnimationAtOutOfRangeIndexIsNoOp() {
        let original = videoClip()
        let result = original.filterAnimation(at: 99, doubleAnim())
        #expect(result.filterAnimations.allSatisfy { $0 == nil })
        #expect(result.filters.count == original.filters.count)
    }

    @Test func filterAnimationAtNegativeIndexIsNoOp() {
        let original = videoClip()
        let result = original.filterAnimation(at: -1, doubleAnim())
        #expect(result.filterAnimations.allSatisfy { $0 == nil })
    }

    @Test func filterAnimationDoesNotDisturbOtherSlots() {
        let twoAnims = videoClip()
            .filterAnimation(at: 0, doubleAnim())
            .filterAnimation(at: 1, doubleAnim())
        let oneCleared = twoAnims.filterAnimation(at: 0, nil)
        #expect(oneCleared.filterAnimations[0] == nil)
        #expect(oneCleared.filterAnimations[1] != nil)
    }

    // MARK: - ImageClip

    @Test func imageTransformAnimationRoundTrips() {
        let withAnim = imageClip().transformAnimation(transformAnim())
        #expect(withAnim.transformAnimation != nil)
        let cleared = withAnim.transformAnimation(nil)
        #expect(cleared.transformAnimation == nil)
        #expect(cleared.transform != nil)
        #expect(cleared.opacity == 0.5)
        #expect(cleared.clipID == "img-1")
    }

    @Test func imageOpacityAnimationRoundTrips() {
        let withAnim = imageClip().opacityAnimation(doubleAnim())
        #expect(withAnim.opacityAnimation != nil)
        let cleared = withAnim.opacityAnimation(nil)
        #expect(cleared.opacityAnimation == nil)
        #expect(cleared.opacity == 0.5)
    }

    // MARK: - TitleSequence

    @Test func titleTransformAnimationRoundTrips() {
        let withAnim = titleSequence().transformAnimation(transformAnim())
        #expect(withAnim.transformAnimation != nil)
        let cleared = withAnim.transformAnimation(nil)
        #expect(cleared.transformAnimation == nil)
        #expect(cleared.text == "Hi")
        #expect(cleared.opacity == 0.7)
        #expect(cleared.clipID == "title-1")
    }

    @Test func titleOpacityAnimationRoundTrips() {
        let withAnim = titleSequence().opacityAnimation(doubleAnim())
        #expect(withAnim.opacityAnimation != nil)
        let cleared = withAnim.opacityAnimation(nil)
        #expect(cleared.opacityAnimation == nil)
        #expect(cleared.opacity == 0.7)
    }

    // MARK: - ImageOverlay

    @Test func imageOverlayPositionAnimationSetsAndClears() {
        let positionAnim = Animation<Position>.keyframes([
            .at(0.0, value: .topLeft),
            .at(2.0, value: .bottomRight)
        ])
        let withAnim = imageOverlay().positionAnimation(positionAnim)
        #expect(withAnim.positionAnimation != nil)
        let cleared = withAnim.positionAnimation(nil)
        #expect(cleared.positionAnimation == nil)
        #expect(cleared.opacity == 0.9)  // other fields preserved
    }

    @Test func imageOverlaySizeAnimationSetsAndClears() {
        let sizeAnim = Animation<Size>.keyframes([
            .at(0.0, value: .normalized(width: 0.5, height: 0.5)),
            .at(2.0, value: .normalized(width: 1.0, height: 1.0))
        ])
        let withAnim = imageOverlay().sizeAnimation(sizeAnim)
        #expect(withAnim.sizeAnimation != nil)
        let cleared = withAnim.sizeAnimation(nil)
        #expect(cleared.sizeAnimation == nil)
    }

    // MARK: - StickerOverlay

    @Test func stickerPositionAnimationPreservesRotationAndShadow() {
        let positionAnim = Animation<Position>.keyframes([
            .at(0.0, value: .topRight),
            .at(2.0, value: .center)
        ])
        let withAnim = stickerOverlay().positionAnimation(positionAnim)
        #expect(withAnim.positionAnimation != nil)
        #expect(withAnim.rotation == 0.5)
        #expect(withAnim.opacity == 0.6)
    }

    @Test func stickerSizeAnimationPreservesRotation() {
        let sizeAnim = Animation<Size>.keyframes([
            .at(0.0, value: .normalized(width: 0.3, height: 0.3))
        ])
        let cleared = stickerOverlay().sizeAnimation(sizeAnim).sizeAnimation(nil)
        #expect(cleared.sizeAnimation == nil)
        #expect(cleared.rotation == 0.5)
    }
}
