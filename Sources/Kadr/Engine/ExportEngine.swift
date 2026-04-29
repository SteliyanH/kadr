import AVFoundation
import CoreMedia

/// Wraps non-Sendable AVFoundation types for safe transfer across concurrency boundaries.
/// These are only accessed within a single Task body — no concurrent access occurs.
private struct ExportConfig: @unchecked Sendable {
    let composition: AVMutableComposition
    let audioMix: AVMutableAudioMix?
    let videoComposition: AVMutableVideoComposition?
    let overlays: [any Overlay]
    let crop: CropRegion?
    let preset: Preset
    let captions: [Caption]
    let outputURL: URL
    let cancellationToken: CancellationToken
}

internal enum ExportEngine {

    static func export(
        composition: AVMutableComposition,
        audioMix: AVMutableAudioMix?,
        videoComposition: AVMutableVideoComposition? = nil,
        overlays: [any Overlay] = [],
        crop: CropRegion? = nil,
        preset: Preset,
        captions: [Caption] = [],
        to outputURL: URL,
        cancellationToken: CancellationToken = CancellationToken()
    ) -> AsyncThrowingStream<ExportProgress, Error> {
        let config = ExportConfig(
            composition: composition,
            audioMix: audioMix,
            videoComposition: videoComposition,
            overlays: overlays,
            crop: crop,
            preset: preset,
            captions: captions,
            outputURL: outputURL,
            cancellationToken: cancellationToken
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    if config.cancellationToken.isCancelled {
                        throw KadrError.cancelled
                    }

                    try? FileManager.default.removeItem(at: config.outputURL)

                    // Try preferred preset first, fall back to passthrough if incompatible
                    let preferredPreset = exportPresetName(for: config.preset)
                    let compatible = await AVAssetExportSession.compatibility(
                        ofExportPreset: preferredPreset,
                        with: config.composition,
                        outputFileType: .mp4
                    )
                    let presetName = compatible ? preferredPreset : AVAssetExportPresetPassthrough

                    guard let exportSession = AVAssetExportSession(asset: config.composition, presetName: presetName) else {
                        throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]))
                    }

                    config.cancellationToken.register(exportSession)

                    exportSession.outputURL = config.outputURL
                    exportSession.outputFileType = .mp4
                    exportSession.audioMix = config.audioMix
                    // Preserve audio pitch when clips are time-scaled by .speed(_:)
                    exportSession.audioTimePitchAlgorithm = .spectral

                    // v0.9.2 — bake captions as AVMetadataItem group.
                    if !config.captions.isEmpty {
                        exportSession.metadata = config.captions.map { $0.makeMetadataItem() }
                    }

                    // Apply video composition to enforce preset resolution/frame rate
                    // (only when using a non-passthrough preset that supports re-encoding)
                    if compatible, presetName != AVAssetExportPresetPassthrough {
                        let cropRect = config.crop?.resolved(in: config.preset.resolution)
                        let baseComposition: AVMutableVideoComposition?
                        if let provided = config.videoComposition {
                            // Already built by CompositionBuilder (transitions path) — that
                            // builder received cropRect and applied it to its instructions.
                            baseComposition = provided
                        } else {
                            // Simple path — build with crop applied here. Shared with the
                            // preview/thumbnail pipeline so both consumers use identical math.
                            baseComposition = PlaybackComposer.buildSimpleVideoComposition(
                                for: config.composition,
                                preset: config.preset,
                                cropRect: cropRect
                            )
                        }

                        if let videoComposition = baseComposition {
                            // If overlays were provided, attach a CALayer animation tool.
                            // The CALayer tree must be built fresh per export — AVFoundation
                            // takes ownership and an instance can't be shared.
                            // When crop is set, overlays render in the cropped (post-crop)
                            // render space, so the parent layer matches the cropped renderSize.
                            if !config.overlays.isEmpty {
                                let renderSize = cropRect?.size ?? config.preset.resolution
                                let tree = OverlayRenderer.buildLayerTree(
                                    overlays: config.overlays,
                                    renderSize: renderSize,
                                    compositionDuration: config.composition.duration
                                )
                                videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                                    postProcessingAsVideoLayer: tree.videoLayer,
                                    in: tree.parent
                                )
                            }
                            exportSession.videoComposition = videoComposition
                        }
                    }

                    let startTime = Date()
                    continuation.yield(ExportProgress(fractionCompleted: 0))

                    exportSession.exportAsynchronously { }

                    // Poll progress
                    while exportSession.status == .waiting || exportSession.status == .exporting {
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        let progress = Double(exportSession.progress)
                        let estimated = estimateTimeRemaining(progress: progress, startTime: startTime)
                        continuation.yield(ExportProgress(fractionCompleted: progress, estimatedTimeRemaining: estimated))
                    }

                    switch exportSession.status {
                    case .completed:
                        continuation.yield(ExportProgress(fractionCompleted: 1.0, estimatedTimeRemaining: 0))
                        continuation.finish()
                    case .cancelled:
                        continuation.finish(throwing: KadrError.cancelled)
                    case .failed:
                        continuation.finish(throwing: KadrError.exportFailed(underlying: exportSession.error ?? NSError(domain: "Kadr", code: -1)))
                    default:
                        continuation.finish(throwing: KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown export status: \(exportSession.status.rawValue)"])))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func estimateTimeRemaining(progress: Double, startTime: Date) -> TimeInterval? {
        guard progress > 0.05 else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        return elapsed / progress * (1.0 - progress)
    }

    private static func exportPresetName(for preset: Preset) -> String {
        switch preset.codec {
        case .hevc:
            return AVAssetExportPresetHEVCHighestQuality
        case .h264:
            return AVAssetExportPresetHighestQuality
        }
    }
}
