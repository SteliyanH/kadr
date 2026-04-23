import Foundation
import CoreMedia

public struct Video: Sendable {
    internal let clips: [any Clip]
    internal let audioTracks: [AudioTrack]
    internal let preset: Preset

    public init(@VideoBuilder _ content: () -> [any Clip]) {
        self.clips = content()
        self.audioTracks = []
        self.preset = .auto
    }

    internal init(clips: [any Clip], audioTracks: [AudioTrack], preset: Preset) {
        self.clips = clips
        self.audioTracks = audioTracks
        self.preset = preset
    }

    public func audio(@AudioBuilder _ tracks: () -> [AudioTrack]) -> Video {
        Video(clips: clips, audioTracks: audioTracks + tracks(), preset: preset)
    }

    public func audio(url: URL) -> Video {
        Video(clips: clips, audioTracks: audioTracks + [AudioTrack(url: url)], preset: preset)
    }

    public func preset(_ preset: Preset) -> Video {
        Video(clips: clips, audioTracks: audioTracks, preset: preset)
    }

    public var duration: CMTime {
        clips.reduce(CMTime.zero) { result, clip in
            CMTimeAdd(result, clip.duration)
        }
    }

    public func export(to url: URL) async throws -> URL {
        guard !clips.isEmpty else {
            throw KadrError.noClipsProvided
        }

        // Check for transitions — not yet implemented
        if clips.contains(where: { $0 is Transition }) {
            throw KadrError.notYetImplemented("Transitions arrive in v0.2")
        }

        // Fast path: single ImageClip
        if clips.count == 1, let imageClip = clips.first as? ImageClip {
            let audioURL = imageClip.audioURL ?? audioTracks.first?.url
            return try await ImageEncoder.encode(
                image: imageClip.image,
                duration: imageClip.duration,
                preset: preset,
                audioURL: audioURL,
                to: url
            )
        }

        // Multi-clip path: CompositionBuilder → ExportEngine
        let result = try await CompositionBuilder.build(
            from: clips,
            audioTracks: audioTracks,
            preset: preset
        )

        let stream = ExportEngine.export(
            composition: result.composition,
            audioMix: result.audioMix,
            preset: preset,
            to: url
        )

        // Consume the stream to completion
        for try await _ in stream {}

        return url
    }

    public func exporter(to url: URL) -> Exporter {
        Exporter(clips: clips, audioTracks: audioTracks, preset: preset, outputURL: url)
    }
}
