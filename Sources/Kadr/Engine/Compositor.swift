import Foundation
import CoreMedia
import CoreImage

/// Per-frame state passed to a ``Compositor``. Use a struct (rather than loose
/// parameters) so additional fields (`clipDuration`, `clipIndex`, etc.) can land in
/// future Kadr releases without breaking custom conformers.
public struct CompositorContext: Sendable {
    /// The composition time of the frame being processed.
    public let time: CMTime

    /// The engine's render canvas size in pixels (post-crop, post-preset).
    public let renderSize: CGSize

    public init(time: CMTime, renderSize: CGSize) {
        self.time = time
        self.renderSize = renderSize
    }
}

/// User code that processes a single frame of a clip's video as part of the export
/// pre-render pass. Compositors are applied **after** ``Filter``s on the same clip,
/// so they receive the post-filter image; their output then flows into the
/// composition assembly (transitions, overlays, crop) downstream.
///
/// ```swift
/// struct InvertColors: Compositor {
///     func process(image: CIImage, context: CompositorContext) -> CIImage {
///         CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: image])?
///             .outputImage ?? image
///     }
/// }
///
/// VideoClip(url: clipURL).compositor(InvertColors())
/// ```
///
/// For ad-hoc use, prefer the closure form on ``VideoClip/compositor(_:)-((CIImage,CompositorContext)->CIImage)``.
///
/// **Constraints**
/// - Synchronous return — Kadr wraps the call in
///   `applyingCIFiltersWithHandler` which expects a non-`async` handler. Per-frame
///   `async` would multiply with frame rate and clip duration; preload state at
///   construction time and keep `process` cheap.
/// - `Sendable` — the engine crosses actor boundaries while running compositors.
/// - Single-clip / single-input — to combine several tracks' frames (a custom
///   blend or transition), use ``MultiInputCompositor`` instead.
public protocol Compositor: Sendable {
    func process(image: CIImage, context: CompositorContext) -> CIImage
}

/// Closure-backed `Compositor` conformance. Internal — public construction goes through
/// ``VideoClip/compositor(_:)-((CIImage,CompositorContext)->CIImage)`` which wraps a closure into one of these.
internal struct ClosureCompositor: Compositor {
    let body: @Sendable (CIImage, CompositorContext) -> CIImage

    func process(image: CIImage, context: CompositorContext) -> CIImage {
        body(image, context)
    }
}
