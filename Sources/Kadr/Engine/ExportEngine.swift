import AVFoundation
import CoreMedia

internal enum ExportEngine {

    static func export(
        composition: AVMutableComposition,
        audioMix: AVMutableAudioMix?,
        preset: Preset,
        to outputURL: URL
    ) -> AsyncThrowingStream<ExportProgress, Error> {
        let presetName = exportPresetName(for: preset)

        // Wrap non-Sendable AVFoundation types for safe transfer into the Task.
        // These values are only used within the single Task body — no concurrent access.
        nonisolated(unsafe) let composition = composition
        nonisolated(unsafe) let audioMix = audioMix

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try? FileManager.default.removeItem(at: outputURL)

                    guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
                        throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]))
                    }

                    exportSession.outputURL = outputURL
                    exportSession.outputFileType = .mp4
                    exportSession.audioMix = audioMix

                    continuation.yield(ExportProgress(fractionCompleted: 0))

                    exportSession.exportAsynchronously { }

                    // Poll progress
                    while exportSession.status == .waiting || exportSession.status == .exporting {
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        let progress = Double(exportSession.progress)
                        continuation.yield(ExportProgress(fractionCompleted: progress))
                    }

                    switch exportSession.status {
                    case .completed:
                        continuation.yield(ExportProgress(fractionCompleted: 1.0))
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

    private static func exportPresetName(for preset: Preset) -> String {
        // AVAssetExportPresetPassthrough avoids re-encoding and works with all input formats.
        // Sized presets (e.g. 1920x1080) can fail with -16976 on formats that don't support
        // the chosen decoder/encoder combination.
        return AVAssetExportPresetPassthrough
    }
}
