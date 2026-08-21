import Kadr
import Foundation
import CoreMedia

/// v0.11 showcase — keyed filters.

// MARK: - Filters that survive reordering

/// Animate one filter's intensity, by identity rather than by index.
///
/// The problem `FilterID` solves: with index-based access, removing or
/// reordering a filter silently reassigns every animation bound after it — a
/// blur ramp becomes a saturation ramp and nothing reports an error. A keyed
/// animation stays attached to the filter it was written for.
func v110KeyedFilterAnimation() async throws {
    let source = URL(fileURLWithPath: "/tmp/shot.mov")
    let output = URL(fileURLWithPath: "/tmp/v110_keyed_filter.mp4")

    let blur = FilterID("blur")
    let vignette = FilterID("vignette")

    _ = try await Video {
        VideoClip(url: source)
            .trimmed(to: 0...6)
            .setFilter(for: blur, .gaussianBlur(radius: 0))
            .setFilter(for: vignette, .vignette(intensity: 0.4))
            // Ramp the blur out over the first two seconds. Bound to `blur`,
            // so inserting another filter above it changes nothing.
            .filterAnimation(for: blur, .keyframes([
                .at(0.0, value: 12.0),
                .at(2.0, value: 0.0)
            ]))
    }
    .export(to: output)
}

/// Removing a filter leaves the others' animations where they were.
func v110RemoveFilterSafely() {
    let blur = FilterID("blur")
    let vignette = FilterID("vignette")

    let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov"))
        .setFilter(for: blur, .gaussianBlur(radius: 8))
        .setFilter(for: vignette, .vignette(intensity: 0.5))
        .filterAnimation(for: vignette, .keyframes([
            .at(0.0, value: 0.0),
            .at(3.0, value: 0.8)
        ]))

    let withoutBlur = clip.removeFilter(for: blur)
    // The vignette animation is still the vignette's.
    precondition(withoutBlur.filter(for: vignette) != nil)
}
