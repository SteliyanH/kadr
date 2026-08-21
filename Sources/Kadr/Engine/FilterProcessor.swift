import AVFoundation
import CoreImage

/// Pre-renders a video file with a chain of `CIFilter`s plus user-supplied
/// ``Compositor``s applied per frame, then writes the result to a temporary `mp4`.
/// The main composition then consumes that temp file like any other source clip.
///
/// This pre-render approach mirrors ``ReverseProcessor`` and trades an extra
/// encode/decode pass for engine simplicity. Order of operations:
///   1. ``Filter``s in declaration order (predictable color ops)
///   2. ``Compositor``s in declaration order (arbitrary user code)
///
/// Both run inside the same `applyingCIFiltersWithHandler` per-frame closure, so the
/// pipeline pays for one extra encode/decode pass total even when both filters and
/// compositors are set on the same clip.
internal enum FilterProcessor {

    static func apply(
        filters: [Filter],
        filterAnimations: [Animation<Double>?] = [],
        trimStart: CMTime = .zero,
        compositors: [any Compositor] = [],
        to url: URL
    ) async throws -> URL {
        guard !filters.isEmpty || !compositors.isEmpty else { return url }

        // Pad / truncate filterAnimations to match filters length defensively (callers
        // should already match, but the engine doesn't crash if they're off).
        var animations = filterAnimations
        while animations.count < filters.count { animations.append(nil) }
        if animations.count > filters.count {
            animations = Array(animations.prefix(filters.count))
        }
        let hasAnyAnimation = animations.contains(where: { $0 != nil })

        let asset = AVURLAsset(url: url)

        // AVMutableVideoComposition.videoComposition(withAsset:applyingCIFiltersWithHandler:)
        // is the Apple-blessed CIFilter-per-frame path. The handler runs for each
        // composition request; we apply each Kadr Filter in order, then each Compositor.
        // For v0.8.2 filter intensity animations, we sample each animated filter's
        // scalar at clip-relative time (request.compositionTime - trimStart) and
        // rebuild the filter via Filter.withScalar(_:) before applying.
        let videoComposition = try await AVMutableVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                var image = request.sourceImage
                let clipRelativeTime = hasAnyAnimation
                    ? CMTimeSubtract(request.compositionTime, trimStart)
                    : request.compositionTime
                for (i, filter) in filters.enumerated() {
                    if let anim = animations[i],
                       let scalar = anim.value(at: clipRelativeTime) {
                        image = filter.withScalar(scalar).apply(to: image)
                    } else {
                        image = filter.apply(to: image)
                    }
                }
                if !compositors.isEmpty {
                    let context = CompositorContext(
                        time: request.compositionTime,
                        renderSize: request.renderSize
                    )
                    for compositor in compositors {
                        image = compositor.process(image: image, context: context)
                    }
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
