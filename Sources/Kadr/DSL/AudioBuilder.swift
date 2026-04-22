@resultBuilder
public enum AudioBuilder {
    public static func buildBlock(_ tracks: AudioTrack...) -> [AudioTrack] {
        Array(tracks)
    }
}
