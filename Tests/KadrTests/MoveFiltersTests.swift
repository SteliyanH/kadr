import Testing
import Foundation
import SwiftUI
// Plain import — reordering is something a client does, and the point of this
// modifier is that a client could not do it cleanly before.
import Kadr

/// Tests for `VideoClip.moveFilters(fromOffsets:toOffset:)`.
///
/// The semantics must match SwiftUI's `onMove`, because that is where the values
/// come from. Several of these compare against SwiftUI's own
/// `Array.move(fromOffsets:toOffset:)` rather than against hand-computed
/// expectations — kadr core cannot use it (no SwiftUI dependency), but a test
/// target can, which makes it an oracle rather than a reimplementation to trust.
struct MoveFiltersTests {

    private var clip: VideoClip {
        VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov"))
            .filter(.brightness(0.1), id: FilterID("a"))
            .filter(.contrast(1.2), id: FilterID("b"))
            .filter(.saturation(0.8), id: FilterID("c"))
            .filter(.sepia(intensity: 0.5), id: FilterID("d"))
    }

    private func ids(_ clip: VideoClip) -> [String] {
        clip.filterIDs.map(\.rawValue)
    }

    @Test("Moving one filter forward matches SwiftUI's semantics")
    func matchesSwiftUIForward() {
        var oracle = ["a", "b", "c", "d"]
        oracle.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(ids(clip.moveFilters(fromOffsets: IndexSet(integer: 0), toOffset: 3)) == oracle)
    }

    @Test("Moving one filter backward matches SwiftUI's semantics")
    func matchesSwiftUIBackward() {
        var oracle = ["a", "b", "c", "d"]
        oracle.move(fromOffsets: IndexSet(integer: 3), toOffset: 1)
        #expect(ids(clip.moveFilters(fromOffsets: IndexSet(integer: 3), toOffset: 1)) == oracle)
    }

    @Test("Every single-element move matches SwiftUI, at every destination")
    func matchesSwiftUIExhaustively() {
        for from in 0..<4 {
            for to in 0...4 {
                var oracle = ["a", "b", "c", "d"]
                oracle.move(fromOffsets: IndexSet(integer: from), toOffset: to)
                let moved = clip.moveFilters(fromOffsets: IndexSet(integer: from), toOffset: to)
                #expect(ids(moved) == oracle, "from \(from) to \(to)")
            }
        }
    }

    @Test("A multi-element move matches SwiftUI too")
    func matchesSwiftUIForMultiple() {
        var oracle = ["a", "b", "c", "d"]
        oracle.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        #expect(ids(clip.moveFilters(fromOffsets: IndexSet([0, 2]), toOffset: 4)) == oracle)
    }

    // MARK: - The three arrays stay aligned

    @Test("Filters, ids and animations all move together")
    func parallelArraysStayAligned() {
        let animated = VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov"))
            .filter(.brightness(0.1), id: FilterID("a"))
            .filter(.sepia(intensity: 0), id: FilterID("b"),
                    animation: .keyframes([.at(0.0, value: 0), .at(1.0, value: 1)]))
            .filter(.contrast(1.2), id: FilterID("c"))

        let moved = animated.moveFilters(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        #expect(moved.filterIDs.map(\.rawValue) == ["b", "a", "c"])
        #expect(moved.filters.count == 3)
        #expect(moved.filterAnimations.count == 3)
        // The animation followed its filter to the front — the whole point.
        #expect(moved.filterAnimations[0] != nil)
        #expect(moved.filterAnimations[1] == nil)
        #expect(moved.filterAnimations[2] == nil)
        #expect(moved.filters[0].kind == .sepia)
    }

    @Test("Order is render order, so the filters themselves reorder too")
    func filtersReorderNotJustIDs() {
        let moved = clip.moveFilters(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(moved.filters.first?.kind == .sepia)
        #expect(moved.filterIDs.first == FilterID("d"))
    }

    // MARK: - Refusals

    @Test("An out-of-range source leaves the clip untouched")
    func outOfRangeSourceIsANoOp() {
        #expect(ids(clip.moveFilters(fromOffsets: IndexSet(integer: 9), toOffset: 0)) == ["a", "b", "c", "d"])
    }

    @Test("An out-of-range destination leaves the clip untouched")
    func outOfRangeDestinationIsANoOp() {
        #expect(ids(clip.moveFilters(fromOffsets: IndexSet(integer: 0), toOffset: 99)) == ["a", "b", "c", "d"])
    }

    @Test("An empty move is a no-op")
    func emptyMoveIsANoOp() {
        #expect(ids(clip.moveFilters(fromOffsets: IndexSet(), toOffset: 2)) == ["a", "b", "c", "d"])
    }

    @Test("Moving on a clip with no filters is a no-op, not a crash")
    func noFiltersIsANoOp() {
        let bare = VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov"))
        #expect(bare.moveFilters(fromOffsets: IndexSet(integer: 0), toOffset: 0).filters.isEmpty)
    }

    @Test("Nothing else about the clip changes")
    func onlyTheFilterStackMoves() {
        let source = clip.trimmed(to: 0...5).opacity(0.7).id(ClipID("hero"))
        let moved = source.moveFilters(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(moved.clipID == ClipID("hero"))
        #expect(moved.opacity == 0.7)
        #expect(moved.trimRange == source.trimRange)
    }
}
