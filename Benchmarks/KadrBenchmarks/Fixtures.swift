import Foundation
import CoreMedia
import Kadr

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Compositions the benchmarks measure.
///
/// Built from solid-colour images rather than sample footage on purpose: a
/// benchmark that decodes a real asset measures the decoder, which is hardware,
/// varies by machine, and is the one thing this package does not implement.
/// Synthetic sources keep the measurement on the code under test — composition
/// building, the compositor, keyframe evaluation and the export pipeline.
enum Fixtures {

    static func image(_ shade: CGFloat) -> PlatformImage {
        let size = CGSize(width: 1080, height: 1920)
        #if canImport(UIKit)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: shade, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        #else
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(white: shade, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        img.unlockFocus()
        return img
        #endif
    }

    /// One clip, no overlays, no animation — the floor of the export pipeline.
    static func singleTrack(seconds: Double) -> Video {
        let img = image(0.2)
        return Video { ImageClip(img, duration: seconds) }
    }

    /// Several clips plus overlays, so `KadrVideoCompositor` runs per frame.
    /// This is the path v0.13's colour-space hoist and overlay coalescing were
    /// meant to speed up.
    static func multiTrack(clips: Int, seconds: Double) -> Video {
        let shades: [CGFloat] = [0.15, 0.35, 0.55, 0.75]
        return Video {
            for i in 0..<clips {
                ImageClip(image(shades[i % shades.count]), duration: seconds)
            }
        }
        .overlay(TextOverlay("Benchmark").id("a"))
        .overlay(TextOverlay("Second layer").id("b"))
    }

    /// A transform animated across many keyframes, so the animation sampler is
    /// the thing under load rather than the encoder.
    static func keyframeHeavy(keyframes: Int, seconds: Double) -> Video {
        let img = image(0.3)
        let frames: [Animation<Transform>.Keyframe] = (0..<keyframes).map { i in
            let t = seconds * Double(i) / Double(max(1, keyframes - 1))
            let scale = 1.0 + 0.5 * sin(Double(i))
            return .at(t, value: Transform(center: .center, rotation: 0, scale: scale, anchor: .center))
        }
        return Video {
            ImageClip(img, duration: seconds).transformAnimation(.keyframes(frames))
        }
    }
}
