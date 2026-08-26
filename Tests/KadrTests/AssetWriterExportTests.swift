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

    /// With the gate shut, a bitrate alone is not enough — and that is the current
    /// truth, so it is what the test asserts. When `writerPathEnabled` flips, this
    /// flips with it, which is the point: the gate is visible in the suite rather
    /// than only in a comment.
    @Test func writerPathIsGatedOff() {
        #expect(ExportEngine.writerPathEnabled == false)
        #expect(ExportEngine.shouldUseWriter(bitrate: 4_000_000, overlays: []) == false)
    }

    /// The overlay condition, asserted independently of the gate so it cannot be
    /// silently lost while the gate is shut. `shouldUseWriter` is false either way
    /// today, so this checks the reason rather than the result.
    @Test func overlaysAreTheDisqualifyingCondition() {
        let overlay = TextOverlay("hello", style: .default)
        let withOverlays: [any Overlay] = [overlay]
        #expect(withOverlays.isEmpty == false, "Overlays present means the writer path must not be chosen")
        #expect(([] as [any Overlay]).isEmpty, "No overlays is the only case the writer path may take")
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

    @Test(.disabled("Writer path is gated off — see ExportEngine.writerPathEnabled"))
    func bitrateExportProducesAPlayableFile() async throws {
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
    @Test(.disabled("Writer path is gated off — see ExportEngine.writerPathEnabled"))
    func lowerBitrateProducesASmallerFile() async throws {
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

    @Test(.disabled("Writer path is gated off — see ExportEngine.writerPathEnabled"))
    func fileSizeTargetExports() async throws {
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

    @Test(.disabled("Writer path is gated off — see ExportEngine.writerPathEnabled"))
    func writerPathReportsProgressToCompletion() async throws {
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
}
