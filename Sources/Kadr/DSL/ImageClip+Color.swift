import Foundation
import CoreMedia
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension ImageClip {

    /// Build an `ImageClip` filled with a solid color. Memory-efficient (1×1 source
    /// image stretched by the engine's aspect-fill); artifact-free on stretch
    /// because every pixel is identical. Convenient for backgrounds, color cards,
    /// or sample compositions.
    ///
    /// ```swift
    /// Video {
    ///     ImageClip.color(.black, duration: 1.0)        // 1-second black card
    ///     VideoClip(url: clipURL).trimmed(to: 0...10)
    /// }
    /// ```
    ///
    /// Added in v0.10.
    public static func color(_ color: PlatformColor, duration: CMTime) -> ImageClip {
        ImageClip(makeSolidColorImage(color), duration: duration)
    }

    /// `TimeInterval` overload. Default duration `3.0` seconds.
    public static func color(_ color: PlatformColor, duration: TimeInterval = 3.0) -> ImageClip {
        Self.color(color, duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    /// Build a 1×1 solid-color `PlatformImage`. Internal — exposed for testing.
    nonisolated internal static func makeSolidColorImage(_ color: PlatformColor) -> PlatformImage {
        let size = CGSize(width: 1, height: 1)
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
        #endif
    }
}
