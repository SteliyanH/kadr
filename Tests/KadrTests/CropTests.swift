import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia
import CoreGraphics

struct CropTests {

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

    // MARK: - DSL

    @Test func defaultCropIsNil() {
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        #expect(video.crop == nil)
    }

    @Test func cropStoresRegion() {
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .crop(at: .center, size: .normalized(width: 0.8, height: 0.8))
        #expect(video.crop != nil)
        #expect(video.crop?.position == .center)
        #expect(video.crop?.anchor == .center)
    }

    @Test func cropSecondCallReplacesFirst() {
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
        .crop(at: .topLeft, size: .normalized(width: 0.3, height: 0.3), anchor: .topLeft)
        #expect(video.crop?.position == .topLeft)
        #expect(video.crop?.anchor == .topLeft)
    }

    @Test func cropPreservesOverlays() throws {
        let img = try loadTestImage()
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .overlay(ImageOverlay(img).id("a"))
        .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
        #expect(video.overlays.count == 1)
        #expect(video.crop != nil)
    }

    // MARK: - CropRegion math

    @Test func centerCropResolvesCorrectly() {
        let region = CropRegion(
            position: .center,
            size: .normalized(width: 0.8, height: 0.8),
            anchor: .center
        )
        let resolved = region.resolved(in: CGSize(width: 1080, height: 1920))
        // Centered 80% region: width 864, height 1536, origin offset by (108, 192)
        #expect(resolved.size.width == 864)
        #expect(resolved.size.height == 1536)
        #expect(resolved.origin.x == 108)
        #expect(resolved.origin.y == 192)
    }

    @Test func topLeftCropAnchored() {
        let region = CropRegion(
            position: .topLeft,
            size: .normalized(width: 0.5, height: 0.5),
            anchor: .topLeft
        )
        let resolved = region.resolved(in: CGSize(width: 1080, height: 1920))
        #expect(resolved.origin.x == 0)
        #expect(resolved.origin.y == 0)
        #expect(resolved.size.width == 540)
        #expect(resolved.size.height == 960)
    }

    @Test func pixelCropPassesThrough() {
        let region = CropRegion(
            position: .pixels(x: 100, y: 200),
            size: .pixels(width: 800, height: 1000),
            anchor: .topLeft
        )
        let resolved = region.resolved(in: CGSize(width: 1080, height: 1920))
        #expect(resolved == CGRect(x: 100, y: 200, width: 800, height: 1000))
    }

    // MARK: - Export

    // MARK: - Engine renderSize verification
    //
    // Note: AVAssetExportPresetHighestQuality clamps output dimensions to the source
    // asset's natural resolution (the test sample is 540p). That means we can't assert
    // on the OUTPUT mp4's pixel size to verify cropping took effect. Instead we verify
    // the CompositionBuilder/ExportEngine wire the right `renderSize` into the
    // videoComposition — that's what controls the crop. End-to-end pixel-precise
    // dimensions land properly when the source is large enough or when a different
    // export preset is used (a v0.5 concern alongside custom compositors).

    @Test func builderSetsCroppedRenderSizeOnTransitionPath() async throws {
        let videoURL = try loadTestVideoURL()
        let cropRect = CGRect(x: 192, y: 108, width: 864, height: 1536)  // arbitrary

        let result = try await CompositionBuilder.build(
            from: [
                VideoClip(url: videoURL).trimmed(to: 0...3),
                Transition.dissolve(duration: 0.4),
                VideoClip(url: videoURL).trimmed(to: 0...3),
            ],
            audioTracks: [],
            preset: .reelsAndShorts,  // 1080×1920
            cropRect: cropRect
        )
        let renderSize = result.videoComposition?.renderSize
        #expect(renderSize?.width == 864)
        #expect(renderSize?.height == 1536)
    }

    // MARK: - End-to-end smoke tests (file is produced; dimensions vary per export preset)

    @Test func exportWithCenterCropSucceeds() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("crop_center_smoke")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .preset(.cinema)
        .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithPixelCropSucceeds() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("crop_pixels_smoke")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .preset(.cinema)
        .crop(
            at: .pixels(x: 100, y: 100),
            size: .pixels(width: 800, height: 600),
            anchor: .topLeft
        )
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithCropAndTransitionSucceeds() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("crop_transition_smoke")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
            Transition.dissolve(duration: 0.4)
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .preset(.cinema)
        .crop(at: .center, size: .normalized(width: 0.7, height: 0.7))
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithCropAndOverlaySucceeds() async throws {
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let outputURL = testOutputURL("crop_overlay_smoke")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .preset(.cinema)
        .crop(at: .center, size: .normalized(width: 0.6, height: 0.6))
        .overlay(
            ImageOverlay(img)
                .position(.bottomRight)
                .anchor(.bottomRight)
                .size(.normalized(width: 0.2, height: 0.2))
        )
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }
}
