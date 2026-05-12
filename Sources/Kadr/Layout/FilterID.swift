import Foundation

/// Stable identifier for a `Filter` slot on a `VideoClip`.
///
/// **Why this exists.** Pre-v0.11, `VideoClip.filterAnimations: [Animation<Double>?]`
/// was a parallel-index array against `VideoClip.filters: [Filter]`. Any
/// consumer that reordered or deleted a filter without rotating the
/// animation array in lockstep silently re-mapped animations to the wrong
/// filters — a silent bug that the type system couldn't catch.
///
/// v0.11 adds ``VideoClip/filterIDs`` as a parallel-array of `FilterID`
/// values auto-generated when each filter is added. Animations are still
/// stored by index for back-compat, but a new keyed API
/// (``VideoClip/filterAnimation(for:)`` / ``VideoClip/setFilter(for:_:)``)
/// lets consumers mutate filters and their animations together by id —
/// preserving identity across modifier rebuilds.
///
/// IDs are typically auto-generated (UUID strings under the hood). Consumers
/// who want stable explicit ids can supply their own via ``init(_:)``;
/// otherwise treat them as opaque tokens.
///
/// Mirrors ``ClipID`` and ``LayerID`` in shape.
public struct FilterID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {

    /// The wrapped string identifier.
    public let rawValue: String

    /// Build a `FilterID` from an explicit string.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Build a `FilterID` from a string literal — `let id: FilterID = "vignette-A"`.
    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// Generate a fresh `FilterID`. Used by ``VideoClip/filter(_:)`` to tag
    /// every newly-added filter so animations can bind to it later. UUID-
    /// backed; never collides in practice.
    public static func generate() -> FilterID {
        FilterID(UUID().uuidString)
    }

    public var description: String { rawValue }
}
