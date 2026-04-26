import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

struct SpeedTests {

    private func testOutputURL(_ name: String) -> URL {
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

    // MARK: - Duration math (synchronous, via Clip.duration)

    @Test func speedHalvesDurationAtTwoX() {
        let videoURL = URL(fileURLWithPath: "/dev/null")
        let clip = VideoClip(url: videoURL).trimmed(to: 0...4).speed(2.0)
        #expect(abs(CMTimeGetSeconds(clip.duration) - 2.0) < 0.01)
    }

    @Test func speedDoublesDurationAtHalfX() {
        let videoURL = URL(fileURLWithPath: "/dev/null")
        let clip = VideoClip(url: videoURL).trimmed(to: 0...4).speed(0.5)
        #expect(abs(CMTimeGetSeconds(clip.duration) - 8.0) < 0.01)
    }

    @Test func speedDefaultIsOne() {
        let videoURL = URL(fileURLWithPath: "/dev/null")
        let clip = VideoClip(url: videoURL).trimmed(to: 0...4)
        #expect(abs(CMTimeGetSeconds(clip.duration) - 4.0) < 0.01)
    }

    @Test func speedComposesWithOtherModifiers() {
        let videoURL = URL(fileURLWithPath: "/dev/null")
        let clip = VideoClip(url: videoURL).trimmed(to: 0...4).muted().speed(2.0)
        #expect(clip.isMuted)
        #expect(abs(CMTimeGetSeconds(clip.duration) - 2.0) < 0.01)
    }

    // MARK: - Export

    @Test func exportAtTwoX() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("speed_2x")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...4).speed(2.0)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        // 4s source / 2.0 = 2s
        #expect(seconds > 1.5)
        #expect(seconds < 2.5)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportAtHalfX() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("speed_half")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...2).speed(0.5)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        // 2s source / 0.5 = 4s
        #expect(seconds > 3.5)
        #expect(seconds < 4.5)

        try? FileManager.default.removeItem(at: result)
    }

    @Test func speedWithDissolve() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("speed_dissolve")

        // First clip: 4s @ 2x = 2s. Second clip: 4s @ 1x = 4s. Dissolve 0.4 overlap.
        // Total = 2 + 4 - 0.4 = 5.6
        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...4).speed(2.0)
            Transition.dissolve(duration: 0.4)
            VideoClip(url: videoURL).trimmed(to: 0...4)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))

        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        #expect(seconds > 5.0)
        #expect(seconds < 6.1)

        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - Validation

    @Test func speedTooSlowThrows() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("speed_too_slow")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL).trimmed(to: 0...3).speed(0.1)
            }
            .export(to: outputURL)
        }
    }

    @Test func speedTooFastThrows() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("speed_too_fast")

        await #expect(throws: KadrError.self) {
            _ = try await Video {
                VideoClip(url: videoURL).trimmed(to: 0...3).speed(8.0)
            }
            .export(to: outputURL)
        }
    }

    @Test func speedAtBoundsExports() async throws {
        let videoURL = try loadTestVideoURL()

        // 0.25 lower bound
        let slowURL = testOutputURL("speed_quarter")
        _ = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...1).speed(0.25)
        }.export(to: slowURL)
        #expect(FileManager.default.fileExists(atPath: slowURL.path))
        try? FileManager.default.removeItem(at: slowURL)

        // 4.0 upper bound
        let fastURL = testOutputURL("speed_4x")
        _ = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...4).speed(4.0)
        }.export(to: fastURL)
        #expect(FileManager.default.fileExists(atPath: fastURL.path))
        try? FileManager.default.removeItem(at: fastURL)
    }
}
