import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Chroma-key (green-screen) configuration. Removes pixels whose chroma falls within
/// `threshold` of `color`'s chroma; everything else is preserved.
///
/// Construction precomputes a `dimension³` color-cube — a one-time cost reused across
/// every frame the filter is applied to. Stored as ``Filter/chromaKey(_:)``'s associated
/// value so a single `ChromaKey` instance can drive multiple clips without rebuilding
/// the cube.
///
/// ```swift
/// let key = ChromaKey(color: .green, threshold: 0.35)
/// VideoClip(url: subjectURL).filter(.chromaKey(key))
/// VideoClip(url: anotherSubjectURL).filter(.chromaKey(key))
///
/// // Or one-shot:
/// VideoClip(url: subjectURL).filter(.chromaKey(color: .green, threshold: 0.35))
/// ```
///
/// **Algorithm.** Per cube entry, the (R, G, B) sample is converted to ITU-R BT.601
/// `(Cb, Cr)` chroma coordinates; the Euclidean distance from the target's `(Cb, Cr)`
/// is compared to `threshold`. Inside → alpha 0 (premultiplied RGB also zeroed; required
/// by `CIColorCube`). Outside → alpha 1 with original RGB.
///
/// `threshold` is in chroma-space units, roughly `0...1`. `0.35` is a reasonable starting
/// point for green-screen footage; raise for forgiving spill, lower for surgical removal.
public struct ChromaKey: Sendable, Equatable {

    /// Cube side length. 64 gives ~262k entries (4 MB of RGBA Float32) — a good balance
    /// between cube build cost, memory, and chroma-edge fidelity.
    internal static let cubeDimension = 64

    /// Target chroma-key color, stored as packed `(r, g, b)` in `[0, 1]`.
    public let color: ColorComponents

    /// Chroma-distance threshold; pixels within this distance of `color`'s chroma
    /// are removed. Roughly `0...1`.
    public let threshold: Double

    internal let cubeData: Data

    /// Build a chroma-key configuration from a target color and chroma threshold.
    /// Construction synchronously precomputes the color cube; reuse the value across
    /// clips to avoid rebuilding.
    public init(color: PlatformColor, threshold: Double) {
        let comp = ColorComponents(platformColor: color)
        self.color = comp
        self.threshold = threshold
        self.cubeData = ChromaKey.buildCube(target: comp, threshold: threshold)
    }

    /// Pure: build the chroma-key color cube. Internal so the math is unit-testable
    /// without going through a `PlatformColor`.
    internal static func buildCube(target: ColorComponents, threshold: Double) -> Data {
        let n = cubeDimension
        let nF = Float(n - 1)
        let (targetCb, targetCr) = bt601Chroma(r: Float(target.r), g: Float(target.g), b: Float(target.b))
        let thresholdSquared = Float(threshold * threshold)

        var floats = [Float]()
        floats.reserveCapacity(n * n * n * 4)

        // CIColorCube traversal order: outer = blue, middle = green, inner = red.
        for bIdx in 0..<n {
            let b = Float(bIdx) / nF
            for gIdx in 0..<n {
                let g = Float(gIdx) / nF
                for rIdx in 0..<n {
                    let r = Float(rIdx) / nF
                    let (cb, cr) = bt601Chroma(r: r, g: g, b: b)
                    let dCb = cb - targetCb
                    let dCr = cr - targetCr
                    let distSq = dCb * dCb + dCr * dCr
                    let alpha: Float = distSq < thresholdSquared ? 0 : 1
                    // CIColorCube expects premultiplied alpha — when alpha=0, RGB must be 0.
                    floats.append(r * alpha)
                    floats.append(g * alpha)
                    floats.append(b * alpha)
                    floats.append(alpha)
                }
            }
        }

        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// ITU-R BT.601 RGB → (Cb, Cr). Chroma is what humans perceive as hue+saturation
    /// independent of luminance, which is what we want for chroma-keying — bright and
    /// dark greens both belong to "green" and should be removed by the same key.
    private static func bt601Chroma(r: Float, g: Float, b: Float) -> (Float, Float) {
        let cb = -0.169 * r - 0.331 * g + 0.500 * b + 0.5
        let cr =  0.500 * r - 0.419 * g - 0.081 * b + 0.5
        return (cb, cr)
    }
}

/// Packed RGB color components in `[0, 1]`. Internal-extraction helper for
/// ``ChromaKey``; lets the type be `Equatable` without depending on `PlatformColor`'s
/// equality (which is platform-asymmetric — `NSColor` lacks `Equatable`).
public struct ColorComponents: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(platformColor color: PlatformColor) {
        var rOut: CGFloat = 0, gOut: CGFloat = 0, bOut: CGFloat = 0, aOut: CGFloat = 0
        #if canImport(UIKit)
        color.getRed(&rOut, green: &gOut, blue: &bOut, alpha: &aOut)
        #elseif canImport(AppKit)
        // NSColor must be in a calibrated/extended-sRGB space before component access.
        let normalized = color.usingColorSpace(.sRGB) ?? color
        normalized.getRed(&rOut, green: &gOut, blue: &bOut, alpha: &aOut)
        #endif
        self.r = Double(rOut)
        self.g = Double(gOut)
        self.b = Double(bOut)
    }
}
