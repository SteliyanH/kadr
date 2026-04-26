import Foundation
import CoreGraphics
import QuartzCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Builds the CALayer tree required by `AVVideoCompositionCoreAnimationTool`.
///
/// Tree shape:
/// ```
/// parent (renderSize)
/// ├── videoLayer (renderSize, where the video is drawn)
/// └── overlay sublayers (added on top, in declaration order)
/// ```
internal enum OverlayRenderer {

    struct LayerTree {
        let parent: CALayer
        let videoLayer: CALayer
    }

    /// Build a parent + video layer with each overlay placed as a sublayer.
    static func buildLayerTree(
        overlays: [ImageOverlay],
        renderSize: CGSize
    ) -> LayerTree {
        let bounds = CGRect(origin: .zero, size: renderSize)

        let parent = CALayer()
        parent.frame = bounds
        parent.isGeometryFlipped = true  // CALayer defaults bottom-up; flip to top-left origin

        let videoLayer = CALayer()
        videoLayer.frame = bounds
        parent.addSublayer(videoLayer)

        for overlay in overlays {
            let sublayer = CALayer()
            sublayer.frame = resolvedFrame(for: overlay, in: renderSize)
            sublayer.contents = imageContents(for: overlay.image)
            sublayer.opacity = Float(overlay.opacity)
            sublayer.contentsGravity = .resizeAspect
            // contentsScale matches the render canvas scale; layers default to 1.0 which
            // produces blocky output if the source image is high-resolution. Using the
            // ratio of resolved size to source size gives one-to-one pixel mapping.
            if let cgImage = cgImage(from: overlay.image) {
                sublayer.contentsScale = CGFloat(cgImage.width) / sublayer.frame.width
            }
            if let layerID = overlay.layerID {
                sublayer.name = layerID.rawValue
            }
            parent.addSublayer(sublayer)
        }

        return LayerTree(parent: parent, videoLayer: videoLayer)
    }

    private static func resolvedFrame(for overlay: ImageOverlay, in renderSize: CGSize) -> CGRect {
        let resolvedSize: Size
        if let explicit = overlay.size {
            resolvedSize = explicit
        } else if let cg = cgImage(from: overlay.image) {
            resolvedSize = .pixels(width: Double(cg.width), height: Double(cg.height))
        } else {
            // Fall back to a sensible default if we can't resolve the image's natural size
            resolvedSize = .normalized(width: 0.25, height: 0.25)
        }
        return FrameResolver.resolve(
            position: overlay.position,
            size: resolvedSize,
            anchor: overlay.anchor,
            in: renderSize
        )
    }

    /// Cross-platform contents value for a `CALayer`. UIKit and AppKit need slightly
    /// different shapes — both reduce to a `CGImage`.
    private static func imageContents(for image: PlatformImage) -> Any? {
        cgImage(from: image)
    }

    private static func cgImage(from image: PlatformImage) -> CGImage? {
        #if canImport(UIKit)
        return image.cgImage
        #elseif canImport(AppKit)
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}
