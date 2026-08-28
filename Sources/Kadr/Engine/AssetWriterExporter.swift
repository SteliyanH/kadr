import AVFoundation
import CoreMedia
import Foundation

/// Export via `AVAssetReader` / `AVAssetWriter`, for compositions that ask for a
/// specific bitrate.
///
/// **Why this exists alongside `ExportEngine`.** `AVAssetExportSession` cannot
/// express a bitrate at all — its presets are the entire vocabulary, and the most
/// specific thing they say is "highest quality". "Export this under 25 MB for
/// upload" is not a preset, so it needs a pipeline that writes the samples itself.
///
/// **What it deliberately does not do.** `AVVideoCompositionCoreAnimationTool` is an
/// export-session facility; a reader/writer pipeline cannot use it. Overlays are
/// rendered through that tool, so overlay-bearing compositions stay on the session
/// path — see `ExportEngine.shouldUseWriter(...)`. Silently dropping overlays to
/// gain bitrate control would be a far worse trade than not having bitrate control.
private struct WriterConfig: @unchecked Sendable {
    let composition: AVMutableComposition
    let audioMix: AVMutableAudioMix?
    let videoComposition: AVMutableVideoComposition?
    let preset: Preset
    let bitrate: Int
    let captions: [Caption]
    let outputURL: URL
    let cancellationToken: CancellationToken
}

/// A reader output and the writer input it feeds. `@unchecked Sendable` for the
/// same reason `WriterConfig` is: AVFoundation's types are not `Sendable`, and each
/// pair is touched by exactly one pump on exactly one queue.
private struct PumpPair: @unchecked Sendable {
    let input: AVAssetWriterInput
    let output: AVAssetReaderOutput
}

/// Progress that several queues report into. The video pump is the only writer
/// today, but the throttle state has to live somewhere that is safe to touch from a
/// dispatch queue rather than captured as a `var` in the task body.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReported = 0.0

    /// True when `fraction` is at least one percentage point past the last report.
    func shouldReport(_ fraction: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard fraction - lastReported >= 0.01 else { return false }
        lastReported = fraction
        return true
    }
}

internal enum AssetWriterExporter {

