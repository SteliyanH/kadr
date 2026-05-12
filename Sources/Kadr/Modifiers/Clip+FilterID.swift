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
    /// Replaces the deprecated index-based ``filterAnimation(at:_:)``
    /// added in v0.10.1. Added in v0.11.
    public func filterAnimation(for id: FilterID, _ animation: Animation<Double>?) -> VideoClip {
        guard let i = filterIDs.firstIndex(of: id) else { return self }
        var newAnimations = filterAnimations
        newAnimations[i] = animation
        return VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: speedRate,
            filters: filters,
            filterIDs: filterIDs,
            filterAnimations: newAnimations,
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: opacityAnimation,
            speedCurve: speedCurve
        )
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
        return VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: speedRate,
            filters: newFilters,
            filterIDs: filterIDs,
            filterAnimations: filterAnimations,
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: opacityAnimation,
            speedCurve: speedCurve
        )
    }

    /// Remove the filter with the given ``FilterID``, along with any bound
    /// animation. No-op when the id isn't in ``filterIDs``.
    ///
    /// The neighboring filters keep their ``FilterID`` values — only the
    /// removed slot disappears. Animations on those neighbors continue
    /// to bind to the same filters.
    ///
    /// Added in v0.11.
    public func removeFilter(for id: FilterID) -> VideoClip {
        guard let i = filterIDs.firstIndex(of: id) else { return self }
        var newFilters = filters
        var newIDs = filterIDs
        var newAnimations = filterAnimations
        newFilters.remove(at: i)
        newIDs.remove(at: i)
        newAnimations.remove(at: i)
        return VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: speedRate,
            filters: newFilters,
            filterIDs: newIDs,
            filterAnimations: newAnimations,
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: opacityAnimation,
            speedCurve: speedCurve
        )
    }
}
