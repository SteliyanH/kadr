import Foundation

extension VideoClip {

    // MARK: - Keyed read surface

    /// Find the filter with the given ``FilterID``. `nil` if the id isn't
    /// in ``filterIDs``. Mirror of ``filterAnimation(for:)`` for the filter
    /// itself.
    ///
    /// Added in v0.11.
    public func filter(for id: FilterID) -> Filter? {
        guard let i = filterIDs.firstIndex(of: id) else { return nil }
        return filters[i]
    }

    /// Find the animation bound to the filter with the given ``FilterID``.
    /// `nil` if either the id isn't in ``filterIDs`` or no animation is
    /// bound to that slot.
    ///
    /// **Preferred over the index-based ``filterAnimations`` accessor** as
    /// of v0.11 — keyed lookup survives filter reorders / deletes that
    /// the parallel-index API would silently mis-handle. Added in v0.11.
    public func filterAnimation(for id: FilterID) -> Animation<Double>? {
        guard let i = filterIDs.firstIndex(of: id) else { return nil }
        return filterAnimations[i]
    }

    // MARK: - Keyed mutation surface

    /// Set the animation on the filter with the given ``FilterID``. Pass
    /// `nil` to clear. No-op when the id isn't in ``filterIDs`` — silent
    /// rather than throwing, matching the editor-consumer mental model
    /// where stale ids can race with concurrent removes.
    ///
    /// Replaces the index-based `filterAnimation(at:_:)` added in v0.10.1
    /// (removed in v0.14). Added in v0.11.
    public func filterAnimation(for id: FilterID, _ animation: Animation<Double>?) -> VideoClip {
        guard let i = filterIDs.firstIndex(of: id) else { return self }
        var newAnimations = filterAnimations
        newAnimations[i] = animation
        return with {
    $0.filterAnimations = newAnimations
}
    }

    /// Replace the filter with the given ``FilterID`` while preserving its
    /// identity (and any bound animation). No-op when the id isn't in
    /// ``filterIDs``.
    ///
    /// Consumers rebuilding a filter's scalar (e.g. via ``Filter/withScalar(_:)``
    /// after a slider edit) should use this instead of walking + re-adding
    /// every filter via ``filter(_:)``, which would re-issue every
    /// ``FilterID`` and orphan any bound animations.
    ///
    /// ```swift
    /// // Editor pattern: change brightness intensity without losing its animation
    /// let updated = clip.setFilter(for: brightnessID, .brightness(0.8))
    /// ```
    ///
    /// Added in v0.11.
    public func setFilter(for id: FilterID, _ filter: Filter) -> VideoClip {
        guard let i = filterIDs.firstIndex(of: id) else { return self }
        var newFilters = filters
        newFilters[i] = filter
        return with {
    $0.filters = newFilters
}
    }

    /// Remove the filter with the given ``FilterID``, along with any bound
    /// animation. No-op when the id isn't in ``filterIDs``.
    ///
    /// The neighboring filters keep their ``FilterID`` values — only the
    /// removed slot disappears. Animations on those neighbors continue
    /// to bind to the same filters.
    ///
    /// Added in v0.11.
    /// Move filters within the stack, preserving each one's ``FilterID`` and
    /// any animation bound to it.
    ///
    /// Filter order is render order, so moving one changes the picture — a blur
    /// before a vignette is not the same image as a vignette before a blur.
    ///
    /// ``filters``, ``filterIDs`` and ``filterAnimations`` are three parallel
    /// arrays, and that is exactly why this exists. Reordering them by hand
    /// means moving all three by the same offsets and then rebuilding the clip,
    /// which is seventeen lines that fail *silently* when they drift: the
    /// arrays stay the same length, so nothing complains, and an animation
    /// simply starts driving the wrong filter.
    ///
    /// ```swift
    /// // Honouring KadrUI's `onFilterMove` callback:
    /// clip.moveFilters(fromOffsets: from, toOffset: to)
    /// ```
    ///
    /// Offsets follow the same convention as `Array.move(fromOffsets:toOffset:)`
    /// and SwiftUI's `onMove`, so a callback's values pass straight through.
    ///
    /// Added in v1.1.
    public func moveFilters(fromOffsets source: IndexSet, toOffset destination: Int) -> VideoClip {
        guard !source.isEmpty,
              source.allSatisfy({ $0 >= 0 && $0 < filters.count }),
              destination >= 0, destination <= filters.count
        else { return self }

        return with {
            $0.filters = VideoClip.moving(filters, from: source, to: destination)
            $0.filterIDs = VideoClip.moving(filterIDs, from: source, to: destination)
            $0.filterAnimations = VideoClip.moving(filterAnimations, from: source, to: destination)
        }
    }

    /// `Array.move(fromOffsets:toOffset:)` without SwiftUI.
    ///
    /// That method is a SwiftUI extension, and kadr core deliberately does not
    /// import SwiftUI — a headless consumer should not have to, to trim a clip.
    /// The semantics are matched exactly so a value from an `onMove` callback
    /// passes straight through: `destination` is an index into the array
    /// *before* anything is removed.
    nonisolated static func moving<T>(_ array: [T], from source: IndexSet, to destination: Int) -> [T] {
        let moving = source.sorted().map { array[$0] }
        var result = array
        // Highest first, so an earlier removal does not shift a later index.
        for index in source.sorted(by: >) { result.remove(at: index) }
        // The destination slides down by however many removed items preceded it.
        let insertion = destination - source.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: max(0, min(insertion, result.count)))
        return result
    }

    public func removeFilter(for id: FilterID) -> VideoClip {
        guard let i = filterIDs.firstIndex(of: id) else { return self }
        var newFilters = filters
        var newIDs = filterIDs
        var newAnimations = filterAnimations
        newFilters.remove(at: i)
        newIDs.remove(at: i)
        newAnimations.remove(at: i)
        return with {
    $0.filters = newFilters
    $0.filterIDs = newIDs
    $0.filterAnimations = newAnimations
}
    }
}