    static func export(
        composition: AVMutableComposition,
        audioMix: AVMutableAudioMix?,
        videoComposition: AVMutableVideoComposition?,
        preset: Preset,
        bitrate: Int,
        captions: [Caption] = [],
        to outputURL: URL,
        cancellationToken: CancellationToken = CancellationToken()
    ) -> AsyncThrowingStream<ExportProgress, Error> {
        let config = WriterConfig(
            composition: composition,
            audioMix: audioMix,
            videoComposition: videoComposition,
            preset: preset,
            bitrate: bitrate,
            captions: captions,
            outputURL: outputURL,
            cancellationToken: cancellationToken
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    if config.cancellationToken.isCancelled { throw KadrError.cancelled }
                    try? FileManager.default.removeItem(at: config.outputURL)

                    // AVAssetReader wants an immutable asset. Handing it the live
                    // AVMutableComposition fails at startReading with an opaque
                    // -11800/-12710, because the reader snapshots internally and the
                    // track objects it is given no longer belong to what it is reading.
                    let asset = config.composition
                    let duration = try await asset.load(.duration)
                    let videoTracks = try await asset.loadTracks(withMediaType: .video)
                    // The composition builders always create an audio track, even when
                    // nothing is inserted into it — a muted clip, or a composition with
                    // no audio at all, still leaves an empty track behind. Handing an
                    // empty track to AVAssetReaderAudioMixOutput makes startReading()
                    // fail, and the error names neither audio nor emptiness.
                    var audioTracks: [AVAssetTrack] = []
                    for track in try await asset.loadTracks(withMediaType: .audio) {
                        let range = try await track.load(.timeRange)
                        if range.duration.seconds > 0 { audioTracks.append(track) }
                    }

                    guard !videoTracks.isEmpty else {
                        throw KadrError.exportFailed(underlying: NSError(
                            domain: "Kadr", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "The composition has no video track to encode."]
                        ))
                    }

                    let reader = try AVAssetReader(asset: asset)
                    let writer = try AVAssetWriter(outputURL: config.outputURL, fileType: .mp4)
                    // No AVAssetExportSession here, so the token gets a teardown
                    // closure instead. Without it a cancel during a stalled read would
                    // wait for the pump loop to notice, which it might never do if the
                    // writer input never asks for more data.
                    config.cancellationToken.onCancel { [weak reader, weak writer] in
                        reader?.cancelReading()
                        writer?.cancelWriting()
                    }

                    if !config.captions.isEmpty {
                        writer.metadata = config.captions.map { $0.makeMetadataItem() }
                    }

                    // ---- video ----
                    let renderSize = config.videoComposition?.renderSize ?? config.preset.resolution
                    let videoOutput = AVAssetReaderVideoCompositionOutput(
                        videoTracks: videoTracks,
                        videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    )
                    videoOutput.alwaysCopiesSampleData = false
                    // The videoComposition is what enforces preset resolution, frame rate
                    // and crop. Without it the reader would hand back source-sized frames
                    // and the preset would silently stop meaning anything.
                    let composed = config.videoComposition
                        ?? PlaybackComposer.buildSimpleVideoComposition(for: config.composition, preset: config.preset, cropRect: nil)
                    guard let composed else {
                        throw KadrError.exportFailed(underlying: NSError(
                            domain: "Kadr", code: -8,
                            userInfo: [NSLocalizedDescriptionKey: "Could not build a video composition for the requested preset."]
                        ))
                    }
                    videoOutput.videoComposition = composed
                    guard reader.canAdd(videoOutput) else {
                        throw KadrError.exportFailed(underlying: NSError(
                            domain: "Kadr", code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Could not read the composition's video for re-encoding."]
                        ))
                    }
                    reader.add(videoOutput)

                    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                        AVVideoCodecKey: codecKey(for: config.preset),
                        AVVideoWidthKey: Int(renderSize.width),
                        AVVideoHeightKey: Int(renderSize.height),
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: config.bitrate,
                        ],
                    ])
                    videoInput.expectsMediaDataInRealTime = false
                    guard writer.canAdd(videoInput) else {
                        throw KadrError.exportFailed(underlying: NSError(
                            domain: "Kadr", code: -4,
                            userInfo: [NSLocalizedDescriptionKey: "Could not configure the video encoder at the requested bitrate."]
                        ))
                    }
                    writer.add(videoInput)

                    // ---- audio (optional) ----
                    var audioOutput: AVAssetReaderAudioMixOutput?
                    var audioInput: AVAssetWriterInput?
                    if !audioTracks.isEmpty {
                        // Every one of these keys is required. Omitting the sample
                        // rate and channel count made `reader.startReading()` fail with
                        // an opaque -11800 / -12710 — an error that names neither audio
                        // nor the missing keys, and which looks exactly like a video
                        // problem because the video output is the one you added first.
                        let out = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                            AVFormatIDKey: kAudioFormatLinearPCM,
                            AVSampleRateKey: 44_100,
                            AVNumberOfChannelsKey: 2,
                            AVLinearPCMBitDepthKey: 16,
                            AVLinearPCMIsFloatKey: false,
                            AVLinearPCMIsBigEndianKey: false,
                            AVLinearPCMIsNonInterleaved: false,
                        ])
                        out.audioMix = config.audioMix
                        if reader.canAdd(out) {
                            reader.add(out)
                            audioOutput = out

                            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                                AVFormatIDKey: kAudioFormatMPEG4AAC,
                                AVNumberOfChannelsKey: 2,
                                AVSampleRateKey: 44_100,
                                AVEncoderBitRateKey: ExportQuality.assumedAudioBitrate,
                            ])
                            input.expectsMediaDataInRealTime = false
                            if writer.canAdd(input) {
                                writer.add(input)
                                audioInput = input
                            }
                        }
                    }

                    guard reader.startReading() else {
                        throw KadrError.exportFailed(underlying: NSError(
                            domain: "Kadr", code: -5,
                            userInfo: [
                                NSLocalizedDescriptionKey: "The composition could not be read for re-encoding.",
                                NSUnderlyingErrorKey: reader.error as NSError? as Any,
                            ].compactMapValues { $0 }
                        ))
                    }
                    guard writer.startWriting() else {
                        throw KadrError.exportFailed(underlying: NSError(
                            domain: "Kadr", code: -6,
                            userInfo: [
                                NSLocalizedDescriptionKey: "The encoder rejected the requested output settings.",
                                NSUnderlyingErrorKey: writer.error as NSError? as Any,
                            ].compactMapValues { $0 }
                        ))
                    }
                    writer.startSession(atSourceTime: .zero)

                    let startTime = Date()
                    continuation.yield(ExportProgress(fractionCompleted: 0))

                    let totalSeconds = duration.seconds

                    // Video and audio are pumped on their own queues; both must drain
                    // before the file is finalised.
                    let throttle = ProgressThrottle()
                    let videoPair = PumpPair(input: videoInput, output: videoOutput)
                    let audioPair = audioInput.flatMap { i in audioOutput.map { PumpPair(input: i, output: $0) } }

                    async let videoDone: Void = pump(
                        videoPair, label: "video", token: config.cancellationToken
                    ) { presentationTime in
                        guard totalSeconds > 0 else { return }
                        let fraction = min(1.0, presentationTime / totalSeconds)
                        guard throttle.shouldReport(fraction) else { return }
                        continuation.yield(ExportProgress(
                            fractionCompleted: fraction,
                            estimatedTimeRemaining: estimateTimeRemaining(progress: fraction, startTime: startTime)
                        ))
                    }
                    async let audioDone: Void = pumpOptional(audioPair, token: config.cancellationToken)
                    _ = try await (videoDone, audioDone)

                    if config.cancellationToken.isCancelled {
                        writer.cancelWriting()
                        reader.cancelReading()
                        throw KadrError.cancelled
                    }

                    await writer.finishWriting()

                    // A reader failure surfaces here as a writer failure with an
                    // opaque code, so report the reader's error when it has one —
                    // otherwise every composition problem reads as an encoder problem.
                    if reader.status == .failed, let readerError = reader.error {
                        continuation.finish(throwing: KadrError.exportFailed(underlying: readerError))
                        return
                    }

                    switch writer.status {
                    case .completed:
                        continuation.yield(ExportProgress(fractionCompleted: 1.0, estimatedTimeRemaining: 0))
                        continuation.finish()
                    case .cancelled:
                        continuation.finish(throwing: KadrError.cancelled)
                    default:
                        continuation.finish(throwing: KadrError.exportFailed(
                            underlying: writer.error ?? reader.error ?? NSError(domain: "Kadr", code: -7)
                        ))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Sample pumping

    /// Feed every sample from `output` into `input`, reporting each sample's
    /// presentation time. Returns when the output is drained.
    private static func pump(
        _ pair: PumpPair,
        label: String,
        token: CancellationToken,
        onSample: @escaping @Sendable (Double) -> Void
    ) async throws {
        let queue = DispatchQueue(label: "com.kadr.export.\(label)")
        // AVAssetWriterInput and AVAssetReaderOutput are NS_SWIFT_NONSENDABLE,
        // and the block below is @Sendable. Safe here because both are touched
        // only from inside that block, which `requestMediaDataWhenReady` runs
        // serially on `queue` and nowhere else — the confinement the compiler
        // cannot see.
        nonisolated(unsafe) let input = pair.input
        nonisolated(unsafe) let output = pair.output
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if token.isCancelled {
                        input.markAsFinished()
                        cont.resume()
                        return
                    }
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        cont.resume()
                        return
                    }
                    onSample(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                    if !input.append(sample) {
                        input.markAsFinished()
                        cont.resume()
                        return
                    }
                }
            }
        }
    }

    private static func pumpOptional(_ pair: PumpPair?, token: CancellationToken) async throws {
        guard let pair else { return }
        try await pump(pair, label: "audio", token: token) { _ in }
    }

    // MARK: - Helpers

    private static func codecKey(for preset: Preset) -> AVVideoCodecType {
        switch preset.codec {
        case .hevc: return .hevc
        case .h264: return .h264
        }
    }

    private static func estimateTimeRemaining(progress: Double, startTime: Date) -> TimeInterval? {
        guard progress > 0.05 else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        return elapsed / progress * (1.0 - progress)
    }
}
