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

    /// Whether a composition can be encoded by the writer path.
    ///
    /// Two conditions, and the second is the interesting one.
    ///
    /// A bitrate must actually have been asked for — `.automatic` has nothing the
    /// session path cannot do, and routing it through a hand-written encoder would
    /// trade a well-tested code path for no gain.
    ///
    /// And there must be no overlays. Overlays are rendered by
    /// `AVVideoCompositionCoreAnimationTool`, which is an export-session facility —
    /// a reader/writer pipeline cannot use it. **An overlay-bearing composition sent
    /// down the writer path would export successfully with the overlays missing**,
    /// which is a far worse outcome than not honouring the bitrate. Until the writer
    /// path composites overlays itself, they pin the export to the session.
    static func shouldUseWriter(bitrate: Int?, overlays: [any Overlay]) -> Bool {
        bitrate != nil && overlays.isEmpty
    }

    /// What a passthrough export would drop, or `nil` when it would drop nothing the
    /// caller asked for.
    ///
    /// Passthrough copies source samples and cannot apply a video composition, so
    /// transitions, multi-track layout, clip transforms, crop and overlays all vanish
    /// while the export still reports success — the failure behind
    /// https://github.com/SteliyanH/kadr/issues/201. A composition with none of those
    /// still falls back: it loses the preset's resolution and codec, but its content
    /// is right.
    static func passthroughLoss(
        hasVideoComposition: Bool,
        hasOverlays: Bool = false,
        hasCrop: Bool = false
    ) -> String? {
        var lost: [String] = []
        if hasVideoComposition { lost.append("video composition (transitions, track layout, clip transforms)") }
        if hasOverlays { lost.append("overlays") }
        if hasCrop { lost.append("crop") }
        return lost.isEmpty ? nil : lost.joined(separator: ", ")
    }

    /// The error thrown instead of a passthrough export that would drop `lost`.
    static func incompatiblePresetError(presetName: String, lost: String) -> KadrError {
        KadrError.exportFailed(underlying: NSError(
            domain: "Kadr", code: -1,
            userInfo: [NSLocalizedDescriptionKey:
                "The \(presetName) export preset is not compatible with this composition, "
                + "and a passthrough copy would silently drop its \(lost)."]
        ))
    }

    static func export(
        composition: AVMutableComposition,
        audioMix: AVMutableAudioMix?,
        videoComposition: AVMutableVideoComposition? = nil,
        overlays: [any Overlay] = [],
        crop: CropRegion? = nil,
        preset: Preset,
        captions: [Caption] = [],
        quality: ExportQuality = .automatic,
        to outputURL: URL,
        cancellationToken: CancellationToken = CancellationToken()
    ) -> AsyncThrowingStream<ExportProgress, Error> {
        let requestedBitrate = quality.resolvedBitrate(forDuration: composition.duration)
        if shouldUseWriter(bitrate: requestedBitrate, overlays: overlays), let requestedBitrate {
            let cropRect = crop?.resolved(in: preset.resolution)
            return AssetWriterExporter.export(
                composition: composition,
                audioMix: audioMix,
                videoComposition: videoComposition
                    ?? PlaybackComposer.buildSimpleVideoComposition(for: composition, preset: preset, cropRect: cropRect),
                preset: preset,
                bitrate: requestedBitrate,
                captions: captions,
                to: outputURL,
                cancellationToken: cancellationToken
            )
        }

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

                    // Try the preferred preset first. Fall back to passthrough only when
                    // the copy would still be the movie that was asked for.
                    let preferredPreset = exportPresetName(for: config.preset)
                    let compatible = await AVAssetExportSession.compatibility(
                        ofExportPreset: preferredPreset,
                        with: config.composition,
                        outputFileType: .mp4
                    )
                    if !compatible, let lost = passthroughLoss(
                        hasVideoComposition: config.videoComposition != nil,
                        hasOverlays: !config.overlays.isEmpty,
                        hasCrop: config.crop != nil
                    ) {
                        throw incompatiblePresetError(presetName: preferredPreset, lost: lost)
                    }
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
                                avoidIdentityTransforms(in: videoComposition)
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

    /// The transform that stands in for identity under an animation tool: a shift of
    /// 1/1024 px, far below anything a resampler can show.
    static let identityStandIn = CGAffineTransform(translationX: 1.0 / 1024, y: 0)

    /// Replaces every identity transform in `videoComposition`'s layer instructions with
    /// ``identityStandIn``, including the implicit identity before a layer's first
    /// explicit transform. Opacity and crop ramps are left untouched.
    ///
    /// Works around an AVFoundation bug. When a layer instruction's transform is exactly
    /// identity and the source frame matches `renderSize`, AVFoundation hands the decoded
    /// frame straight to `AVVideoCompositionCoreAnimationTool`, and for some sizes the
    /// video layer then renders solid white — e.g. 320×320, 560×560 and 640×320 on macOS
    /// 27.0.1, while 600×600, 640×640 and 320×640 are fine. It reproduces with plain
    /// AVFoundation and no Kadr code. Any non-identity transform takes the regular
    /// compositing path, so the stand-in avoids it at no visible cost. Only applied when
    /// an animation tool is attached; without one, the identity fast path works.
    static func avoidIdentityTransforms(in videoComposition: AVMutableVideoComposition) {
        for case let instruction as AVMutableVideoCompositionInstruction in videoComposition.instructions {
            for case let layer as AVMutableVideoCompositionLayerInstruction in instruction.layerInstructions {
                replaceIdentityTransforms(in: layer)
            }
            // Reassign in case the composition copied the layer instructions on set.
            instruction.layerInstructions = instruction.layerInstructions
        }
        videoComposition.instructions = videoComposition.instructions
    }

    private static func replaceIdentityTransforms(in layer: AVMutableVideoCompositionLayerInstruction) {
        func standIn(_ t: CGAffineTransform) -> CGAffineTransform { t.isIdentity ? identityStandIn : t }

        // Collect first, then rewrite: setting a transform (or ramp) at an existing time
        // replaces that entry, so the rewrite keeps the same ramp layout.
        var ramps: [(start: CGAffineTransform, end: CGAffineTransform, range: CMTimeRange)] = []
        var time = CMTime.zero
        while ramps.count < 100_000 {
            var start = CGAffineTransform.identity, end = CGAffineTransform.identity
            var range = CMTimeRange.invalid
            guard layer.getTransformRamp(for: time, start: &start, end: &end, timeRange: &range),
                  range.isValid else { break }
            ramps.append((start, end, range))
            // A query returns the ramp at or after `time`; stop at the open-ended last one.
            guard range.end.isNumeric, CMTimeCompare(range.end, time) > 0 else { break }
            time = range.end
        }

        // Before the first explicit transform a layer is identity.
        if ramps.first.map({ CMTimeCompare($0.range.start, .zero) > 0 }) ?? true {
            layer.setTransform(identityStandIn, at: .zero)
        }
        for ramp in ramps where ramp.start.isIdentity || ramp.end.isIdentity {
            if ramp.start == ramp.end {
                layer.setTransform(standIn(ramp.start), at: ramp.range.start)
            } else {
                layer.setTransformRamp(fromStart: standIn(ramp.start), toEnd: standIn(ramp.end), timeRange: ramp.range)
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
