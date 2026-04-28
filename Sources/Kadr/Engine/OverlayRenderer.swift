import Foundation
import CoreGraphics
import CoreMedia
import QuartzCore
import AVFoundation
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
    ///
    /// `compositionDuration` is the total composition duration in `CMTime` — required to
    /// drive ``Overlay/visibilityRange`` timing animations. Pass `composition.duration`.
    static func buildLayerTree(
        overlays: [any Overlay],
        renderSize: CGSize,
        compositionDuration: CMTime = .zero
    ) -> LayerTree {
        let bounds = CGRect(origin: .zero, size: renderSize)

        let parent = CALayer()
        parent.frame = bounds
        parent.isGeometryFlipped = true  // CALayer defaults bottom-up; flip to top-left origin

        let videoLayer = CALayer()
        videoLayer.frame = bounds
        parent.addSublayer(videoLayer)

        for overlay in overlays {
            let frame = resolvedFrame(for: overlay, in: renderSize)
            let sublayer = makeContentLayer(for: overlay, frame: frame, renderSize: renderSize)
            let baseOpacity = Float(overlay.opacity)
            sublayer.opacity = baseOpacity
            if let layerID = overlay.layerID {
                sublayer.name = layerID.rawValue
            }
            if let range = overlay.visibilityRange {
                applyVisibilityTiming(
                    to: sublayer,
                    range: range,
                    baseOpacity: baseOpacity,
                    compositionDuration: compositionDuration
                )
            }
            // v0.8: text animation. The recipe builds CAAnimation(s) targeting the
            // overlay's text layer; we add them with stable keys so they don't collide
            // with the visibility-timing animation. The recipe is responsible for its
            // own beginTime / fillMode / removedOnCompletion semantics.
            if let textOverlay = overlay as? TextOverlay,
               let textAnim = textOverlay.textAnimation {
                let animations = textAnim.makeAnimations(for: sublayer)
                for (i, anim) in animations.enumerated() {
                    sublayer.add(anim, forKey: "kadr.textAnimation.\(i)")
                }
            }
            parent.addSublayer(sublayer)
        }

        return LayerTree(parent: parent, videoLayer: videoLayer)
    }

    /// Drive a layer's `opacity` so it renders only during `range`.
    /// The animation uses `CAKeyframeAnimation` with `.discrete` calculation mode for an
    /// instant on/off transition (no fade). Required machinery:
    ///   - Animation's `beginTime` must be `AVCoreAnimationBeginTimeAtZero` (a magic
    ///     value AVFoundation uses to mean "the composition's t=0").
    ///   - `fillMode = .forwards` and `isRemovedOnCompletion = false` so the final value
    ///     persists past the animation's end.
    ///   - `keyTimes` are normalized `[0, 1]` fractions of the animation duration; we use
    ///     the full composition duration so the fractions match composition time.
    private static func applyVisibilityTiming(
        to layer: CALayer,
        range: CMTimeRange,
        baseOpacity: Float,
        compositionDuration: CMTime
    ) {
        let total = CMTimeGetSeconds(compositionDuration)
        guard total > 0 else { return }

        let startSec = max(0, CMTimeGetSeconds(range.start))
        let endSec = min(total, CMTimeGetSeconds(range.end))
        // No-op (fully outside or zero-length range): just hide the layer.
        guard startSec < endSec else {
            layer.opacity = 0
            return
        }

        let startFraction = startSec / total
        let endFraction = endSec / total

        // Hide by default; the keyframe animation switches the visible window on/off.
        layer.opacity = 0

        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.keyTimes = [0, NSNumber(value: startFraction), NSNumber(value: endFraction), 1]
        // 3 values for 4 keyTimes with .discrete mode:
        //   [0, startFraction):    invisible
        //   [startFraction, end):  visible at baseOpacity
        //   [endFraction, 1):      invisible again
        anim.values = [Float(0), baseOpacity, Float(0)]
        anim.calculationMode = .discrete
        anim.duration = total
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        layer.add(anim, forKey: "kadr.visibilityRange")
    }

    // MARK: - Per-type content layers

    private static func makeContentLayer(
        for overlay: any Overlay,
        frame: CGRect,
        renderSize: CGSize
    ) -> CALayer {
        if let img = overlay as? ImageOverlay {
            return makeImageLayer(image: img.image, frame: frame)
        }
        if let sticker = overlay as? StickerOverlay {
            return makeStickerLayer(sticker, frame: frame)
        }
        if let txt = overlay as? TextOverlay {
            return makeTextLayer(text: txt.text, style: txt.style, frame: frame)
        }
        // Unknown overlay type — return an empty layer so the export still succeeds
        let layer = CALayer()
        layer.frame = frame
        return layer
    }

    private static func makeStickerLayer(_ sticker: StickerOverlay, frame: CGRect) -> CALayer {
        // Reuse the image-layer build, then layer on sticker-specific effects.
        let layer = makeImageLayer(image: sticker.image, frame: frame)

        if sticker.rotation != 0 {
            // Rotate around the layer's center. Setting CALayer.transform applies
            // the transform around the anchor point, which defaults to (0.5, 0.5).
            layer.transform = CATransform3DMakeRotation(CGFloat(sticker.rotation), 0, 0, 1)
        }

        if let shadow = sticker.shadow {
            layer.shadowColor = shadow.color.cgColor
            layer.shadowRadius = CGFloat(shadow.radius)
            layer.shadowOffset = shadow.offset
            layer.shadowOpacity = Float(shadow.opacity)
            // Required so the shadow renders on a layer with image contents
            layer.masksToBounds = false
        }

        return layer
    }

    private static func makeImageLayer(image: PlatformImage, frame: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contents = cgImage(from: image)
        layer.contentsGravity = .resizeAspect
        // contentsScale matches the source image's pixel density to the layer's bounds
        // for one-to-one pixel mapping.
        if let cg = cgImage(from: image), frame.width > 0 {
            layer.contentsScale = CGFloat(cg.width) / frame.width
        }
        return layer
    }

    private static func makeTextLayer(text: String, style: TextStyle, frame: CGRect) -> CATextLayer {
        let layer = CATextLayer()
        layer.frame = frame
        layer.string = text
        layer.fontSize = CGFloat(style.fontSize)
        layer.foregroundColor = style.color.cgColor
        layer.alignmentMode = textAlignmentMode(style.alignment)
        layer.isWrapped = true
        layer.truncationMode = .none

        if let fontName = style.fontName {
            layer.font = fontName as CFString
        } else {
            // System font at requested weight. CATextLayer.font accepts CFString (font
            // family name) or CTFont. Use CTFont to honor weight cleanly.
            let weight = ctFontWeight(for: style.weight)
            let descriptor = CTFontDescriptorCreateWithAttributes([
                kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]
            ] as CFDictionary)
            let ctFont = CTFontCreateWithFontDescriptor(descriptor, CGFloat(style.fontSize), nil)
            layer.font = ctFont
        }

        // 2x renders text crisply at most export resolutions; production pipelines often
        // bump this further but 2x is a sensible default that won't over-allocate.
        layer.contentsScale = 2.0
        return layer
    }

    private static func textAlignmentMode(_ alignment: TextStyle.Alignment) -> CATextLayerAlignmentMode {
        switch alignment {
        case .leading:  return .left
        case .center:   return .center
        case .trailing: return .right
        }
    }

    private static func ctFontWeight(for weight: TextStyle.Weight) -> CGFloat {
        // Values from kCTFontWeightRegular / kCTFontWeightMedium / kCTFontWeightBold
        switch weight {
        case .regular: return 0.0
        case .medium:  return 0.23
        case .bold:    return 0.4
        }
    }

    // MARK: - Frame resolution

    private static func resolvedFrame(for overlay: any Overlay, in renderSize: CGSize) -> CGRect {
        let resolvedSize: Size
        if let explicit = overlay.size {
            resolvedSize = explicit
        } else if let img = overlay as? ImageOverlay, let cg = cgImage(from: img.image) {
            // ImageOverlay default: natural pixel size
            resolvedSize = .pixels(width: Double(cg.width), height: Double(cg.height))
        } else if let sticker = overlay as? StickerOverlay, let cg = cgImage(from: sticker.image) {
            // StickerOverlay default: natural pixel size
            resolvedSize = .pixels(width: Double(cg.width), height: Double(cg.height))
        } else if overlay is TextOverlay {
            // TextOverlay default: full render area so text can wrap edge-to-edge
            resolvedSize = .normalized(width: 1.0, height: 1.0)
        } else {
            // Conservative default for unknown / un-resolvable overlays
            resolvedSize = .normalized(width: 0.25, height: 0.25)
        }
        return FrameResolver.resolve(
            position: overlay.position,
            size: resolvedSize,
            anchor: overlay.anchor,
            in: renderSize
        )
    }

    // MARK: - Cross-platform CGImage extraction

    private static func cgImage(from image: PlatformImage) -> CGImage? {
        #if canImport(UIKit)
        return image.cgImage
        #elseif canImport(AppKit)
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}
