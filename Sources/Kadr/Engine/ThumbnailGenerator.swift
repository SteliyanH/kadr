import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A reusable thumbnail / scrub-frame generator for a ``Video``.
///
/// Build one with ``Video/thumbnailGenerator()``. It composes the video **once** and
/// holds a single `AVAssetImageGenerator`, so a scrubber or filmstrip requesting many
/// frames pays the composition + generator-allocation cost a single time. By contrast
/// ``Video/thumbnail(at:)-(CMTime)`` re-runs the full composition and builds a fresh
/// generator on every call — fine for one frame, wasteful for many.
///
/// ```swift
/// let generator = try await video.thumbnailGenerator()   // composes once
/// let first  = try await generator.thumbnail(at: 1.0)    // reuses the generator
/// let second = try await generator.thumbnail(at: 2.5)
///
/// // Filmstrip: stream frames as each becomes ready.
/// for try await frame in generator.thumbnails(at: scrubTimes) {
///     strip.place(frame.image, at: frame.requestedTime)
/// }
/// ```
///
/// > **Overlays are not baked in.** Like ``Video/thumbnail(at:)-(CMTime)`` and
/// > ``Video/makePlayerItem()``, the underlying `AVAssetImageGenerator` uses the
/// > playback `videoComposition`, which excludes overlays (AVFoundation's
/// > `AVVideoCompositionCoreAnimationTool` is export-only). Compose overlays on top of
/// > the returned image using ``Layout/resolveFrame(position:size:anchor:in:)``.
///
/// Added in v0.14.
///
/// > Concurrency: a `final class` marked `@unchecked Sendable` rather than an `actor` —
/// > `AVAssetImageGenerator` is thread-safe for image generation, and a value type keeps
/// > the batch ``thumbnails(at:)`` stream (which drives `images(for:)` from a producer
/// > task) free of actor-isolation friction. Matches the engine's other AVFoundation
/// > wrappers (``KadrVideoCompositor``).
public final class ThumbnailGenerator: @unchecked Sendable {

    private let generator: AVAssetImageGenerator

    /// Builds the generator from an already-composed playback composition. Internal —
    /// consumers go through ``Video/thumbnailGenerator()`` so composition stays a
    /// single, validated code path.
    internal init(playback: PlaybackComposition) {
        let generator = AVAssetImageGenerator(asset: playback.composition)
        // Match Video.thumbnail(at:)'s configuration exactly so a generator-produced
        // frame is identical to the one-shot path: honor track transforms, and request
        // frame-accurate times (zero tolerance) for scrub precision.
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if let videoComposition = playback.videoComposition {
            generator.videoComposition = videoComposition
        }
        self.generator = generator
    }

    /// A single rendered frame from a batch ``thumbnails(at:)`` request.
    ///
    /// `requestedTime` is the time you asked for; `actualTime` is the nearest frame
    /// boundary the generator actually rendered (they match when tolerances are zero and
    /// the time lands on a frame). Use `requestedTime` to place the frame — batch
    /// emission order is not guaranteed.
    ///
    /// > Marked `@unchecked Sendable`: `NSImage` is not `Sendable` on AppKit, but `image`
    /// > is an immutable, never-mutated render result, so it's safe to hand across tasks.
    public struct Frame: @unchecked Sendable {
        public let requestedTime: CMTime
        public let actualTime: CMTime
        public let image: PlatformImage
    }

    /// Render a single frame at composition time `time`, reusing the shared generator.
    public func thumbnail(at time: CMTime) async throws -> PlatformImage {
        let result = try await generator.image(at: time)
        return Self.platformImage(from: result.image)
    }

    /// Render a single frame at `seconds` into the composition. Convenience overload of
    /// ``thumbnail(at:)-(CMTime)``.
    public func thumbnail(at seconds: TimeInterval) async throws -> PlatformImage {
        try await thumbnail(at: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    /// Stream frames for many times at once — the filmstrip / scrub-strip path.
    ///
    /// Backed by `AVAssetImageGenerator.images(for:)`. Each ``Frame`` is yielded as the
    /// generator finishes it; **emission order is not guaranteed**, so place each frame
    /// by its ``Frame/requestedTime``. Cancelling the consuming task (or calling
    /// ``cancel()``) stops in-flight generation.
    public func thumbnails(at times: [CMTime]) -> AsyncThrowingStream<Frame, Error> {
        // Capture `self` (this class is `@unchecked Sendable`) rather than the
        // non-Sendable `AVAssetImageGenerator` directly, so the producer task doesn't
        // smuggle a non-Sendable value across the closure boundary.
        AsyncThrowingStream { [self] continuation in
            let task = Task {
                do {
                    for await result in self.generator.images(for: times) {
                        try Task.checkCancellation()
                        let cgImage = try result.image
                        let actualTime = try result.actualTime
                        continuation.yield(
                            Frame(
                                requestedTime: result.requestedTime,
                                actualTime: actualTime,
                                image: Self.platformImage(from: cgImage)
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Cancel all in-flight image generation. Safe to call when idle (no-op).
    public func cancel() {
        generator.cancelAllCGImageGeneration()
    }

    // MARK: - Cross-platform CGImage → PlatformImage

    private static func platformImage(from cgImage: CGImage) -> PlatformImage {
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }
}
