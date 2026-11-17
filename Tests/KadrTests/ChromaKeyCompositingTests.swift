import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A chroma-keyed clip on top of another clip must let that clip show through.
///
/// `ChromaKeyTests` covers the key's colour maths. This covers what a green-screen
/// user actually sees: subject over background, in an exported file.
///
/// Time-limited so an encoder that stalls (for example HEVC with alpha on a
/// virtualised CI runner) fails this suite by name instead of hanging the job.
@Suite(.timeLimit(.minutes(1)))
struct ChromaKeyCompositingTests {

    private let preset: Preset = .custom(width: 128, height: 64, frameRate: 30, codec: .h264)

    private typealias RGB = (r: UInt8, g: UInt8, b: UInt8)
    private let green: RGB = (0, 255, 0), red: RGB = (255, 0, 0), blue: RGB = (0, 0, 255)

    /// 128×64 with `left` on the left half and `right` on the right half.
    private func makeMovie(left: RGB, right: RGB, seconds: Double = 1) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chroma_subject_\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        guard writer.startWriting(), let pool = adaptor.pixelBufferPool else {
            throw KadrError.unsupportedFormat("Could not start the fixture writer")
        }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<Int(seconds * 30) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { throw KadrError.unsupportedFormat("No pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<64 {
                for x in 0..<128 {
                    let p = base + y * bytesPerRow + x * 4   // BGRA
                    let c = x < 64 ? left : right
                    p[0] = c.b; p[1] = c.g; p[2] = c.r
                    p[3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
    }

    private func solid(red: CGFloat, green: CGFloat, blue: CGFloat) -> PlatformImage {
        let context = CGContext(data: nil, width: 128, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
        let image = context.makeImage()!
        #if canImport(UIKit)
        return UIImage(cgImage: image)
        #else
        return NSImage(cgImage: image, size: NSSize(width: 128, height: 64))
        #endif
    }

    /// The green-left, red-right subject: keyed, it is transparent on the left.
    private func makeSubject() async throws -> URL {
        try await makeMovie(left: green, right: red)
    }

    /// RGB at the centre of the left and right halves, at `seconds`.
    private func halves(of url: URL, at seconds: Double) async throws -> (left: [Int], right: [Int]) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        return halves(of: image)
    }

    private func halves(of image: CGImage) -> (left: [Int], right: [Int]) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func rgb(_ x: Int, _ y: Int) -> [Int] {
            let i = (y * width + x) * 4
            return [Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]
        }
        return (rgb(width / 4, height / 2), rgb(width * 3 / 4, height / 2))
    }

    private func isClose(_ rgb: [Int], to target: [Int]) -> Bool {
        zip(rgb, target).allSatisfy { abs($0 - $1) < 60 }
    }

    @Test func keyedClipShowsTheClipBeneath() async throws {
        let subject = try await makeSubject()
        defer { try? FileManager.default.removeItem(at: subject) }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("chroma_out_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }

        _ = try await Video {
            ImageClip(solid(red: 0, green: 0, blue: 1), duration: 1)
            VideoClip(url: subject)
                .filter(.chromaKey(color: .green, threshold: 0.35))
                .at(time: 0)
        }
        .preset(preset)
        .export(to: output)

        let (left, right) = try await halves(of: output, at: 0.5)
        #expect(isClose(left, to: [0, 0, 255]), "keyed half should show the blue clip beneath, got \(left)")
        #expect(isClose(right, to: [255, 0, 0]), "subject half should stay red, got \(right)")
    }

    @Test func keyedTrackOverAVideoClip() async throws {
        let subject = try await makeSubject()
        let background = try await makeMovie(left: blue, right: blue)
        defer {
            try? FileManager.default.removeItem(at: subject)
            try? FileManager.default.removeItem(at: background)
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("chroma_track_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }

        _ = try await Video {
            VideoClip(url: background)
            Track(at: 0) {
                VideoClip(url: subject).filter(.chromaKey(color: .green, threshold: 0.35))
            }
        }
        .preset(preset)
        .export(to: output)

        let (left, right) = try await halves(of: output, at: 0.5)
        #expect(isClose(left, to: [0, 0, 255]), "keyed half should show the video beneath, got \(left)")
        #expect(isClose(right, to: [255, 0, 0]), "subject half should stay red, got \(right)")
    }

    /// Thumbnails and preview share the export's composition, so they must agree.
    @Test func thumbnailShowsTheClipBeneath() async throws {
        let subject = try await makeSubject()
        defer { try? FileManager.default.removeItem(at: subject) }

        let video = Video {
            ImageClip(solid(red: 0, green: 0, blue: 1), duration: 1)
            VideoClip(url: subject)
                .filter(.chromaKey(color: .green, threshold: 0.35))
                .at(time: 0)
        }
        .preset(preset)

        let thumbnail = try await video.thumbnailGenerator().thumbnail(at: 0.5)
        #if canImport(UIKit)
        let image = try #require(thumbnail.cgImage)
        #else
        let image = try #require(thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #endif
        let (left, right) = halves(of: image)
        #expect(isClose(left, to: [0, 0, 255]), "keyed half should show the blue clip beneath, got \(left)")
        #expect(isClose(right, to: [255, 0, 0]), "subject half should stay red, got \(right)")
    }

    /// Alpha costs encode time and file size, so only filters that can make
    /// pixels transparent pay for it. Everything else keeps the H.264 path.
    @Test func onlyTransparentFiltersPreRenderWithAlpha() async throws {
        let subject = try await makeSubject()
        defer { try? FileManager.default.removeItem(at: subject) }

        let keyed = try await FilterProcessor.apply(filters: [.chromaKey(color: .green, threshold: 0.35)], to: subject)
        let graded = try await FilterProcessor.apply(filters: [.brightness(0.1)], to: subject)
        defer {
            try? FileManager.default.removeItem(at: keyed)
            try? FileManager.default.removeItem(at: graded)
        }

        #expect(try await hasAlpha(keyed))
        #expect(try await !hasAlpha(graded))
        #expect(graded.pathExtension == "mp4")
    }

    private func hasAlpha(_ url: URL) async throws -> Bool {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let value = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel)
        return (value as? Bool) ?? false
    }
}
