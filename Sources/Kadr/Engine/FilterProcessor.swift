import AVFoundation
import CoreImage

/// Pre-renders a video file with a chain of `CIFilter`s applied per frame, then writes
/// the result to a temporary `mp4`. The main composition then consumes that temp file
/// like any other source clip.
///
/// This pre-render approach mirrors ``ReverseProcessor`` and trades an extra
/// encode/decode pass for engine simplicity — we don't need a custom
/// `AVVideoCompositing` (deferred to v0.5's "custom compositors" feature).
internal enum FilterProcessor {

    static func apply(filters: [Filter], to url: URL) async throws -> URL {
        guard !filters.isEmpty else { return url }

        let asset = AVURLAsset(url: url)

        // AVMutableVideoComposition.videoComposition(withAsset:applyingCIFiltersWithHandler:)
        // is the Apple-blessed CIFilter-per-frame path. The handler runs for each
        // composition request; we apply each Kadr Filter in order to the source CIImage.
        let videoComposition = try await AVMutableVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                var image = request.sourceImage
                for filter in filters {
                    image = filter.apply(to: image)
                }
                request.finish(with: image, context: nil)
            }
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create filter export session"]))
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition

        await exportSession.export()

        if exportSession.status == .completed {
            return outputURL
        }
        throw KadrError.exportFailed(underlying: exportSession.error ?? NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Filter export failed: \(exportSession.status.rawValue)"]))
    }
}
