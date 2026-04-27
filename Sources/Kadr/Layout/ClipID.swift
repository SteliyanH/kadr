import Foundation

/// Stable identifier for a clip in a composition.
///
/// IDs are user-supplied. Assign one with `.id(_:)` on any clip primitive (`VideoClip`,
/// `ImageClip`, `TitleSequence`) so callers like [`kadr-ui`](https://github.com/SteliyanH/kadr-ui)'s
/// `TimelineView` can route selection / reorder / trim interactions back to the right
/// clip — without relying on array indices, which break under reorder.
///
/// `ClipID` conforms to `ExpressibleByStringLiteral` so call sites read naturally:
///
/// ```swift
/// Video {
///     ImageClip(intro, duration: 2.0).id("intro")
///     Transition.dissolve(duration: 0.5)
///     VideoClip(url: clipURL).trimmed(to: 0...10).id("body")
/// }
/// ```
///
/// IDs must be **stable across recompositions** — picking a UUID at construction time
/// would change the ID every time the result-builder closure re-evaluates, breaking
/// any consumer that holds a reference. Pass an explicit string and you stay in control.
///
/// `Transition` deliberately doesn't carry a `ClipID` — it sits between media clips
/// and isn't an addressable unit. ``Clip/clipID-7m1ip`` returns `nil` for transitions.
public struct ClipID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The wrapped string identifier.
    public let rawValue: String

    /// Build a `ClipID` from an explicit string.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Build a `ClipID` from a string literal — `let id: ClipID = "intro"`.
    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}
