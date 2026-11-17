import AVFoundation
import Foundation
import ImageIO
import Kadr
import UniformTypeIdentifiers

/// Renders the README's GIFs by running the README's own snippets.
///
/// Each GIF comes from the exact code printed next to it. The snippet is
/// compiled from README.md into `ReadmeSnippets.swift`, run against the media
/// `ReadmeArt` draws, exported by kadr, and only then turned into a GIF. If the
/// code and the picture ever disagree, re-rendering fixes the picture.
///
///     swift run KadrReadmeMedia            # writes docs/media/*.gif
///     swift run KadrReadmeMedia hero       # just one
public enum ReadmeMediaRenderer {

    struct Recipe {
        let name: String
        /// GIF width in pixels. Height follows the video's aspect ratio.
        let width: Int
        let run: () async throws -> Void
    }

    static var recipes: [Recipe] { [
        Recipe(name: "hero", width: 560, run: readmeSnippet_hero),
        Recipe(name: "slideshow", width: 400, run: readmeSnippet_slideshow),
        Recipe(name: "vertical", width: 220, run: readmeSnippet_vertical),
        Recipe(name: "pip", width: 400, run: readmeSnippet_pip),
        Recipe(name: "greenScreen", width: 400, run: readmeSnippet_greenScreen),
        Recipe(name: "speedRamp", width: 400, run: readmeSnippet_speedRamp),
        Recipe(name: "titles", width: 400, run: readmeSnippet_titles),
    ] }

    /// GIF frame rate. 12 fps keeps motion readable and files small.
    static let fps = 12.0

    public static func render(into directory: URL, only names: Set<String> = []) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("Drawing source media into \(ReadmeArt.directory.path)")
        try await ReadmeArt.prepare()

        for recipe in recipes where names.isEmpty || names.contains(recipe.name) {
            try? FileManager.default.removeItem(at: outputURL)
            try await recipe.run()
            let gif = directory.appendingPathComponent("\(recipe.name).gif")
            let frames = try await writeGIF(from: outputURL, to: gif, width: recipe.width)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: gif.path)[.size] as? Int) ?? 0
            print("\(recipe.name).gif  \(frames) frames  \(bytes / 1024) KB")
        }

        if names.isEmpty || names.contains("comparison") {
            try await verifyComparison()
        }
    }

    /// The README claims its raw AVFoundation snippet makes the same video as
    /// the kadr one. Run both and compare frames, so the claim stays true.
    static func verifyComparison() async throws {
        func render(_ snippet: () async throws -> Void, as name: String) async throws -> URL {
            try? FileManager.default.removeItem(at: outputURL)
            try await snippet()
            let kept = ReadmeArt.url(name)
            try? FileManager.default.removeItem(at: kept)
            try FileManager.default.moveItem(at: outputURL, to: kept)
            return kept
        }
        let kadr = try await render(readmeSnippet_kadrVertical, as: "comparison-kadr.mp4")
        let raw = try await render(readmeSnippet_rawAVFoundation, as: "comparison-raw.mp4")

        var worst = 0.0
        for seconds in [0.5, 3.0, 5.5] {
            let a = try await frame(of: kadr, at: seconds), b = try await frame(of: raw, at: seconds)
            guard a.width == b.width, a.height == b.height else {
                throw KadrError.unsupportedFormat("kadr made \(a.width)×\(a.height), raw AVFoundation \(b.width)×\(b.height)")
            }
            worst = max(worst, meanDifference(a.pixels, b.pixels))
        }
        // Two encodes of the same frames differ by a few levels, not more.
        guard worst < 6 else {
            throw KadrError.unsupportedFormat("README comparison: frames differ by \(worst) levels on average")
        }
        print("comparison: kadr and raw AVFoundation match (mean difference \(String(format: "%.2f", worst)) of 255)")
    }

    private static func frame(of movie: URL, at seconds: Double) async throws -> (width: Int, height: Int, pixels: [UInt8]) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, pixels)
    }

    private static func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0
        for i in stride(from: 0, to: min(a.count, b.count), by: 4) {
            total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
        }
        return Double(total) / Double(a.count / 4 * 3)
    }

    /// Samples `movie` at `fps` and writes a looping GIF `width` pixels wide.
    static func writeGIF(from movie: URL, to gif: URL, width: Int) async throws -> Int {
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: width, height: width * 4)

        let count = max(1, Int(duration * fps))
        try? FileManager.default.removeItem(at: gif)
        guard let destination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw KadrError.unsupportedFormat("Cannot write \(gif.lastPathComponent)")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1 / fps,
                kCGImagePropertyGIFUnclampedDelayTime: 1 / fps,
            ],
        ] as CFDictionary

        for index in 0..<count {
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(destination, image, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw KadrError.unsupportedFormat("Could not finish \(gif.lastPathComponent)")
        }
        return count
    }
}
