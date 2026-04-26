import Foundation

/// Stable identifier for an overlay layer in a composition.
///
/// IDs are user-supplied. Assign one with `.id(_:)` on any overlay primitive (`Text`,
/// `Image`, `Sticker` — landing in v0.3.x) so that KadrUI (v0.4) can route gesture
/// handlers (`.onTap`, `.onDrag`) back to the right layer.
///
/// `LayerID` conforms to `ExpressibleByStringLiteral` so call sites read naturally:
///
/// ```swift
/// Image(logo)
///     .position(.topRight)
///     .id("watermark")            // string literal
///
/// // Later, in KadrUI:
/// VideoPreview(video)
///     .onTap("watermark") { ... }
/// ```
///
/// IDs must be **stable across recompositions** — picking a UUID at construction time
/// would change the ID every time the result-builder closure re-evaluates, breaking
/// hit-testing. Pass an explicit string and you stay in control.
public struct LayerID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}
