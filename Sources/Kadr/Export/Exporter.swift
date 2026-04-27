import Foundation
import AVFoundation

/// Cancelable, progress-reporting export of a ``Video``. Build with ``Video/exporter(to:)``.
///
/// ```swift
/// let exporter = video.exporter(to: outputURL)
/// for try await progress in exporter.run() {
///     print("\(Int(progress.fractionCompleted * 100))%")
/// }
/// ```
///
/// Call ``cancel()`` from any thread to abort the in-flight export. The stream will
/// then throw ``KadrError/cancelled``.
public final class Exporter: @unchecked Sendable {
    internal let clips: [any Clip]
    internal let audioTracks: [AudioTrack]
    internal let preset: Preset
    internal let overlays: [any Overlay]
    internal let crop: CropRegion?
    internal let multiInputCompositor: (any MultiInputCompositor)?
    internal let outputURL: URL
    private let cancellationToken = CancellationToken()

    internal init(
        clips: [any Clip],
        audioTracks: [AudioTrack],
        preset: Preset,
        overlays: [any Overlay] = [],
        crop: CropRegion? = nil,
        multiInputCompositor: (any MultiInputCompositor)? = nil,
        outputURL: URL
    ) {
        self.clips = clips
        self.audioTracks = audioTracks
        self.preset = preset
        self.overlays = overlays
        self.crop = crop
        self.multiInputCompositor = multiInputCompositor
        self.outputURL = outputURL
    }

    /// Begin the export and yield ``ExportProgress`` updates. The final element is at
    /// `fractionCompleted == 1.0`. Throws ``KadrError`` on validation failure, the
    /// underlying export error, or ``KadrError/cancelled`` if ``cancel()`` was called.
    public func run() -> AsyncThrowingStream<ExportProgress, Error> {
        let token = cancellationToken

        return AsyncThrowingStream { continuation in
            Task { [clips, audioTracks, preset, overlays, crop, outputURL] in
                do {
                    guard !clips.isEmpty else {
                        throw KadrError.noClipsProvided
                    }

                    if token.isCancelled {
                        throw KadrError.cancelled
                    }

                    // Single ImageClip fast path — skip when overlays or crop are set
                    // (both need the videoComposition path: animation tool for overlays,
                    // adjusted renderSize+offset for crop).
                    if clips.count == 1, let imageClip = clips.first as? ImageClip, overlays.isEmpty, crop == nil {
                        continuation.yield(ExportProgress(fractionCompleted: 0))
                        let audioURL = imageClip.audioURL ?? audioTracks.first?.url
                        _ = try await ImageEncoder.encode(
                            image: imageClip.image,
                            duration: imageClip.duration,
                            preset: preset,
                            audioURL: audioURL,
                            to: outputURL
                        )
                        continuation.yield(ExportProgress(fractionCompleted: 1.0, estimatedTimeRemaining: 0))
                        continuation.finish()
                        return
                    }

                    // Multi-clip path
                    let result = try await CompositionBuilder.build(
                        from: clips,
                        audioTracks: audioTracks,
                        preset: preset,
                        cropRect: crop?.resolved(in: preset.resolution),
                        multiInputCompositor: multiInputCompositor
                    )

                    let stream = ExportEngine.export(
                        composition: result.composition,
                        audioMix: result.audioMix,
                        videoComposition: result.videoComposition,
                        overlays: overlays,
                        crop: crop,
                        preset: preset,
                        to: outputURL,
                        cancellationToken: token
                    )

                    for try await progress in stream {
                        continuation.yield(progress)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Cancel the in-flight export. Safe to call from any thread. The ``run()`` stream
    /// will throw ``KadrError/cancelled``. No effect if the export already finished.
    public func cancel() {
        cancellationToken.cancel()
    }
}
