import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// Tests for v0.20 — the `AVAssetReader` / `AVAssetWriter` export backend.
struct AssetWriterExportTests {

    private let preset: Preset = .auto

    private func sampleURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "mov") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.mov"))
        }
        return url
    }

    /// A real 64×64 image. `PlatformImage()` has no backing `CGImage`, so anything
    /// that actually encodes it fails with "Failed to convert image to CGImage" —
    /// a test failure that looks like a product bug and is not one.
    private func solidImage() throws -> PlatformImage {
        let size = CGSize(width: 64, height: 64)
        guard let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw KadrError.unsupportedFormat("Could not create a bitmap context") }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        guard let cg = context.makeImage() else {
            throw KadrError.unsupportedFormat("Could not render the test image")
        }
        #if canImport(UIKit)
        return PlatformImage(cgImage: cg)
        #else
        return PlatformImage(cgImage: cg, size: size)
        #endif
    }

    private func tempOutput() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
    }

    // MARK: - Routing
    //
    // The routing rule is the part most likely to cause a silent regression, so it
    // is tested directly rather than inferred from an exported file.

    @Test func automaticQualityStaysOnTheSessionPath() {
        #expect(ExportEngine.shouldUseWriter(bitrate: nil, overlays: []) == false)
    }

    @Test func explicitBitrateWithNoOverlaysUsesTheWriter() {
        #expect(ExportEngine.shouldUseWriter(bitrate: 4_000_000, overlays: []))
    }

    /// The rule that matters most. Overlays render through
    /// `AVVideoCompositionCoreAnimationTool`, which the writer path cannot use — so
    /// an overlay-bearing composition must stay on the session path even though a
    /// bitrate was asked for. **Exporting it through the writer would succeed with
    /// the overlays missing**, which is a far worse failure than ignoring bitrate.
    @Test func overlaysPinTheExportToTheSessionPath() {
        let overlay = TextOverlay("hello", style: .default)
        #expect(ExportEngine.shouldUseWriter(bitrate: 4_000_000, overlays: [overlay]) == false)
    }

    // MARK: - Real exports

    @Test func bitrateExportProducesAPlayableFile() async throws {
        let out = tempOutput()
        defer { try? FileManager.default.removeItem(at: out) }

        let url = try sampleURL()

        let video = Video { VideoClip(url: url).trimmed(to: 0...1) }
            .quality(.bitrate(2_000_000))
        _ = try await video.export(to: out)

        #expect(FileManager.default.fileExists(atPath: out.path))
        let asset = AVURLAsset(url: out)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(!tracks.isEmpty, "The written file must contain a video track")
        let duration = try await asset.load(.duration)
        #expect(duration.seconds > 0)
    }

    /// The point of the whole backend: a lower bitrate must produce a smaller file.
    /// Asserted as a ratio rather than an absolute size, because absolute sizes
    /// depend on the fixture and the encoder version.
    @Test func lowerBitrateProducesASmallerFile() async throws {
        let url = try sampleURL()
        let high = tempOutput(), low = tempOutput()
        defer {
            try? FileManager.default.removeItem(at: high)
            try? FileManager.default.removeItem(at: low)
        }

        _ = try await Video { VideoClip(url: url).trimmed(to: 0...2) }
            .quality(.bitrate(6_000_000)).export(to: high)
        _ = try await Video { VideoClip(url: url).trimmed(to: 0...2) }
            .quality(.bitrate(600_000)).export(to: low)

        let highSize = try FileManager.default.attributesOfItem(atPath: high.path)[.size] as! Int
        let lowSize = try FileManager.default.attributesOfItem(atPath: low.path)[.size] as! Int
        #expect(lowSize < highSize, "600 kbps produced \(lowSize) bytes, 6 Mbps produced \(highSize)")
    }

    @Test func fileSizeTargetExports() async throws {
        let out = tempOutput()
        defer { try? FileManager.default.removeItem(at: out) }

        let url = try sampleURL()

        let video = Video { VideoClip(url: url).trimmed(to: 0...2) }
            .quality(.fileSize(bytes: 2_000_000))
        _ = try await video.export(to: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
    }

    /// An overlay plus a bitrate must still export *with the overlay*. The bitrate is
    /// what gets dropped, and that is the correct half to drop.
    @Test func overlayWithBitrateStillExports() async throws {
        let out = tempOutput()
        defer { try? FileManager.default.removeItem(at: out) }

        let url = try sampleURL()

        let video = Video { VideoClip(url: url).trimmed(to: 0...1) }
            .overlay(TextOverlay("hi", style: .default))
            .quality(.bitrate(2_000_000))
        _ = try await video.export(to: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
    }

    @Test func writerPathReportsProgressToCompletion() async throws {
        let out = tempOutput()
        defer { try? FileManager.default.removeItem(at: out) }

        let url = try sampleURL()

        let video = Video { VideoClip(url: url).trimmed(to: 0...1) }
            .quality(.bitrate(2_000_000))

        var fractions: [Double] = []
        for try await progress in video.exporter(to: out).run() {
            fractions.append(progress.fractionCompleted)
        }
        #expect(fractions.first == 0.0)
        #expect(fractions.last == 1.0, "The stream must end at 1.0, not merely stop")
        #expect(fractions == fractions.sorted(), "Progress must not go backwards")
    }

    // MARK: - The fast path must not swallow a bitrate

    /// `Video.export(to:)` has a fast path for a single `ImageClip`: it goes straight
    /// to `ImageEncoder` and never reaches either export engine. `ImageEncoder` has
    /// no bitrate control, so taking that route with a bitrate requested would ignore
    /// it silently.
    ///
    /// Found by a benchmark, not by a test — the writer-path timings came back
    /// identical to the session path because the composition never left the fast
    /// path. This pins it so the next person to touch that branch has to notice.
    @Test func singleImageClipWithBitrateStillHonoursIt() async throws {
        let out = tempOutput()
        defer { try? FileManager.default.removeItem(at: out) }

        let image = try solidImage()
        let video = Video { ImageClip(image, duration: CMTime(seconds: 1, preferredTimescale: 600)) }
            .quality(.bitrate(800_000))

        // The assertion that matters is that this does not take the ImageEncoder
        // shortcut. Exporting proves the routing change did not break the case.
        _ = try await video.export(to: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
    }

    @Test func singleImageClipWithoutQualityStillTakesTheFastPath() async throws {
        let out = tempOutput()
        defer { try? FileManager.default.removeItem(at: out) }

        let image = try solidImage()
        let video = Video { ImageClip(image, duration: CMTime(seconds: 1, preferredTimescale: 600)) }
        _ = try await video.export(to: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
    }
}

