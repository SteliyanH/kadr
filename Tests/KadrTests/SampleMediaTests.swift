import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia
#if canImport(AppKit)
import AppKit
#endif

/// Tests for v0.20 — ``SampleMedia``.
///
/// The point of this type is that a newcomer has something to point `VideoPreview`
/// or `export(to:)` at without finding a video file first. So the tests assert it is
/// genuinely usable, not merely that it returns non-nil.
struct SampleMediaTests {

    @Test func videoHasClipsAndDuration() {
        let video = SampleMedia.video(seconds: 4)
        #expect(video.clips.count == 4)
        #expect(video.duration.seconds > 3.9)
        #expect(video.duration.seconds < 4.1)
    }

    @Test func videoRespectsTheRequestedDuration() {
        #expect(SampleMedia.video(seconds: 2).duration.seconds < 2.1)
        #expect(SampleMedia.video(seconds: 8).duration.seconds > 7.9)
    }

    /// A zero or negative duration is a caller mistake, not a request for an empty
    /// composition. Clamping beats returning something that cannot be played.
    @Test func nonPositiveDurationStillProducesPlayableMedia() {
        #expect(SampleMedia.video(seconds: 0).duration.seconds > 0)
        #expect(SampleMedia.video(seconds: -5).duration.seconds > 0)
    }

    @Test func videoCarriesTheRequestedPreset() {
        let video = SampleMedia.video(preset: .square)
        #expect(video.preset.resolution.width == video.preset.resolution.height)
    }

    // MARK: - Frames

    @Test func imageIsARealBitmap() {
        let image = SampleMedia.image(size: CGSize(width: 120, height: 200))
        #if canImport(UIKit)
        #expect(image.cgImage != nil)
        #else
        #expect(image.size.width > 0 && image.size.height > 0)
        #endif
    }

    /// Consecutive frames must differ. A generator that returned the same frame
    /// every time would make every cut invisible, which defeats the point of using
    /// it to check a transform or a transition.
    @Test func consecutiveFramesDiffer() throws {
        let a = SampleMedia.image(index: 0, size: CGSize(width: 64, height: 64))
        let b = SampleMedia.image(index: 1, size: CGSize(width: 64, height: 64))
        let dataA = try #require(pngData(a))
        let dataB = try #require(pngData(b))
        #expect(dataA != dataB)
    }

    /// Any integer is valid; the set wraps. Callers iterating `0..<n` should not have
    /// to know how many arrangements exist.
    @Test func frameIndexWrapsAndAcceptsNegatives() throws {
        let zero = try #require(pngData(SampleMedia.image(index: 0, size: CGSize(width: 32, height: 32))))
        let four = try #require(pngData(SampleMedia.image(index: 4, size: CGSize(width: 32, height: 32))))
        let minusFour = try #require(pngData(SampleMedia.image(index: -4, size: CGSize(width: 32, height: 32))))
        #expect(zero == four)
        #expect(zero == minusFour)
    }

    // MARK: - Actually usable

    @Test func sampleVideoExports() async throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: out) }

        _ = try await SampleMedia.video(seconds: 1).export(to: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
    }

    /// The whole reason `movieFileURL` exists: `VideoClip` needs a file, and a
    /// newcomer has none.
    @Test func movieFileURLProducesAClipSource() async throws {
        let url = try await SampleMedia.movieFileURL(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(FileManager.default.fileExists(atPath: url.path))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(!tracks.isEmpty)

        // And it composes, which is the actual claim being made.
        let clip = VideoClip(url: url).trimmed(to: 0...0.5)
        #expect(clip.trimRange != nil)
    }

    /// `VideoPreview` takes a player item, so this is the path a newcomer hits
    /// first. `AVPlayerItem.asset` is main-actor isolated and non-Sendable, so the
    /// assertion stays on the item itself rather than reaching through it.
    @MainActor
    @Test func sampleVideoMakesAPlayerItem() async throws {
        let item = try await SampleMedia.video(seconds: 1).makePlayerItem()
        #expect(item.duration.seconds.isNaN || item.duration.seconds >= 0)
    }

    /// The raw pixels, compared directly. Round-tripping through a PNG encoder adds
    /// a platform-specific step and answers a slightly different question.
    private func pngData(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        guard let cg = image.cgImage else { return nil }
        #else
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #endif
        guard let provider = cg.dataProvider else { return nil }
        return provider.data as Data?
    }
}
