import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreGraphics
import CoreMedia

/// Rotated and mirrored sources must come out the way they are meant to be seen.
///
/// Cameras store a portrait recording as landscape pixels plus a `preferredTransform`
/// that turns it upright; the front camera may add a mirror. A layer instruction's
/// transform replaces that `preferredTransform`, so the engine has to apply it, and
/// before 1.1.2 it didn't: every portrait iPhone clip exported sideways.
///
/// Each fixture stores a 128×64 frame in four coloured quadrants and tags it with a
/// transform. The ground truth is the same file decoded with
/// `appliesPreferredTrackTransform`, which is how Photos and QuickTime show it. A test
/// passes when the export shows the four quadrants in the same places.
struct VideoOrientationTests {

    private enum Quadrant: Equatable { case red, green, blue, yellow }

    /// Four quadrant colours, read top-left, top-right, bottom-left, bottom-right.
    private typealias Layout = [Quadrant]

    /// Portrait output for portrait-displayed fixtures, so filling the frame crops nothing.
    private let portrait: Preset = .custom(width: 64, height: 128, frameRate: 30, codec: .h264)
    private let landscape: Preset = .custom(width: 128, height: 64, frameRate: 30, codec: .h264)

    // MARK: - Fixtures

    /// A `seconds`-long clip of 128×64 stored pixels in four colours, tagged `transform`.
    private func makeClip(transform: CGAffineTransform, seconds: Double = 1) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("orientation_\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 64,
        ])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        guard writer.startWriting(), let pool = adaptor.pixelBufferPool else {
            throw KadrError.unsupportedFormat("Could not start the fixture writer")
        }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(seconds * 30)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { throw KadrError.unsupportedFormat("No pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<64 {
                for x in 0..<128 {
                    // BGRA. Stored rows run top to bottom.
                    let (r, g, b): (UInt8, UInt8, UInt8)
                    switch (x < 64, y < 32) {
                    case (true, true): (r, g, b) = (255, 0, 0)      // top-left red
                    case (false, true): (r, g, b) = (0, 255, 0)     // top-right green
                    case (true, false): (r, g, b) = (0, 0, 255)     // bottom-left blue
                    case (false, false): (r, g, b) = (255, 255, 0)  // bottom-right yellow
                    }
                    let p = base + y * bytesPerRow + x * 4
                    p[0] = b; p[1] = g; p[2] = r; p[3] = 255
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

    // A quarter turn as an iPhone writes it: rotation with the translation baked in.
    private let quarterTurn = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 64, ty: 0)
    // The same quarter turn about the origin, with no translation (some writers do this).
    private let quarterTurnAboutOrigin = CGAffineTransform(rotationAngle: .pi / 2)
    private let threeQuarterTurn = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 128)
    private let halfTurn = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 128, ty: 64)
    // Front camera: a quarter turn plus a horizontal mirror.
    private let mirroredQuarterTurn = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)

    // MARK: - Reading frames

    private func layout(of image: CGImage) throws -> Layout {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw KadrError.unsupportedFormat("Could not create a bitmap context") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Bitmap row 0 is the top of the drawn image.
        func quadrant(_ x: Int, _ y: Int) -> Quadrant {
            let i = (y * w + x) * 4
            let (r, g, b) = (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
            let candidates: [(Quadrant, (Int, Int, Int))] = [
                (.red, (255, 0, 0)), (.green, (0, 255, 0)), (.blue, (0, 0, 255)), (.yellow, (255, 255, 0)),
            ]
            return candidates.min { lhs, rhs in
                func distance(_ c: (Int, Int, Int)) -> Int {
                    (r - c.0) * (r - c.0) + (g - c.1) * (g - c.1) + (b - c.2) * (b - c.2)
                }
                return distance(lhs.1) < distance(rhs.1)
            }!.0
        }
        return [quadrant(w / 4, h / 4), quadrant(3 * w / 4, h / 4),
                quadrant(w / 4, 3 * h / 4), quadrant(3 * w / 4, 3 * h / 4)]
    }

    private func layout(of url: URL, at seconds: Double) async throws -> Layout {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        return try layout(of: image)
    }

    /// How the fixture is meant to look: decoded with its own transform applied.
    private func expected(_ url: URL) async throws -> Layout {
        try await layout(of: url, at: 0.5)
    }

    private func export(_ video: Video) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("orientation_out_\(UUID().uuidString).mp4")
        return try await video.export(to: url)
    }

    // MARK: - Single clip, simple path

    @Test(arguments: ["quarter", "quarterAboutOrigin", "threeQuarter", "mirrored"])
    func portraitSourceExportsUpright(_ name: String) async throws {
        let transform: CGAffineTransform = switch name {
        case "quarter": quarterTurn
        case "quarterAboutOrigin": quarterTurnAboutOrigin
        case "threeQuarter": threeQuarterTurn
        default: mirroredQuarterTurn
        }
        let clip = try await makeClip(transform: transform)
        let want = try await expected(clip)

        let out = try await export(Video { VideoClip(url: clip) }.preset(portrait))
        #expect(try await layout(of: out, at: 0.5) == want)
    }

    @Test func upsideDownSourceExportsUpright() async throws {
        let clip = try await makeClip(transform: halfTurn)
        let want = try await expected(clip)
        let out = try await export(Video { VideoClip(url: clip) }.preset(landscape))
        #expect(try await layout(of: out, at: 0.5) == want)
    }

    @Test func uprightSourceIsUnchanged() async throws {
        let clip = try await makeClip(transform: .identity)
        let out = try await export(Video { VideoClip(url: clip) }.preset(landscape))
        #expect(try await layout(of: out, at: 0.5) == [.red, .green, .blue, .yellow])
    }

    /// Two clips with different orientations share one composition track; each must
    /// get its own.
    @Test func mixedOrientationsOnOneTrack() async throws {
        let a = try await makeClip(transform: quarterTurn)
        let b = try await makeClip(transform: threeQuarterTurn)
        let (wantA, wantB) = (try await expected(a), try await expected(b))
        #expect(wantA != wantB)

        let out = try await export(Video {
            VideoClip(url: a)
            VideoClip(url: b)
        }.preset(portrait))
        #expect(try await layout(of: out, at: 0.5) == wantA)
        #expect(try await layout(of: out, at: 1.5) == wantB)
    }

    // MARK: - Transitions path

    @Test func dissolveBetweenRotatedClips() async throws {
        let a = try await makeClip(transform: quarterTurn)
        let b = try await makeClip(transform: threeQuarterTurn)
        let (wantA, wantB) = (try await expected(a), try await expected(b))

        // A plays 0–1 s, B 0.5–1.5 s; the dissolve is 0.5–1 s.
        let out = try await export(Video {
            VideoClip(url: a).trimmed(to: 0...1)
            Transition.dissolve(duration: 0.5)
            VideoClip(url: b).trimmed(to: 0...1)
        }.preset(portrait))
        #expect(try await layout(of: out, at: 0.25) == wantA)
        #expect(try await layout(of: out, at: 1.3) == wantB)
    }

    @Test func slideBetweenRotatedClips() async throws {
        let a = try await makeClip(transform: quarterTurn)
        let b = try await makeClip(transform: threeQuarterTurn)
        let (wantA, wantB) = (try await expected(a), try await expected(b))

        let out = try await export(Video {
            VideoClip(url: a).trimmed(to: 0...1)
            Transition.slide(direction: .fromLeft, duration: 0.5)
            VideoClip(url: b).trimmed(to: 0...1)
        }.preset(portrait))
        #expect(try await layout(of: out, at: 0.25) == wantA)
        #expect(try await layout(of: out, at: 1.3) == wantB)
    }

    // MARK: - Multi-track path

    /// A clip transform routes through the per-clip keyframe path, whose transforms
    /// replace the base layout; the orientation has to survive inside them.
    @Test func clipTransformKeepsOrientation() async throws {
        let clip = try await makeClip(transform: quarterTurn)
        let want = try await expected(clip)
        let out = try await export(Video {
            VideoClip(url: clip).transform(Transform(scale: 1.0))
        }.preset(portrait))
        #expect(try await layout(of: out, at: 0.5) == want)
    }

    /// After an animated clip, a plain clip on the same track goes back to its own base
    /// layout rather than keeping the previous clip's transform.
    @Test func plainClipAfterTransformedClip() async throws {
        let a = try await makeClip(transform: quarterTurn)
        let b = try await makeClip(transform: threeQuarterTurn)
        let wantB = try await expected(b)
        let out = try await export(Video {
            VideoClip(url: a).transform(Transform(scale: 1.0))
            VideoClip(url: b)
        }.preset(portrait))
        #expect(try await layout(of: out, at: 1.5) == wantB)
    }

    /// Same rule with upright sources and a transform that visibly moves the clip: the
    /// plain clip after it must not inherit it.
    @Test func plainClipDoesNotInheritPreviousTransform() async throws {
        let a = try await makeClip(transform: .identity)
        let b = try await makeClip(transform: .identity)
        let out = try await export(Video {
            VideoClip(url: a).trimmed(to: 0...1).transform(Transform(center: .normalized(x: 0, y: 0)))
            VideoClip(url: b).trimmed(to: 0...1)
        }.preset(landscape))
        #expect(try await layout(of: out, at: 1.5) == [.red, .green, .blue, .yellow])
    }

    @Test func trackOverChainKeepsOrientation() async throws {
        let chain = try await makeClip(transform: quarterTurn)
        let top = try await makeClip(transform: threeQuarterTurn)
        let wantTop = try await expected(top)
        let out = try await export(Video {
            VideoClip(url: chain)
            Track(at: .zero) { VideoClip(url: top) }
        }.preset(portrait))
        #expect(try await layout(of: out, at: 0.5) == wantTop)
    }

    // MARK: - Preview, pre-render passes

    @Test func previewMatchesExport() async throws {
        let clip = try await makeClip(transform: quarterTurn)
        let want = try await expected(clip)
        let thumbnail = try await Video { VideoClip(url: clip) }.preset(portrait).thumbnail(at: 0.5)
        #if canImport(UIKit)
        let cg = try #require(thumbnail.cgImage)
        #else
        let cg = try #require(thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #endif
        #expect(try layout(of: cg) == want)
    }

    @Test func filteredRotatedClipStaysUpright() async throws {
        let clip = try await makeClip(transform: quarterTurn)
        let want = try await expected(clip)
        let out = try await export(Video {
            VideoClip(url: clip).filter(.saturation(1.0))
        }.preset(portrait))
        #expect(try await layout(of: out, at: 0.5) == want)
    }

    @Test func reversedRotatedClipStaysUpright() async throws {
        let clip = try await makeClip(transform: quarterTurn)
        let want = try await expected(clip)
        let out = try await export(Video {
            VideoClip(url: clip).reversed()
        }.preset(portrait))
        #expect(try await layout(of: out, at: 0.5) == want)
    }
}
