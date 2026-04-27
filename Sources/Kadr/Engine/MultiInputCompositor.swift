import Foundation
import CoreMedia
import CoreImage
import CoreGraphics

/// User code that blends multiple per-frame source images into a single output frame —
/// the multi-track / multi-input counterpart to v0.5's single-input ``Compositor``.
///
/// Used by the engine to merge parallel video tracks into the composition's output
/// frame: at each frame `t`, every track that's currently active contributes a
/// `CIImage` to `images`, and the compositor returns the blended result.
///
/// ```swift
/// // Custom blend mode — multiply the two layers:
/// struct MultiplyBlend: MultiInputCompositor {
///     func process(images: [CIImage], context: CompositorContext) -> CIImage {
///         guard images.count >= 2 else { return images.first ?? .empty() }
///         let filter = CIFilter(name: "CIMultiplyBlendMode")
///         filter?.setValue(images[1], forKey: kCIInputImageKey)
///         filter?.setValue(images[0], forKey: kCIInputBackgroundImageKey)
///         return filter?.outputImage ?? images[0]
///     }
/// }
///
/// Video {
///     VideoClip(url: base).trimmed(to: 0...10)
///     VideoClip(url: overlay).trimmed(to: 0...10).at(time: 0)
/// }
/// .compositor(MultiplyBlend())
/// ```
///
/// **Constraints**
/// - Synchronous return — same reasoning as v0.5's ``Compositor``: per-frame `async`
///   would multiply with frame rate. Preload state at construction time.
/// - `Sendable` — the engine crosses actor boundaries while running it.
/// - Inputs are in declaration order from the composition's `[any Clip]`. Earlier =
///   lower (background); later = higher (foreground). Custom compositors may use
///   different conventions internally, but Kadr passes them in declaration order.
/// - When only one track is active at a frame, `images` has exactly one element.
///   A single-element pass-through is the obvious default.
public protocol MultiInputCompositor: Sendable {
    func process(images: [CIImage], context: CompositorContext) -> CIImage
}

/// Default multi-track blender: alpha-composite later-over-earlier. Used when a
/// composition has multiple parallel tracks but no custom ``MultiInputCompositor`` is
/// attached via ``Video/compositor(_:)-(any)``.
///
/// Internal — users get this implicitly. Custom blends override via the public modifier.
internal struct AlphaCompositeBlender: MultiInputCompositor {
    func process(images: [CIImage], context: CompositorContext) -> CIImage {
        // Empty composition path — return a transparent image at render size.
        guard let first = images.first else {
            return CIImage(color: .clear)
                .cropped(to: CGRect(origin: .zero, size: context.renderSize))
        }
        // Single track — pass through unchanged. The engine still wraps single-track
        // compositions through this code path so behavior is uniform.
        if images.count == 1 { return first }

        // Iteratively composite: result = source-over(layer[i], result).
        // CISourceOverCompositing puts the foreground (input) over the background.
        var result = first
        for layer in images.dropFirst() {
            guard let filter = CIFilter(name: "CISourceOverCompositing") else { continue }
            filter.setValue(layer, forKey: kCIInputImageKey)
            filter.setValue(result, forKey: kCIInputBackgroundImageKey)
            if let output = filter.outputImage {
                result = output
            }
        }
        return result
    }
}

/// Closure-backed `MultiInputCompositor` conformance. Internal — public construction
/// goes through ``Video/compositor(_:)-(closure)`` which wraps the closure into one of
/// these.
internal struct ClosureMultiInputCompositor: MultiInputCompositor {
    let body: @Sendable ([CIImage], CompositorContext) -> CIImage

    func process(images: [CIImage], context: CompositorContext) -> CIImage {
        body(images, context)
    }
}
