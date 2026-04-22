import Foundation
import AVFoundation

public final class Exporter: @unchecked Sendable {
    internal let clips: [any Clip]
    internal let audioTracks: [AudioTrack]
    internal let preset: Preset
    internal let outputURL: URL
    private var isCancelled = false

    internal init(clips: [any Clip], audioTracks: [AudioTrack], preset: Preset, outputURL: URL) {
        self.clips = clips
        self.audioTracks = audioTracks
        self.preset = preset
        self.outputURL = outputURL
    }

    public func run() -> AsyncThrowingStream<ExportProgress, Error> {
        AsyncThrowingStream { continuation in
            Task { [clips, audioTracks, preset, outputURL] in
                do {
                    guard !clips.isEmpty else {
                        throw KadrError.noClipsProvided
                    }

                    if clips.contains(where: { $0 is Transition }) {
                        throw KadrError.notYetImplemented("Transitions arrive in v0.2")
                    }

                    // Single ImageClip fast path
                    if clips.count == 1, let imageClip = clips.first as? ImageClip {
                        continuation.yield(ExportProgress(fractionCompleted: 0))
                        let audioURL = imageClip.audioURL ?? audioTracks.first?.url
                        _ = try await ImageEncoder.encode(
                            image: imageClip.image,
                            duration: imageClip.duration,
                            preset: preset,
                            audioURL: audioURL,
                            to: outputURL
                        )
                        continuation.yield(ExportProgress(fractionCompleted: 1.0))
                        continuation.finish()
                        return
                    }

                    // Multi-clip path
                    let result = try await CompositionBuilder.build(
                        from: clips,
                        audioTracks: audioTracks,
                        preset: preset
                    )

                    let stream = ExportEngine.export(
                        composition: result.composition,
                        audioMix: result.audioMix,
                        preset: preset,
                        to: outputURL
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

    public func cancel() {
        isCancelled = true
    }
}
