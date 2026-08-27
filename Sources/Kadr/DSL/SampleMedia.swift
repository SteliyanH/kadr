import Foundation
import CoreMedia
import CoreGraphics

/// Ready-made media for trying kadr out, writing a sample, or filling a preview.
///
/// **Why this exists.** Every API in this library takes media as input, and a
/// newcomer has none to hand. The first thing anyone does with `VideoPreview` or
/// `Video.export(to:)` is look for something to point it at, and until v0.20 the
/// answer was "find a video file". The reference app ended up synthesising one out
/// of solid-colour image clips, which is a workaround the library should have made
/// unnecessary.
///
/// **Nothing is bundled.** Everything here is generated, so the package carries no
/// binary media, adds nothing to a consumer's checkout, and works offline and
/// deterministically. A colour-bar frame is a better fixture than a stock clip
/// anyway: motion and colour are obvious at a glance, so a transform, a filter or a
/// crop is visibly right or wrong.
///
/// Added in v0.20.
public enum SampleMedia {

    /// A composition that plays and exports immediately.
    ///
    /// ```swift
    /// VideoPreview(video: SampleMedia.video())          // something to look at
    /// try await SampleMedia.video().export(to: url)     // something to export
    /// ```
    ///
    /// Four colour segments of equal length, so cuts are visible without counting
    /// frames. Use ``movieFileURL(seconds:preset:)`` instead when an API needs a
    /// file URL rather than a `Video`.
    public static func video(seconds: Double = 4, preset: Preset = .auto) -> Video {
        let count = 4
        let each = CMTime(seconds: max(0.1, seconds) / Double(count), preferredTimescale: 600)
        return Video {
            for index in 0..<count {
                ImageClip(bars(index: index, size: preset.resolution), duration: each)
            }
        }
        .preset(preset)
    }

    /// A single generated frame, for `ImageClip`, an overlay, or a thumbnail
    /// placeholder.
    ///
    /// `index` selects one of four colour arrangements; any integer is valid and
    /// wraps, so `0...` walks the set.
    public static func image(index: Int = 0, size: CGSize = CGSize(width: 1080, height: 1920)) -> PlatformImage {
        bars(index: index, size: size)
    }

    /// A real `.mp4` written to the temporary directory, for the APIs that need a
    /// file URL rather than a `Video` — `VideoClip(url:)` above all.
    ///
    /// The caller owns the file and should delete it when finished. It is written to
    /// `FileManager.default.temporaryDirectory`, so the system will eventually
    /// reclaim it either way.
    ///
    /// ```swift
    /// let url = try await SampleMedia.movieFileURL()
    /// defer { try? FileManager.default.removeItem(at: url) }
    /// let clip = VideoClip(url: url).trimmed(to: 0...2)
    /// ```
    public static func movieFileURL(seconds: Double = 4, preset: Preset = .auto) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadr-sample-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        return try await video(seconds: seconds, preset: preset).export(to: url)
    }

    // MARK: - Frame generation

    /// Colour bars with a moving block, so both the palette and the position change
    /// between frames. A still gradient would look the same in every clip and make a
    /// broken cut invisible.
    private static func bars(index: Int, size: CGSize) -> PlatformImage {
        let palettes: [[CGColor]] = [
            [CGColor(red: 0.86, green: 0.24, blue: 0.16, alpha: 1), CGColor(red: 0.98, green: 0.75, blue: 0.18, alpha: 1)],
            [CGColor(red: 0.16, green: 0.50, blue: 0.73, alpha: 1), CGColor(red: 0.40, green: 0.80, blue: 0.90, alpha: 1)],
            [CGColor(red: 0.18, green: 0.62, blue: 0.40, alpha: 1), CGColor(red: 0.65, green: 0.86, blue: 0.35, alpha: 1)],
            [CGColor(red: 0.45, green: 0.30, blue: 0.65, alpha: 1), CGColor(red: 0.80, green: 0.60, blue: 0.90, alpha: 1)],
        ]
        let palette = palettes[((index % palettes.count) + palettes.count) % palettes.count]
        let width = max(2, Int(size.width))
        let height = max(2, Int(size.height))

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return PlatformImage()
        }

        let barCount = 6
        let barWidth = CGFloat(width) / CGFloat(barCount)
        for bar in 0..<barCount {
            context.setFillColor(bar.isMultiple(of: 2) ? palette[0] : palette[1])
            context.fill(CGRect(x: CGFloat(bar) * barWidth, y: 0, width: barWidth, height: CGFloat(height)))
        }

        // A block that steps across the frame, so consecutive clips differ in
        // position as well as colour.
        let blockSize = CGFloat(min(width, height)) / 5
        let step = (CGFloat(width) - blockSize) / 3
        let x = step * CGFloat(((index % 4) + 4) % 4)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        context.fill(CGRect(x: x, y: (CGFloat(height) - blockSize) / 2, width: blockSize, height: blockSize))

        guard let cgImage = context.makeImage() else { return PlatformImage() }
        #if canImport(UIKit)
        return PlatformImage(cgImage: cgImage)
        #else
        return PlatformImage(cgImage: cgImage, size: size)
        #endif
    }
}
