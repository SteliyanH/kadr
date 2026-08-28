import Testing
import Foundation
// Not `@testable` — the point is what a downstream module can reach. The
// internal memberwise init takes `filterIDs:` and is invisible from out here,
// which is exactly why this modifier had to exist.
import Kadr

/// Tests for `VideoClip.filter(_:id:animation:)`.
struct FilterIDRestorationTests {

    private var clip: VideoClip {
        VideoClip(url: URL(fileURLWithPath: "/tmp/clip.mov"))
    }

    @Test("A supplied id is used verbatim, not regenerated")
    func idIsPreserved() {
        let restored = clip.filter(.sepia(intensity: 0.4), id: FilterID("saved-A"))
        #expect(restored.filterIDs == [FilterID("saved-A")])
        #expect(restored.filters.count == 1)
    }

    @Test("Ids survive a full save/restore of several filters, in order")
    func severalIDsRoundTrip() {
        let original = clip
            .filter(.brightness(0.1))
            .filter(.contrast(1.2))
            .filter(.vignette(intensity: 0.5))
        let savedIDs = original.filterIDs
        let savedFilters = original.filters

        var restored = clip
        for (filter, id) in zip(savedFilters, savedIDs) {
            restored = restored.filter(filter, id: id)
        }
        #expect(restored.filterIDs == savedIDs)
        #expect(restored.filters == savedFilters)
    }

    @Test("An animation supplied alongside the id binds to that filter")
    func animationBindsUnderTheSuppliedID() {
        let animation = Animation<Double>.keyframes([.at(0.0, value: 0), .at(2.0, value: 1)])
        let restored = clip.filter(.sepia(intensity: 0), id: FilterID("fade"), animation: animation)
        #expect(restored.filterIDs == [FilterID("fade")])
        #expect(restored.filterAnimations.count == 1)
        #expect(restored.filterAnimations[0] != nil)
    }

    @Test("Omitting the animation leaves a nil in the parallel array, not a gap")
    func parallelArraysStayAligned() {
        let restored = clip
            .filter(.brightness(0.1), id: FilterID("a"))
            .filter(.contrast(1.2), id: FilterID("b"), animation: .keyframes([.at(0.0, value: 1)]))
            .filter(.mono, id: FilterID("c"))
        #expect(restored.filters.count == 3)
        #expect(restored.filterIDs == [FilterID("a"), FilterID("b"), FilterID("c")])
        #expect(restored.filterAnimations.count == 3)
        #expect(restored.filterAnimations[0] == nil)
        #expect(restored.filterAnimations[1] != nil)
        #expect(restored.filterAnimations[2] == nil)
    }

    @Test("Mixing generated and supplied ids does not disturb the generated ones")
    func mixingWithGeneratedIDs() {
        let mixed = clip
            .filter(.brightness(0.1))
            .filter(.contrast(1.2), id: FilterID("explicit"))
        #expect(mixed.filterIDs.count == 2)
        #expect(mixed.filterIDs[1] == FilterID("explicit"))
        #expect(mixed.filterIDs[0] != FilterID("explicit"))
    }
}
