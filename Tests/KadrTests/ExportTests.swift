import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

struct ExportTests {

    private func testOutputURL(_ name: String = "test_output") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func loadTestImage() throws -> PlatformImage {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "sample", withExtension: "png") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.png"))
        }
        #if canImport(UIKit)
        guard let image = PlatformImage(contentsOfFile: url.path) else {
            throw KadrError.invalidURL(url)
        }
        return image
        #elseif canImport(AppKit)
        guard let image = PlatformImage(contentsOf: url) else {
            throw KadrError.invalidURL(url)
        }
        return image
        #endif
    }

    private func loadTestAudioURL() throws -> URL {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "sample", withExtension: "wav") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.wav"))
        }
        return url
    }

    /// Create a short test video file programmatically using ImageEncoder
    private func createTestVideo(duration: TimeInterval = 2.0) async throws -> URL {
        let image = try loadTestImage()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_video_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        return try await ImageEncoder.encode(
            image: image,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            preset: .square,
            audioURL: nil,
            to: outputURL
        )
    }

    // MARK: - ImageEncoder Tests

    @Test func singleImageExport() async throws {
        let image = try loadTestImage()
        let outputURL = testOutputURL("single_image")

        let result = try await Video {
            ImageClip(image, duration: 2.0)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        #expect(CMTimeGetSeconds(duration) > 1.5)
        #expect(CMTimeGetSeconds(duration) < 2.5)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func singleImageWithAudioExport() async throws {
        let image = try loadTestImage()
        let audioURL = try loadTestAudioURL()
        let outputURL = testOutputURL("image_audio")

        let result = try await Video {
            ImageClip(image, duration: 1.0)
        }
        .audio(url: audioURL)
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func singleImageWithPreset() async throws {
        let image = try loadTestImage()
        let outputURL = testOutputURL("image_preset")

        let result = try await Video {
            ImageClip(image, duration: 1.0)
        }
        .preset(.square)
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - Multi-clip Tests

    @Test func slideshowExport() async throws {
        let image = try loadTestImage()
        let outputURL = testOutputURL("slideshow")

        let result = try await Video {
            ImageClip(image, duration: 1.0)
            ImageClip(image, duration: 1.0)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        #expect(CMTimeGetSeconds(duration) > 1.5)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func mergeVideoClips() async throws {
        let video1URL = try await createTestVideo(duration: 1.0)
        let video2URL = try await createTestVideo(duration: 1.0)
        defer {
            try? FileManager.default.removeItem(at: video1URL)
            try? FileManager.default.removeItem(at: video2URL)
        }

        let outputURL = testOutputURL("merge")

        let result = try await Video {
            VideoClip(url: video1URL)
            VideoClip(url: video2URL)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        #expect(CMTimeGetSeconds(duration) > 1.5)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func trimVideoClip() async throws {
        let videoURL = try await createTestVideo(duration: 3.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = testOutputURL("trim")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0.5...2.0)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        #expect(CMTimeGetSeconds(duration) > 1.0)
        #expect(CMTimeGetSeconds(duration) < 2.0)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func mutedVideoClip() async throws {
        let videoURL = try await createTestVideo(duration: 1.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = testOutputURL("muted")

        let result = try await Video {
            VideoClip(url: videoURL).muted()
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func replaceAudio() async throws {
        let videoURL = try await createTestVideo(duration: 1.0)
        let audioURL = try loadTestAudioURL()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = testOutputURL("replace_audio")

        let result = try await Video {
            VideoClip(url: videoURL).muted()
        }
        .audio(url: audioURL)
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty)

        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - Error Tests

    @Test func emptyClipsThrows() async throws {
        let outputURL = testOutputURL("empty")
        let emptyClips: [any Clip] = []
        let video = Video(clips: emptyClips, audioTracks: [], preset: .auto)

        await #expect(throws: KadrError.self) {
            _ = try await video.export(to: outputURL)
        }
    }

    @Test func reverseVideoClip() async throws {
        let videoURL = try await createTestVideo(duration: 2.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = testOutputURL("reverse")

        let result = try await Video {
            VideoClip(url: videoURL).reversed()
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        #expect(CMTimeGetSeconds(duration) > 1.5)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func transitionThrowsNotYetImplemented() async throws {
        let videoURL = try await createTestVideo(duration: 1.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = testOutputURL("transition")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL)
                Transition.fade(duration: 0.5)
                VideoClip(url: videoURL)
            }
            .export(to: outputURL)
        }
    }
}
