import Foundation

public final class Exporter: Sendable {
    internal let clips: [any Clip]
    internal let audioTracks: [AudioTrack]
    internal let preset: Preset
    internal let outputURL: URL

    internal init(clips: [any Clip], audioTracks: [AudioTrack], preset: Preset, outputURL: URL) {
        self.clips = clips
        self.audioTracks = audioTracks
        self.preset = preset
        self.outputURL = outputURL
    }

    public func run() -> AsyncThrowingStream<ExportProgress, Error> {
        fatalError("Not yet implemented")
    }

    public func cancel() {
        fatalError("Not yet implemented")
    }
}
