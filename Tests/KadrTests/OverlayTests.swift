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

    // MARK: - TextOverlay DSL

    @Test func defaultTextOverlayValues() {
        let t = TextOverlay("hello")
        #expect(t.text == "hello")
        #expect(t.style == .default)
        #expect(t.position == .center)
        #expect(t.size == nil)
        #expect(t.anchor == .center)
        #expect(t.opacity == 1.0)
        #expect(t.layerID == nil)
    }

    @Test func textOverlayModifierChain() {
        let style = TextStyle(fontSize: 64, alignment: .center, weight: .bold)
        let t = TextOverlay("HELLO")
            .style(style)
            .position(.bottom)
            .anchor(.bottom)
            .opacity(0.9)
            .id("title")
        #expect(t.text == "HELLO")
        #expect(t.style == style)
        #expect(t.position == .bottom)
        #expect(t.anchor == .bottom)
        #expect(t.opacity == 0.9)
        #expect(t.layerID == "title")
    }

    @Test func videoAcceptsHeterogeneousOverlays() throws {
        let img = try loadTestImage()
        let videoURL = URL(fileURLWithPath: "/tmp/test.mov")
        let video = Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .overlay(ImageOverlay(img).id("watermark"))
        .overlay(TextOverlay("HELLO").id("title"))
        #expect(video.overlays.count == 2)
        #expect(video.overlays[0] is ImageOverlay)
        #expect(video.overlays[1] is TextOverlay)
    }

    // MARK: - Engine — text-layer dispatch

    @Test func textOverlayProducesCATextLayer() {
        let tree = OverlayRenderer.buildLayerTree(
            overlays: [TextOverlay("hi").id("greeting")],
            renderSize: CGSize(width: 1080, height: 1920)
        )
        // sublayers: video + 1 text overlay
        #expect(tree.parent.sublayers?.count == 2)
        let textLayer = tree.parent.sublayers?[1]
        #expect(textLayer is CATextLayer)
        #expect(textLayer?.name == "greeting")
        #expect((textLayer as? CATextLayer)?.string as? String == "hi")
    }

    @Test func textOverlayDefaultSizeFillsRenderArea() {
        let renderSize = CGSize(width: 1080, height: 1920)
        let tree = OverlayRenderer.buildLayerTree(
            overlays: [TextOverlay("x").position(.topLeft).anchor(.topLeft)],
            renderSize: renderSize
        )
        let textLayer = tree.parent.sublayers?[1] as? CATextLayer
        // Default size = full render area, anchored top-left at (0,0) → frame is (0,0,1080,1920)
        #expect(textLayer?.frame == CGRect(origin: .zero, size: renderSize))
    }

    @Test func textOverlayStyleAppliesToLayer() {
        let style = TextStyle(fontSize: 100, alignment: .center, weight: .bold)
        let tree = OverlayRenderer.buildLayerTree(
            overlays: [TextOverlay("bold", style: style)],
            renderSize: CGSize(width: 1080, height: 1080)
        )
        let textLayer = tree.parent.sublayers?[1] as? CATextLayer
        #expect(textLayer?.fontSize == 100)
        #expect(textLayer?.alignmentMode == .center)
    }

    // MARK: - Export with text

    @Test func exportWithTextOverlay() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("text_export")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .overlay(
            TextOverlay("HELLO WORLD", style: TextStyle(fontSize: 80, alignment: .center, weight: .bold))
                .position(.bottom)
                .anchor(.bottom)
                .size(.normalized(width: 1.0, height: 0.2))
        )
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithTextAndImageOverlays() async throws {
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let outputURL = testOutputURL("text_and_image")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .overlay(ImageOverlay(img).position(.topRight).anchor(.topRight).size(.normalized(width: 0.15, height: 0.15)))
        .overlay(TextOverlay("CAPTION").position(.bottom).anchor(.bottom).size(.normalized(width: 1.0, height: 0.15)))
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - StickerOverlay DSL

    @Test func defaultStickerValues() throws {
        let img = try loadTestImage()
        let s = StickerOverlay(img)
        #expect(s.position == .center)
        #expect(s.size == nil)
        #expect(s.anchor == .center)
        #expect(s.opacity == 1.0)
        #expect(s.rotation == 0)
        #expect(s.shadow == nil)
        #expect(s.layerID == nil)
    }

    @Test func stickerModifierChain() throws {
        let img = try loadTestImage()
        let s = StickerOverlay(img)
            .position(.bottomLeft)
            .size(.normalized(width: 0.2, height: 0.2))
            .anchor(.bottomLeft)
            .opacity(0.9)
            .rotation(degrees: -10)
            .shadow(color: .black, radius: 12, offset: CGSize(width: 0, height: 6), opacity: 0.5)
            .id("burst")
        #expect(s.position == .bottomLeft)
        #expect(s.opacity == 0.9)
        #expect(abs(s.rotation - (-10 * .pi / 180)) < 0.0001)
        #expect(s.shadow?.radius == 12)
        #expect(s.layerID == "burst")
    }

    @Test func stickerRotationRadiansAndDegreesAgree() throws {
        let img = try loadTestImage()
        let radians = StickerOverlay(img).rotation(.pi / 2)
        let degrees = StickerOverlay(img).rotation(degrees: 90)
        #expect(abs(radians.rotation - degrees.rotation) < 0.0001)
    }

    @Test func stickerShadowDefaults() throws {
        let img = try loadTestImage()
        let s = StickerOverlay(img).shadow()  // all-defaults shadow
        #expect(s.shadow != nil)
        #expect(s.shadow?.radius == 8)
        #expect(s.shadow?.opacity == 0.4)
    }

    // MARK: - Engine — sticker layer dispatch

    @Test func stickerProducesLayerWithRotationAndShadow() throws {
        let img = try loadTestImage()
        let sticker = StickerOverlay(img)
            .size(.pixels(width: 100, height: 100))
            .rotation(degrees: 45)
            .shadow(color: .black, radius: 10, offset: CGSize(width: 2, height: 4), opacity: 0.6)
        let tree = OverlayRenderer.buildLayerTree(
            overlays: [sticker],
            renderSize: CGSize(width: 1080, height: 1080)
        )
        let layer = tree.parent.sublayers?[1]
        #expect(layer != nil)
        // Shadow propagated
        #expect(layer?.shadowRadius == 10)
        #expect(layer?.shadowOffset == CGSize(width: 2, height: 4))
        #expect(layer?.shadowOpacity == 0.6)
        // Rotation applied as a 3D transform; for a Z-axis rotation of 45° at the
        // identity, m11 should equal cos(π/4) ≈ 0.7071
        let m11 = layer?.transform.m11 ?? 0
        #expect(abs(m11 - cos(.pi / 4)) < 0.001)
    }

    @Test func stickerWithoutShadowOrRotationRendersLikeImage() throws {
        let img = try loadTestImage()
        let tree = OverlayRenderer.buildLayerTree(
            overlays: [StickerOverlay(img).size(.pixels(width: 50, height: 50))],
            renderSize: CGSize(width: 1080, height: 1080)
        )
        let layer = tree.parent.sublayers?[1]
        #expect(layer?.shadowOpacity == 0)
        // Identity transform
        #expect(CATransform3DIsIdentity(layer?.transform ?? CATransform3DIdentity))
    }

    // MARK: - Export with sticker

    @Test func exportWithSticker() async throws {
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let outputURL = testOutputURL("sticker_export")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .overlay(
            StickerOverlay(img)
                .position(.center)
                .size(.normalized(width: 0.3, height: 0.3))
                .rotation(degrees: -15)
                .shadow(radius: 10, offset: CGSize(width: 0, height: 6))
        )
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithMixedOverlayTypes() async throws {
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let outputURL = testOutputURL("mixed_overlays")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .overlay(ImageOverlay(img).position(.topRight).anchor(.topRight).size(.normalized(width: 0.15, height: 0.15)))
        .overlay(StickerOverlay(img).position(.center).size(.normalized(width: 0.2, height: 0.2)).rotation(degrees: 20))
        .overlay(TextOverlay("FINAL").position(.bottom).anchor(.bottom).size(.normalized(width: 1.0, height: 0.2)))
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - Watermark sugar

    @Test func watermarkUsesDefaultsAndAddsOverlay() throws {
        let img = try loadTestImage()
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .watermark(img)

        #expect(video.overlays.count == 1)
        let added = video.overlays[0] as? ImageOverlay
        #expect(added != nil)
        #expect(added?.position == .bottomRight)
        #expect(added?.anchor == .bottomRight)
        #expect(added?.opacity == 0.6)
        #expect(added?.layerID == "watermark")
        #expect(added?.size == nil)
    }

    @Test func watermarkAcceptsCustomPositionAndOpacity() throws {
        let img = try loadTestImage()
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .watermark(img, position: .topRight, opacity: 0.4)

        let added = video.overlays.first as? ImageOverlay
        #expect(added?.position == .topRight)
        #expect(added?.anchor == .topRight)
        #expect(added?.opacity == 0.4)
    }

    @Test func watermarkAcceptsCustomSize() throws {
        let img = try loadTestImage()
        let size = Size.normalized(width: 0.1, height: 0.05)
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .watermark(img, size: size)

        let added = video.overlays.first as? ImageOverlay
        #expect(added?.size == size)
    }

    @Test func watermarkUsesCenterAnchorForCustomPosition() throws {
        let img = try loadTestImage()
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .watermark(img, position: .normalized(x: 0.95, y: 0.95))

        let added = video.overlays.first as? ImageOverlay
        // Custom position falls back to center anchor (no named match)
        #expect(added?.anchor == .center)
    }

    @Test func multipleWatermarksStack() throws {
        let img = try loadTestImage()
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .watermark(img, position: .topLeft)
        .watermark(img, position: .bottomRight)
        // Both have id "watermark" — that's user error to dedupe; the engine just
        // stacks them in declaration order.
        #expect(video.overlays.count == 2)
    }

    @Test func exportWithWatermark() async throws {
        let videoURL = try loadTestVideoURL()
        let img = try loadTestImage()
        let outputURL = testOutputURL("watermark_export")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .watermark(img, size: .normalized(width: 0.15, height: 0.05))
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
