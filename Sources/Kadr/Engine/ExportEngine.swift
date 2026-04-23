import AVFoundation
import CoreMedia

/// Wraps non-Sendable AVFoundation types for safe transfer across concurrency boundaries.
/// These are only accessed within a single Task body — no concurrent access occurs.
private struct ExportConfig: @unchecked Sendable {
    let composition: AVMutableComposition
    let audioMix: AVMutableAudioMix?
    let presetName: String
    let outputURL: URL
    let cancellationToken: CancellationToken
}

internal enum ExportEngine {

    static func export(
        composition: AVMutableComposition,
        audioMix: AVMutableAudioMix?,
        preset: Preset,
        to outputURL: URL,
        cancellationToken: CancellationToken = CancellationToken()
    ) -> AsyncThrowingStream<ExportProgress, Error> {
        let config = ExportConfig(
            composition: composition,
            audioMix: audioMix,
            presetName: exportPresetName(for: preset),
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

                    guard let exportSession = AVAssetExportSession(asset: config.composition, presetName: config.presetName) else {
                        throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]))
                    }

                    config.cancellationToken.register(exportSession)

                    exportSession.outputURL = config.outputURL
                    exportSession.outputFileType = .mp4
                    exportSession.audioMix = config.audioMix

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
        // AVAssetExportPresetPassthrough avoids re-encoding and works with all input formats.
        // Sized presets (e.g. 1920x1080) can fail with -16976 on formats that don't support
        // the chosen decoder/encoder combination.
        return AVAssetExportPresetPassthrough
    }
}
