import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia
import CoreImage

struct FilterTests {

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

    // MARK: - DSL

    @Test func defaultFiltersIsEmpty() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov"))
        #expect(clip.filters.isEmpty)
    }

    @Test func filterModifierAppends() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov"))
            .filter(.brightness(0.1))
            .filter(.contrast(1.2))
        #expect(clip.filters.count == 2)
        #expect(clip.filters[0] == .brightness(0.1))
        #expect(clip.filters[1] == .contrast(1.2))
    }

    @Test func filterVariadicAccumulates() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov"))
            .filter(.brightness(0.1), .contrast(1.2), .saturation(1.3))
        #expect(clip.filters.count == 3)
    }

    @Test func filterChainPlusVariadic() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov"))
            .filter(.brightness(0.1))
            .filter(.contrast(1.2), .saturation(1.3))
        #expect(clip.filters.count == 3)
        #expect(clip.filters[0] == .brightness(0.1))
        #expect(clip.filters[1] == .contrast(1.2))
        #expect(clip.filters[2] == .saturation(1.3))
    }

    @Test func filtersThreadThroughOtherModifiers() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov"))
            .filter(.sepia(intensity: 0.8))
            .trimmed(to: 0...3)
            .speed(2.0)
            .muted()
        #expect(clip.filters.count == 1)
        #expect(clip.filters[0] == .sepia(intensity: 0.8))
        #expect(clip.isMuted)
        #expect(clip.speedRate == 2.0)
    }

    // MARK: - Filter equality

    @Test func filterEquatable() {
        #expect(Filter.brightness(0.1) == .brightness(0.1))
        #expect(Filter.brightness(0.1) != .brightness(0.2))
        #expect(Filter.mono == .mono)
        #expect(Filter.brightness(0.1) != .contrast(0.1))
        #expect(Filter.sepia(intensity: 1.0) == .sepia())  // default arg matches explicit 1.0
    }

    // MARK: - CIFilter mapping

    @Test func filterAppliesToCIImage() {
        let testImage = CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        // Each filter case should produce some output (not crash, not return identity)
        for filter in [Filter.brightness(0.1), .contrast(1.2), .saturation(1.5), .exposure(0.5), .sepia(intensity: 0.8), .mono] {
            let output = filter.apply(to: testImage)
            #expect(output.extent.width == 100)
        }
    }

    // MARK: - Export

    @Test func exportWithSingleFilter() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("filter_brightness")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3).filter(.brightness(0.1))
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithChainedFilters() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("filter_chain")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
                .filter(.brightness(0.05), .contrast(1.15), .saturation(1.2))
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithMonoFilter() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("filter_mono")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3).filter(.mono)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithSepiaFilter() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("filter_sepia")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3).filter(.sepia(intensity: 0.8))
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func filterWithTransition() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("filter_transition")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3).filter(.contrast(1.3))
            Transition.dissolve(duration: 0.4)
            VideoClip(url: videoURL).trimmed(to: 0...3).filter(.mono)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        // Two clips of ~3s, dissolve overlap 0.4s → ~5.6s
        let asset = AVURLAsset(url: result)
        let dur = CMTimeGetSeconds(try await asset.load(.duration))
        #expect(dur > 5.0)
        #expect(dur < 6.0)
        try? FileManager.default.removeItem(at: result)
    }

    @Test func filterWithSpeed() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("filter_speed")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...4).speed(2.0).filter(.brightness(0.1))
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        // 4s at 2x = 2s
        let asset = AVURLAsset(url: result)
        let dur = CMTimeGetSeconds(try await asset.load(.duration))
        #expect(dur > 1.5)
        #expect(dur < 2.5)
        try? FileManager.default.removeItem(at: result)
    }
}
