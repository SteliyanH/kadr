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
        // Frozen before it crosses into the CI handler below, which runs
        // concurrently per frame. Capturing the `var` itself is a data race the
        // compiler is right to warn about, even though nothing mutates it after
        // this point.
        let resolvedAnimations = animations

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
                    if let anim = resolvedAnimations[i],
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

        // H.264 has no alpha channel. Before 1.2 every pre-render was H.264, so a
        // chroma key's transparent pixels were written as black, and a keyed clip
        // over another clip showed black instead of the clip beneath. When a filter
        // can make pixels transparent, encode with alpha instead. Other filters keep
        // H.264, which is faster and smaller.
        let keepsAlpha = filters.contains { $0.producesTransparency }
        var lastError: Error?
        for presetName in presets(keepingAlpha: keepsAlpha) {
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
                continue
            }
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(keepsAlpha ? "mov" : "mp4")
            exportSession.outputURL = outputURL
            exportSession.outputFileType = keepsAlpha ? .mov : .mp4
            exportSession.videoComposition = videoComposition

            await exportSession.export()

            if exportSession.status == .completed {
                return outputURL
            }
            lastError = exportSession.error
            try? FileManager.default.removeItem(at: outputURL)
        }

        // No silent fallback to H.264 for a keyed clip: that is the black
        // background this code exists to prevent.
        let reason = keepsAlpha
            ? "No encoder on this device can keep the transparency a chroma key needs"
            : "Failed to create filter export session"
        throw KadrError.exportFailed(underlying: lastError ?? NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: reason]))
    }

    /// Export presets to try, in order.
    ///
    /// With alpha: HEVC with alpha first (every platform kadr supports, and
    /// hardware-encoded on Apple silicon), then ProRes 4444 where the SDK has it.
    static func presets(keepingAlpha: Bool) -> [String] {
        guard keepingAlpha else { return [AVAssetExportPresetHighestQuality] }
        #if os(macOS) || os(iOS)
        return [AVAssetExportPresetHEVCHighestQualityWithAlpha, AVAssetExportPresetAppleProRes4444LPCM]
        #else
        return [AVAssetExportPresetHEVCHighestQualityWithAlpha]
        #endif
    }
}
