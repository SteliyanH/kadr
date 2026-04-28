import Foundation
import AVFoundation
import CoreMedia
import CoreImage
import CoreGraphics

/// Custom `AVVideoCompositing` implementation that hands per-frame compositing duties
/// off to the user's ``MultiInputCompositor`` (or the built-in ``AlphaCompositeBlender``
/// when none is set).
///
/// **Lifecycle.** AVFoundation instantiates this class itself via the
/// `customVideoCompositorClass` property on `AVMutableVideoComposition`; we don't get to
/// pass state via `init`. The active `MultiInputCompositor` is plumbed through a custom
/// ``KadrVideoCompositionInstruction`` subclass — each instruction carries its own
/// compositor reference, retrieved in `startRequest`.
///
/// **Threading.** AVFoundation calls `startRequest` from a background queue. We hop to
/// our own render queue to bound parallelism and serialize against
/// `renderContextChanged` updates.
internal final class KadrVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {

    // MARK: - Pixel format negotiation

    /// Pixel format AVFoundation should deliver source frames in. BGRA matches what
    /// `CIImage(cvPixelBuffer:)` consumes most efficiently; matches the format the
    /// existing v0.5 single-track pipeline implicitly uses.
    var sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    /// Pixel format we render the composited output in. Same as source.
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    // MARK: - Render context + queues

    private let renderQueue = DispatchQueue(label: "com.kadr.video-compositor.render", qos: .userInitiated)
    private let renderContextQueue = DispatchQueue(label: "com.kadr.video-compositor.context", qos: .userInitiated)

    private var renderContext: AVVideoCompositionRenderContext?
    private var shouldCancelAllRequests = false
    private let ciContext = CIContext()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextQueue.sync {
            self.renderContext = newRenderContext
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        renderQueue.sync {
            shouldCancelAllRequests = true
        }
        renderQueue.async { [weak self] in
            self?.shouldCancelAllRequests = false
        }
    }

    // MARK: - Per-frame compositing

    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            guard let self else { return }
            if self.shouldCancelAllRequests {
                asyncVideoCompositionRequest.finishCancelledRequest()
                return
            }
            self.process(request: asyncVideoCompositionRequest)
        }
    }

    private func process(request: AVAsynchronousVideoCompositionRequest) {
        guard let renderContext = renderContextQueue.sync(execute: { self.renderContext }) else {
            request.finish(with: NSError(
                domain: "Kadr", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Custom video compositor missing render context"]
            ))
            return
        }

        // Pull our custom instruction; fall back to the default blender if it's missing.
        let instruction = request.videoCompositionInstruction as? KadrVideoCompositionInstruction
        // Time-windowed compositor selection (v0.7): when the instruction declares a
        // window and the request's composition time falls outside it, run the default
        // alpha-composite blender instead of the user's compositor for this frame.
        let useUserCompositor: Bool = {
            guard instruction?.multiInputCompositor != nil else { return false }
            guard let window = instruction?.compositorWindow else { return true }
            return window.containsTime(request.compositionTime)
        }()
        let compositor: any MultiInputCompositor = useUserCompositor
            ? (instruction!.multiInputCompositor!)
            : AlphaCompositeBlender()

        // Pull each track's source frame in instruction declaration order. AVFoundation
        // returns the buffer in the format we requested via `sourcePixelBufferAttributes`.
        var images: [CIImage] = []
        let trackIDs = (instruction?.requiredSourceTrackIDs ?? []).compactMap { $0 as? CMPersistentTrackID }
        for trackID in trackIDs {
            guard let pixelBuffer = request.sourceFrame(byTrackID: trackID) else { continue }
            images.append(CIImage(cvPixelBuffer: pixelBuffer))
        }

        // Run the user's (or default) compositor.
        let context = CompositorContext(
            time: request.compositionTime,
            renderSize: renderContext.size
        )
        let output = compositor.process(images: images, context: context)

        // Render the result CIImage into a fresh CVPixelBuffer from the render pool.
        guard let outputBuffer = renderContext.newPixelBuffer() else {
            request.finish(with: NSError(
                domain: "Kadr", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output pixel buffer"]
            ))
            return
        }
        let bounds = CGRect(origin: .zero, size: renderContext.size)
        ciContext.render(
            output,
            to: outputBuffer,
            bounds: bounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        request.finish(withComposedVideoFrame: outputBuffer)
    }
}

/// Custom `AVMutableVideoCompositionInstruction` subclass that carries the active
/// ``MultiInputCompositor`` for the `KadrVideoCompositor` to read in `startRequest`.
///
/// Subclassing the instruction (rather than using a global / static reference on the
/// compositor class) means concurrent multi-track exports remain isolated and the
/// instruction's lifetime is bounded by the export session.
internal final class KadrVideoCompositionInstruction: AVMutableVideoCompositionInstruction, @unchecked Sendable {

    var multiInputCompositor: (any MultiInputCompositor)?

    /// Optional time window (in composition time) during which the user-supplied
    /// compositor is active. When `nil`, the compositor runs for the full composition.
    /// When set, frames whose `compositionTime` falls outside the window are rendered
    /// via the default `AlphaCompositeBlender` instead. Added in v0.7.
    var compositorWindow: CMTimeRange?

    /// Track IDs whose source frames the custom compositor needs at request time.
    /// Backing storage for the read-only base-class `requiredSourceTrackIDs` property;
    /// set via ``setRequiredSourceTrackIDs(_:)``.
    private var _requiredSourceTrackIDs: [NSValue] = []

    /// Override to declare we always composite — never pass a single source track
    /// through unmodified. The base class's property is read-only; override is the
    /// supported way to express this.
    override var passthroughTrackID: CMPersistentTrackID { kCMPersistentTrackID_Invalid }

    /// Override to expose the stored required-track-IDs to AVFoundation. AVFoundation
    /// uses this list to schedule which source frames it must decode and pass into
    /// `AVAsynchronousVideoCompositionRequest`.
    override var requiredSourceTrackIDs: [NSValue] { _requiredSourceTrackIDs }

    func setRequiredSourceTrackIDs(_ trackIDs: [CMPersistentTrackID]) {
        _requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
    }
}
