/// Result builder for ``Video/audio(_:)``'s closure form. Lets you list multiple
/// ``AudioTrack``s — each with its own volume, fades, and ducking. You generally don't
/// reference this type directly — the compiler invokes it for you when you write
/// `.audio { AudioTrack(url: ...) }`.
@resultBuilder
public enum AudioBuilder {
    public static func buildBlock(_ tracks: AudioTrack...) -> [AudioTrack] {
        Array(tracks)
    }
}
