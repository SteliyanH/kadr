import AVFoundation
import CoreMedia

/// Wraps non-Sendable AVFoundation types for safe transfer across concurrency boundaries.
/// These are only accessed within a single Task body — no concurrent access occurs.
private struct ExportConfig: @unchecked Sendable {
    let composition: AVMutableComposition
    let audioMix: AVMutableAudioMix?
    let videoComposition: AVMutableVideoComposition?
    let overlays: [ImageOverlay]
    let preset: Preset
    let outputURL: URL
    let cancellationToken: CancellationToken
}

internal enum ExportEngine {

    static func export(
        composition: AVMutableComposition,
        audioMix: AVMutableAudioMix?,
        videoComposition: AVMutableVideoComposition? = nil,
        overlays: [ImageOverlay] = [],
        preset: Preset,
        to outputURL: URL,
        cancellationToken: CancellationToken = CancellationToken()
    ) -> AsyncThrowingStream<ExportProgress, Error> {
        let config = ExportConfig(
            composition: composition,
            audioMix: audioMix,
            videoComposition: videoComposition,
            overlays: overlays,
            preset: preset,
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

                    // Apply video composition to enforce preset resolution/frame rate
                    // (only when using a non-passthrough preset that supports re-encoding)
                    if compatible, presetName != AVAssetExportPresetPassthrough {
                        let baseComposition: AVMutableVideoComposition?
                        if let provided = config.videoComposition {
                            baseComposition = provided
                        } else {
                            baseComposition = buildVideoComposition(
                                for: config.composition,
                                preset: config.preset
                            )
                        }

                        if let videoComposition = baseComposition {
                            // If overlays were provided, attach a CALayer animation tool.
                            // The CALayer tree must be built fresh per export — AVFoundation
                            // takes ownership and an instance can't be shared.
                            if !config.overlays.isEmpty {
                                let tree = OverlayRenderer.buildLayerTree(
                                    overlays: config.overlays,
                                    renderSize: config.preset.resolution
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

    /// Builds an AVMutableVideoComposition that enforces the preset's resolution and frame rate.
    private static func buildVideoComposition(
        for composition: AVMutableComposition,
        preset: Preset
    ) -> AVMutableVideoComposition? {
        let videoTracks = composition.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = preset.resolution
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))

        // Create a single instruction spanning the full duration
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

        // Layer the first video track
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[0])

        // Scale video to fill the preset resolution
        let trackSize = videoTracks[0].naturalSize
        if trackSize.width > 0 && trackSize.height > 0 {
            let scaleX = preset.resolution.width / trackSize.width
            let scaleY = preset.resolution.height / trackSize.height
            let scale = max(scaleX, scaleY) // scale to fill
            let scaledWidth = trackSize.width * scale
            let scaledHeight = trackSize.height * scale
            let tx = (preset.resolution.width - scaledWidth) / 2
            let ty = (preset.resolution.height - scaledHeight) / 2
            let transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: tx / scale, y: ty / scale)
            layerInstruction.setTransform(transform, at: .zero)
        }

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        return videoComposition
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
