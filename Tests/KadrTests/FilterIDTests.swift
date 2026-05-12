import XCTest
@testable import Kadr

/// Tests for v0.11 Tier 3 — ``FilterID`` + keyed filter operations.
///
/// Pre-v0.11 `VideoClip.filterAnimations` was a parallel-index array
/// against `VideoClip.filters`. Reordering or deleting a filter without
/// rotating the animation array in lockstep silently re-mapped animations
/// to the wrong filters.
///
/// v0.11 adds ``VideoClip/filterIDs`` parallel to ``VideoClip/filters`` —
/// auto-generated on every ``VideoClip/filter(_:)`` call — and a keyed
/// API (``VideoClip/filterAnimation(for:_:)``, ``VideoClip/setFilter(for:_:)``,
/// ``VideoClip/removeFilter(for:)``) that survives reorders and deletes.
@MainActor
final class FilterIDTests: XCTestCase {

    private let url = URL(fileURLWithPath: "/tmp/filter-id-test.mov")

    // MARK: - FilterID basics

    func testFilterIDFromLiteralAndRawValue() {
        let a: FilterID = "vignette-A"
        let b = FilterID("vignette-A")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.rawValue, "vignette-A")
        XCTAssertEqual(a.description, "vignette-A")
    }

    func testGenerateReturnsUniqueIDs() {
        let a = FilterID.generate()
        let b = FilterID.generate()
        XCTAssertNotEqual(a, b)
    }

    // MARK: - filterIDs auto-generated and parallel to filters

    func testFreshClipHasEmptyFilterIDs() {
        let clip = VideoClip(url: url)
        XCTAssertTrue(clip.filters.isEmpty)
        XCTAssertTrue(clip.filterIDs.isEmpty)
    }

    func testFilterModifierAppendsToFiltersAndFilterIDs() {
        let clip = VideoClip(url: url)
            .filter(.brightness(0.2))
            .filter(.contrast(1.2))
        XCTAssertEqual(clip.filters.count, 2)
        XCTAssertEqual(clip.filterIDs.count, 2)
        XCTAssertNotEqual(clip.filterIDs[0], clip.filterIDs[1])
    }

    func testFilterIDsSurviveOtherModifierChains() {
        // Trim / id / opacity / transform / speed don't touch filters but
        // also can't drop filterIDs — they thread through every rebuild.
        let clip = VideoClip(url: url)
            .filter(.brightness(0.2))
            .trimmed(to: 0...4)
            .id(ClipID("c1"))
            .opacity(0.8)
            .speed(.flat(2.0))
        XCTAssertEqual(clip.filterIDs.count, 1)
    }

    // MARK: - filter(for:) lookup

    func testFilterForIDReturnsTheRightFilter() {
        let clip = VideoClip(url: url)
            .filter(.brightness(0.2))
            .filter(.contrast(1.2))
        let id0 = clip.filterIDs[0]
        let id1 = clip.filterIDs[1]
        if case .brightness(let b) = clip.filter(for: id0) {
            XCTAssertEqual(b, 0.2)
        } else { XCTFail("Expected .brightness for first id") }
        if case .contrast(let c) = clip.filter(for: id1) {
            XCTAssertEqual(c, 1.2)
        } else { XCTFail("Expected .contrast for second id") }
    }

    func testFilterForUnknownIDReturnsNil() {
        let clip = VideoClip(url: url).filter(.brightness(0.2))
        XCTAssertNil(clip.filter(for: FilterID("does-not-exist")))
    }

    // MARK: - filterAnimation(for:_:) keyed setter

    func testFilterAnimationForIDRoundTrips() {
        let clip = VideoClip(url: url).filter(.brightness(0.2))
        let id = clip.filterIDs[0]
        let curve = Animation<Double>.keyframes([.at(0.0, value: 0.0), .at(2.0, value: 1.0)], timing: .linear)
        let updated = clip.filterAnimation(for: id, curve)
        XCTAssertNotNil(updated.filterAnimation(for: id))
        XCTAssertNotNil(updated.filterAnimations[0])
    }

    func testFilterAnimationForIDClearsWithNil() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 0.5)], timing: .linear)
        let clip = VideoClip(url: url)
            .filter(.brightness(0.2))
        let id = clip.filterIDs[0]
        let withAnim = clip.filterAnimation(for: id, curve)
        XCTAssertNotNil(withAnim.filterAnimation(for: id))
        let cleared = withAnim.filterAnimation(for: id, nil)
        XCTAssertNil(cleared.filterAnimation(for: id))
    }

    func testFilterAnimationForUnknownIDIsNoOp() {
        let clip = VideoClip(url: url).filter(.brightness(0.2))
        let curve = Animation<Double>.keyframes([.at(0.0, value: 0.5)], timing: .linear)
        let result = clip.filterAnimation(for: FilterID("ghost"), curve)
        // No-op — clip unchanged. Existing animation slot stays nil.
        XCTAssertNil(result.filterAnimations[0])
    }

    // MARK: - setFilter(for:_:) preserves identity + animation

    /// Tier 3's headline use case: replace a filter's payload (e.g. change
    /// brightness intensity via a slider edit) without re-issuing
    /// ``FilterID`` — animations bound to that id survive intact.
    func testSetFilterPreservesFilterIDAndBoundAnimation() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 0.0), .at(2.0, value: 1.0)], timing: .linear)
        var clip = VideoClip(url: url).filter(.brightness(0.2))
        let id = clip.filterIDs[0]
        clip = clip.filterAnimation(for: id, curve)

        // Swap brightness intensity through setFilter.
        let updated = clip.setFilter(for: id, .brightness(0.9))

        // Filter scalar moved; id preserved; animation still bound.
        if case .brightness(let b) = updated.filter(for: id) {
            XCTAssertEqual(b, 0.9)
        } else { XCTFail("Expected updated brightness scalar") }
        XCTAssertEqual(updated.filterIDs, clip.filterIDs)
        XCTAssertNotNil(updated.filterAnimation(for: id))
    }

    func testSetFilterForUnknownIDIsNoOp() {
        let clip = VideoClip(url: url).filter(.brightness(0.2))
        let result = clip.setFilter(for: FilterID("ghost"), .contrast(1.5))
        XCTAssertEqual(result.filters.count, 1)
        if case .brightness = result.filters[0] {} else {
            XCTFail("Expected the original brightness filter to remain")
        }
    }

    // MARK: - removeFilter(for:) drops slot + animation

    func testRemoveFilterDropsTheSlotAndItsAnimation() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 0.5)], timing: .linear)
        var clip = VideoClip(url: url)
            .filter(.brightness(0.2))
            .filter(.contrast(1.2))
        let id0 = clip.filterIDs[0]
        let id1 = clip.filterIDs[1]
        clip = clip.filterAnimation(for: id0, curve)

        let result = clip.removeFilter(for: id0)
        XCTAssertEqual(result.filters.count, 1)
        XCTAssertEqual(result.filterIDs.count, 1)
        XCTAssertEqual(result.filterAnimations.count, 1)
        // Remaining filter is contrast; its id (id1) is unchanged.
        XCTAssertEqual(result.filterIDs[0], id1)
        if case .contrast = result.filters[0] {} else {
            XCTFail("Expected contrast to remain after removing brightness")
        }
    }

    func testRemoveFilterForUnknownIDIsNoOp() {
        let clip = VideoClip(url: url).filter(.brightness(0.2))
        let result = clip.removeFilter(for: FilterID("ghost"))
        XCTAssertEqual(result.filters.count, 1)
        XCTAssertEqual(result.filterIDs.count, 1)
    }
}
