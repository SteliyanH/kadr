import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

struct TransitionsTests {

    private func testOutputURL(_ name: String = "transition_test") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func loadTestVideoURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "mov") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.mov"))
        }
        return url
    }

    private func loadTestImage() throws -> PlatformImage {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "png") else {
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

    // MARK: - Successful fade exports

    @Test func fadeBetweenTwoVideoClips() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("fade_videos")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
            Transition.fade(duration: 0.5)
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        // Total = 3 + 3 - 0.5 overlap = 5.5
        #expect(seconds > 5.0)
        #expect(seconds < 6.0)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func fadeBetweenImageClips() async throws {
        let image = try loadTestImage()
        let outputURL = testOutputURL("fade_images")

        let result = try await Video {
            ImageClip(image, duration: 2.0)
            Transition.fade(duration: 0.5)
            ImageClip(image, duration: 2.0)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        // Total = 2 + 2 - 0.5 overlap = 3.5
        #expect(seconds > 3.0)
        #expect(seconds < 4.0)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func fadeAcrossThreeClips() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("fade_three")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...2)
            Transition.fade(duration: 0.4)
            VideoClip(url: videoURL).trimmed(to: 0...2)
            Transition.fade(duration: 0.4)
            VideoClip(url: videoURL).trimmed(to: 0...2)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        // Total = 2 + 2 + 2 - 0.4 - 0.4 = 5.2
        #expect(seconds > 4.7)
        #expect(seconds < 5.7)

        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - Validation

    @Test func transitionAtStartThrows() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("trans_start")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                Transition.fade(duration: 0.5)
                VideoClip(url: videoURL).trimmed(to: 0...3)
            }
            .export(to: outputURL)
        }
    }

    @Test func transitionAtEndThrows() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("trans_end")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL).trimmed(to: 0...3)
                Transition.fade(duration: 0.5)
            }
            .export(to: outputURL)
        }
    }

    @Test func adjacentTransitionsThrow() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("adj_trans")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL).trimmed(to: 0...3)
                Transition.fade(duration: 0.3)
                Transition.fade(duration: 0.3)
                VideoClip(url: videoURL).trimmed(to: 0...3)
            }
            .export(to: outputURL)
        }
    }

    @Test func transitionLongerThanClipThrows() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("trans_too_long")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL).trimmed(to: 0...1)
                Transition.fade(duration: 2.0)
                VideoClip(url: videoURL).trimmed(to: 0...3)
            }
            .export(to: outputURL)
        }
    }
}
