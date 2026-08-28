/// Result builder for ``Video/audio(_:)``'s closure form. Lets you list multiple
/// ``AudioTrack``s — each with its own volume, fades, and ducking — with control flow
/// (`if`, `for`, `switch`). You generally don't reference this type directly — the
/// compiler invokes it for you when you write `.audio { AudioTrack(url: ...) }`.
///
/// ```swift
/// let beds: [AudioTrack] = loadBeds()
/// Video { clip }
///     .audio {
///         for bed in beds { bed }
///         if includeVoiceover { AudioTrack(url: voiceoverURL) }
///     }
/// ```
@resultBuilder
public enum AudioBuilder {
    /// The empty block — `.audio { }`, or a loop that yielded nothing.
    public static func buildBlock() -> [AudioTrack] {
        []
    }

    public static func buildBlock(_ tracks: AudioTrack...) -> [AudioTrack] {
        Array(tracks)
    }

    public static func buildOptional(_ component: [AudioTrack]?) -> [AudioTrack] {
        component ?? []
    }

    public static func buildEither(first component: [AudioTrack]) -> [AudioTrack] {
        component
    }

    public static func buildEither(second component: [AudioTrack]) -> [AudioTrack] {
        component
    }

    public static func buildArray(_ components: [[AudioTrack]]) -> [AudioTrack] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: AudioTrack) -> [AudioTrack] {
        [expression]
    }

    public static func buildBlock(_ components: [AudioTrack]...) -> [AudioTrack] {
        components.flatMap { $0 }
    }
}
