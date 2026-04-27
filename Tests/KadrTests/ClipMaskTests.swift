import Testing
import Foundation
import Kadr
import CoreImage
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Tests for the v0.5.0 ``VideoClip/mask(_:)-(CIImage)`` and
/// ``VideoClip/mask(_:)-(PlatformImage)`` modifiers — Tier 3 of the v0.5 cycle, built
/// on top of the public ``Compositor`` protocol via the internal `MaskCompositor`.
struct ClipMaskTests {

    /// A small grayscale CIImage with full opacity, suitable as a mask for sanity tests.
    private func solidMaskCIImage(size: CGSize = CGSize(width: 100, height: 100)) -> CIImage {
        CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
    }

    @Test func maskCIImageAppendsACompositor() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url).mask(solidMaskCIImage())
        #expect(clip.compositors.count == 1)
    }

    @Test func maskPreservesPriorCompositors() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .compositor { image, _ in image }
            .mask(solidMaskCIImage())
        #expect(clip.compositors.count == 2)
    }

    @Test func multipleMasksAccumulate() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .mask(solidMaskCIImage())
            .mask(solidMaskCIImage())
        #expect(clip.compositors.count == 2)
    }

    @Test func maskSurvivesModifierChain() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .mask(solidMaskCIImage())
            .trimmed(to: 0.0...5.0)
            .speed(2.0)
            .filter(.brightness(0.1))
            .id("hero")
        #expect(clip.compositors.count == 1)
        #expect(clip.clipID == ClipID("hero"))
    }

    @Test func maskCropAndOtherCompositorsCoexist() {
        // .crop and .mask both append Compositors; chaining them produces an array of
        // two distinct compositors that run in declaration order.
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .crop(at: .center, size: .normalized(width: 0.8, height: 0.8))
            .mask(solidMaskCIImage())
        #expect(clip.compositors.count == 2)
    }

    @Test func platformImageMaskExtractsCIImage() {
        // PlatformImage overload should add a compositor (success path).
        // Construct a minimal opaque platform image.
        #if canImport(UIKit)
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 32, height: 32), false, 1)
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        let platformImage = img
        #elseif canImport(AppKit)
        let platformImage = NSImage(size: NSSize(width: 32, height: 32))
        platformImage.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        platformImage.unlockFocus()
        #endif

        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url).mask(platformImage)
        #expect(clip.compositors.count == 1)
    }
}
