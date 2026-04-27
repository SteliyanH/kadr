import Kadr
import Foundation
import CoreMedia
import CoreImage

/// v0.6.0 showcase — multi-track timeline.
///
/// Each function below is a self-contained recipe. URLs are placeholders — wire to
/// real assets to run.

// MARK: - 1. Picture-in-picture via .at(time:)

/// Smallest possible multi-track shape: one main clip plus a free-floating clip
/// pinned to a specific composition time.
@available(iOS 16, macOS 13, *)
func v060PictureInPicture() async throws {
    let mainURL = URL(fileURLWithPath: "/tmp/main.mov")
    let pipURL = URL(fileURLWithPath: "/tmp/pip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v060_pip.mp4")

    _ = try await Video {
        VideoClip(url: mainURL).trimmed(to: 0...10)
        VideoClip(url: pipURL).trimmed(to: 0...3).at(time: 2.0)
    }
    .export(to: outputURL)
}

// MARK: - 2. Track block — grouped parallel sub-timeline

/// A parallel track containing multiple clips that chain among themselves.
@available(iOS 16, macOS 13, *)
func v060ParallelTrack() async throws {
    let mainURL = URL(fileURLWithPath: "/tmp/main.mov")
    let aURL = URL(fileURLWithPath: "/tmp/a.mov")
    let bURL = URL(fileURLWithPath: "/tmp/b.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v060_track.mp4")

    _ = try await Video {
        VideoClip(url: mainURL).trimmed(to: 0...10)
        Track(at: 1.0) {
            VideoClip(url: aURL).trimmed(to: 0...3)
            VideoClip(url: bURL).trimmed(to: 0...3)
        }
    }
    .export(to: outputURL)
}

// MARK: - 3. Track with transitions inside (recursive composition)

/// Tracks that contain transitions are pre-rendered to a temp .mp4 internally, then
/// inserted as a single piece on the parent's parallel video track. Transparent to
/// the consumer — just declare the transition inside the Track.
@available(iOS 16, macOS 13, *)
func v060TrackWithTransitions() async throws {
    let mainURL = URL(fileURLWithPath: "/tmp/main.mov")
    let aURL = URL(fileURLWithPath: "/tmp/a.mov")
    let bURL = URL(fileURLWithPath: "/tmp/b.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v060_track_dissolve.mp4")

    _ = try await Video {
        VideoClip(url: mainURL).trimmed(to: 0...10)
        Track(at: 2.0) {
            VideoClip(url: aURL).trimmed(to: 0...2)
            Transition.dissolve(duration: 0.5)
            VideoClip(url: bURL).trimmed(to: 0...2)
        }
    }
    .export(to: outputURL)
}

// MARK: - 4. Custom multi-input compositor — protocol form

/// A custom blend that multiplies the foreground over the background. Multi-input
/// compositors run after the v0.6 multi-track engine assembles parallel tracks.
@available(iOS 16, macOS 13, *)
struct MultiplyBlend: MultiInputCompositor {
    func process(images: [CIImage], context: CompositorContext) -> CIImage {
        guard images.count >= 2 else { return images.first ?? CIImage(color: .clear) }
        let filter = CIFilter(name: "CIMultiplyBlendMode")
        filter?.setValue(images[1], forKey: kCIInputImageKey)
        filter?.setValue(images[0], forKey: kCIInputBackgroundImageKey)
        return filter?.outputImage ?? images[0]
    }
}

@available(iOS 16, macOS 13, *)
func v060CustomMultiInputCompositor() async throws {
    let baseURL = URL(fileURLWithPath: "/tmp/base.mov")
    let overlayURL = URL(fileURLWithPath: "/tmp/overlay.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v060_multiply.mp4")

    _ = try await Video {
        VideoClip(url: baseURL).trimmed(to: 0...8)
        VideoClip(url: overlayURL).trimmed(to: 0...8).at(time: 0)
    }
    .compositor(MultiplyBlend())
    .export(to: outputURL)
}

// MARK: - 5. Custom multi-input compositor — closure form

/// Inline closure for a one-off blend. Same engine path as the protocol form; just
/// less ceremony at the call site.
@available(iOS 16, macOS 13, *)
func v060InlineMultiInputCompositor() async throws {
    let baseURL = URL(fileURLWithPath: "/tmp/base.mov")
    let overlayURL = URL(fileURLWithPath: "/tmp/overlay.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v060_screen.mp4")

    _ = try await Video {
        VideoClip(url: baseURL).trimmed(to: 0...8)
        VideoClip(url: overlayURL).trimmed(to: 0...8).at(time: 0)
    }
    .compositor { images, _ in
        guard images.count >= 2 else { return images.first ?? CIImage(color: .clear) }
        return CIFilter(name: "CIScreenBlendMode", parameters: [
            kCIInputImageKey: images[1],
            kCIInputBackgroundImageKey: images[0],
        ])?.outputImage ?? images[0]
    }
    .export(to: outputURL)
}

// MARK: - 6. Nested Tracks

/// Tracks can contain other Tracks. Outer Tracks containing nested ones are pre-rendered
/// recursively. Useful for organizing complex sub-compositions.
@available(iOS 16, macOS 13, *)
func v060NestedTracks() async throws {
    let mainURL = URL(fileURLWithPath: "/tmp/main.mov")
    let pipAURL = URL(fileURLWithPath: "/tmp/pipA.mov")
    let pipBURL = URL(fileURLWithPath: "/tmp/pipB.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v060_nested.mp4")

    _ = try await Video {
        VideoClip(url: mainURL).trimmed(to: 0...10)
        Track(at: 0) {
            Track(at: 0) {
                VideoClip(url: pipAURL).trimmed(to: 0...3)
            }
            VideoClip(url: pipBURL).trimmed(to: 0...3)
        }
    }
    .export(to: outputURL)
}

// MARK: - 7. End-to-end — combining v0.6 features

/// A composition that uses every shape of the v0.6 hybrid DSL plus a custom blender,
/// all on top of v0.5's per-clip processing surface.
@available(iOS 16, macOS 13, *)
func v060Combined() async throws {
    let mainURL = URL(fileURLWithPath: "/tmp/main.mov")
    let pipAURL = URL(fileURLWithPath: "/tmp/pipA.mov")
    let pipBURL = URL(fileURLWithPath: "/tmp/pipB.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v060_combined.mp4")

    _ = try await Video {
        // Implicit chain — main timeline
        VideoClip(url: mainURL)
            .trimmed(to: 0...12)
            .filter(.brightness(0.05))   // v0.5 per-clip filter

        // Single PiP via .at(time:)
        VideoClip(url: pipAURL)
            .trimmed(to: 0...2)
            .at(time: 1.0)

        // A grouped sub-timeline with internal transitions
        Track(at: 4.0) {
            VideoClip(url: pipAURL).trimmed(to: 0...2)
            Transition.dissolve(duration: 0.5)
            VideoClip(url: pipBURL).trimmed(to: 0...2)
        }
    }
    .compositor(MultiplyBlend())            // v0.6 multi-input compositor
    .export(to: outputURL)
}
