import Kadr
import Foundation
import CoreMedia

/// v0.4.1 showcase — `ClipID`, the stable per-clip identifier added in v0.4.1.
///
/// Each function below is a self-contained recipe. `ClipID` mirrors `LayerID`'s role
/// for overlays: it gives callers (notably timeline UIs) a stable handle for a clip
/// that survives reorder and trim. Assignment is opt-in via `.id(_:)` on any media
/// clip; `Transition` doesn't carry an ID because it isn't an addressable unit.

// MARK: - 1. Assigning IDs survives the modifier chain

/// IDs are preserved through every chained modifier (`.trimmed`, `.reversed`, `.speed`,
/// `.filter`, `.background`, `.withAudio`, etc.) — set the ID once at any point in
/// the chain.
@available(iOS 16, macOS 13, *)
func v041AssigningIDsSurvivesModifierChain() {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")

    // Set the ID at the start, mutate freely afterwards.
    let body = VideoClip(url: videoURL)
        .id("body")
        .trimmed(to: 0...8)
        .speed(0.75)
        .filter(.brightness(0.1))
    assert(body.clipID == ClipID("body"))

    // Or set it at the end — same result.
    let intro = VideoClip(url: videoURL)
        .trimmed(to: 0...3)
        .reversed()
        .id("intro")
    assert(intro.clipID == ClipID("intro"))
}

// MARK: - 2. Generic iteration via the Clip protocol

/// `Clip.clipID` is a protocol requirement (default `nil`), so you can read IDs from
/// `Video.clips` regardless of the concrete clip type. Useful for building any UI
/// that walks the composition.
@available(iOS 16, macOS 13, *)
func v041IterateClipIDs(_ video: Video) -> [ClipID] {
    video.clips.compactMap { $0.clipID }
}

// MARK: - 3. End-to-end — pattern for a clip-selection model

/// The pattern a timeline UI uses: the consumer holds a `selectedClipID: ClipID?`,
/// hit-tests a tap by walking `video.clips`, and rebuilds the `Video` if it ever
/// reorders or trims (Kadr's `Video` is immutable; consumers carry mutation intent).
@available(iOS 16, macOS 13, *)
func v041SelectionModelDemo() {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")

    let video = Video {
        VideoClip(url: videoURL).trimmed(to: 0...3).id("intro")
        Transition.dissolve(duration: 0.5)
        VideoClip(url: videoURL).trimmed(to: 5...12).id("body")
        Transition.fade(duration: 0.4)
        VideoClip(url: videoURL).trimmed(to: 15...18).id("outro")
    }

    // Selection — the consumer's piece of state. ClipID is Hashable, so it works as
    // a SwiftUI binding key, a dictionary key, etc.
    let selectedClipID: ClipID? = "body"

    // Find the selected clip without an array-index race.
    let selected = video.clips.first { $0.clipID == selectedClipID }
    _ = selected
}
