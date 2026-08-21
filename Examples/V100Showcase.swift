import Kadr
import Foundation
import CoreMedia

/// v0.10 showcase — track opacity and animation clearing.

// MARK: - 1. Track opacity

/// Fade a whole track rather than each clip in it.
///
/// Opacity on `Track` applies to the composed result, so a stack of clips
/// dissolves as one thing instead of each clip dissolving separately over its
/// neighbours.
func v100TrackOpacity() async throws {
    let base = URL(fileURLWithPath: "/tmp/base.mov")
    let bRoll = URL(fileURLWithPath: "/tmp/broll.mov")
    let output = URL(fileURLWithPath: "/tmp/v100_track_opacity.mp4")

    _ = try await Video {
        VideoClip(url: base).trimmed(to: 0...10)
        Track(name: "b-roll") {
            VideoClip(url: bRoll).trimmed(to: 0...4).at(time: 3.0)
        }
        .opacity(0.6)
    }
    .export(to: output)
}

// MARK: - 2. Clearing an animation

/// Remove an animation without rebuilding the clip.
///
/// Passing `nil` to the animation modifiers clears the field. Before v0.10 a
/// consumer had to reconstruct the clip to drop an animation, which meant
/// carrying rebuild helpers in application code.
func v100ClearAnimation() {
    let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov"))
        .transformAnimation(.keyframes([
            .at(0.0, value: Transform.identity),
            .at(2.0, value: Transform(center: .center, rotation: 0, scale: 1.4, anchor: .center))
        ]))

    // The user dragged the animation off in the inspector.
    let cleared = clip.transformAnimation(nil)
    precondition(cleared.transformAnimation == nil)
}
