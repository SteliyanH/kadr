import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

struct OverlayTests {

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

    @Test func defaultOverlayValues() throws {
        let img = try loadTestImage()
        let overlay = ImageOverlay(img)
        #expect(overlay.opacity == 1.0)
        #expect(overlay.layerID == nil)
        #expect(overlay.size == nil)
        #expect(overlay.anchor == .center)
    }

    @Test func overlayModifierChain() throws {
        let img = try loadTestImage()
        let overlay = ImageOverlay(img)
            .position(.topRight)
            .size(.normalized(width: 0.2, height: 0.05))
            .anchor(.topRight)
            .opacity(0.8)
            .id("watermark")
        #expect(overlay.position == .topRight)
        #expect(overlay.size == .normalized(width: 0.2, height: 0.05))
        #expect(overlay.anchor == .topRight)
        #expect(overlay.opacity == 0.8)
        #expect(overlay.layerID == "watermark")
    }

    @Test func videoOverlayThreadsThrough() throws {
        let img = try loadTestImage()
        let videoURL = URL(fileURLWithPath: "/tmp/test.mov")
        let video = Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .overlay(ImageOverlay(img).id("a"))
        .overlay(ImageOverlay(img).id("b"))
        #expect(video.overlays.count == 2)
        #expect(video.overlays[0].layerID == "a")
        #expect(video.overlays[1].layerID == "b")
    }

    // MARK: - Engine — layer-tree shape

    @Test func layerTreeHasParentVideoAndOverlaySublayers() throws {
        let img = try loadTestImage()
        let overlays = [
            ImageOverlay(img).position(.topLeft).id("one"),
            ImageOverlay(img).position(.bottomRight).id("two"),
        ]
        let renderSize = CGSize(width: 1080, height: 1920)
        let tree = OverlayRenderer.buildLayerTree(overlays: overlays, renderSize: renderSize)

        #expect(tree.parent.bounds == CGRect(origin: .zero, size: renderSize))
        // sublayers: video + 2 overlays
        #expect(tree.parent.sublayers?.count == 3)
        // Video layer is the first sublayer
        #expect(tree.parent.sublayers?[0] === tree.videoLayer)
        // LayerID propagates to the CALayer.name
        #expect(tree.parent.sublayers?[1].name == "one")
        #expect(tree.parent.sublayers?[2].name == "two")
    }

    @Test func overlayWithoutIDHasNilLayerName() throws {
        let img = try loadTestImage()
        let tree = OverlayRenderer.buildLayerTree(
            overlays: [ImageOverlay(img)],
            renderSize: CGSize(width: 1080, height: 1080)
        )
        let overlayLayer = tree.parent.sublayers?[1]
        #expect(overlayLayer?.name == nil)
    }

    @Test func opacityAppliedToLayer() throws {
        let img = try loadTestImage()
        let tree = OverlayRenderer.buildLayerTree(
            overlays: [ImageOverlay(img).opacity(0.5)],
            renderSize: CGSize(width: 1080, height: 1080)
        )
        let overlayLayer = tree.parent.sublayers?[1]
        #expect(overlayLayer?.opacity == 0.5)
    }

    @Test func explicitSizeUsedWhenProvided() throws {
        let img = try loadTestImage()
        let tree = OverlayRenderer.buildLayerTree(
            overlays: [
                ImageOverlay(img)
                    .position(.center)
                    .size(.pixels(width: 200, height: 100))
                    .anchor(.center)
            ],
            renderSize: CGSize(width: 1080, height: 1920)
        )
        let overlayLayer = tree.parent.sublayers?[1]
        // Centered at (540, 960) with size 200x100 → origin at (440, 910)
        #expect(overlayLayer?.frame == CGRect(x: 440, y: 910, width: 200, height: 100))
    }

    // MARK: - Export

    @Test func exportWithImageOverlay() async throws {
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let outputURL = testOutputURL("overlay_export")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .overlay(
            ImageOverlay(img)
                .position(.center)
                .size(.normalized(width: 0.3, height: 0.3))
                .opacity(0.7)
        )
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        let asset = AVURLAsset(url: result)
        let dur = try await asset.load(.duration)
        #expect(CMTimeGetSeconds(dur) > 2.5)
        #expect(CMTimeGetSeconds(dur) < 3.5)
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithMultipleOverlays() async throws {
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let outputURL = testOutputURL("multi_overlay")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .overlay(ImageOverlay(img).position(.topLeft).anchor(.topLeft).size(.normalized(width: 0.2, height: 0.2)))
        .overlay(ImageOverlay(img).position(.bottomRight).anchor(.bottomRight).size(.normalized(width: 0.2, height: 0.2)).opacity(0.5))
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithOverlayAndTransition() async throws {
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let outputURL = testOutputURL("overlay_transition")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
            Transition.dissolve(duration: 0.4)
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .overlay(ImageOverlay(img).position(.center).size(.normalized(width: 0.2, height: 0.2)))
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }
}
