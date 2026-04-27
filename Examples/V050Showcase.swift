import Kadr
import Foundation
import CoreMedia
import CoreImage

/// v0.5.0 showcase — per-clip processing primitives.
///
/// Each function below is a self-contained recipe demonstrating one or more v0.5
/// features. Function bodies use placeholder URLs — wire them to real assets to run.

// MARK: - 1. Time-ranged overlay visibility

/// An overlay that only appears during a portion of the composition. The first chapter
/// title fades in at t=0, hides at t=4, then a second title takes its place.
@available(iOS 16, macOS 13, *)
func v050TimeRangedOverlays() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v050_chapters.mp4")

    _ = try await Video {
        VideoClip(url: videoURL).trimmed(to: 0...12)
    }
    .overlay(
        TextOverlay("CHAPTER 1", style: TextStyle(fontSize: 96, color: .white, alignment: .center, weight: .bold))
            .position(.center)
            .visible(during: 0.0...4.0)
    )
    .overlay(
        TextOverlay("CHAPTER 2", style: TextStyle(fontSize: 96, color: .white, alignment: .center, weight: .bold))
            .position(.center)
            .visible(during: 6.0...10.0)
    )
    .export(to: outputURL)
}

// MARK: - 2. LUTs

/// Apply a `.cube` LUT to a video clip. Building a `LUT` once and reusing it across
/// clips avoids reparsing the file per frame.
@available(iOS 16, macOS 13, *)
func v050LUTGrading() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let lutURL = URL(fileURLWithPath: "/tmp/teal-orange.cube")
    let outputURL = URL(fileURLWithPath: "/tmp/v050_graded.mp4")

    let lut = try LUT(url: lutURL)

    _ = try await Video {
        VideoClip(url: videoURL).trimmed(to: 0...10).filter(.lut(lut))
        Transition.dissolve(duration: 0.5)
        VideoClip(url: videoURL).trimmed(to: 10...20).filter(.lut(lut))
    }
    .export(to: outputURL)
}

// MARK: - 3. Chroma key

/// Remove a green background from a clip. `ChromaKey` precomputes the cube once at
/// construction; reuse the value across clips for cheap composition.
@available(iOS 16, macOS 13, *)
func v050GreenScreen() async throws {
    let subjectURL = URL(fileURLWithPath: "/tmp/subject_on_green.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v050_keyed.mp4")

    let key = ChromaKey(color: .green, threshold: 0.35)

    _ = try await Video {
        VideoClip(url: subjectURL).trimmed(to: 0...8).filter(.chromaKey(key))
    }
    .export(to: outputURL)
}

// MARK: - 4. Custom compositor — protocol form

/// A user-written `Compositor` that adds a time-driven vignette intensifying toward
/// the end of the clip. Time is read off `CompositorContext.time`.
@available(iOS 16, macOS 13, *)
struct TimeDrivenVignette: Compositor {
    let totalDuration: CMTime

    func process(image: CIImage, context: CompositorContext) -> CIImage {
        let total = CMTimeGetSeconds(totalDuration)
        guard total > 0 else { return image }
        let progress = min(1.0, max(0.0, CMTimeGetSeconds(context.time) / total))
        let intensity = progress * 1.5

        guard let filter = CIFilter(name: "CIVignette",
                                    parameters: [
                                        kCIInputImageKey: image,
                                        "inputIntensity": intensity,
                                        "inputRadius": 1.5
                                    ]) else { return image }
        return filter.outputImage ?? image
    }
}

@available(iOS 16, macOS 13, *)
func v050CustomCompositor() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v050_vignetted.mp4")

    _ = try await Video {
        VideoClip(url: videoURL)
            .trimmed(to: 0...8)
            .compositor(TimeDrivenVignette(totalDuration: CMTime(seconds: 8, preferredTimescale: 600)))
    }
    .export(to: outputURL)
}

// MARK: - 5. Custom compositor — closure form

/// Inline closure for an ad-hoc one-off transformation. No need to define a named type.
@available(iOS 16, macOS 13, *)
func v050InlineCompositor() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v050_inverted.mp4")

    _ = try await Video {
        VideoClip(url: videoURL)
            .trimmed(to: 0...4)
            .compositor { image, _ in
                image.applyingFilter("CIColorInvert")
            }
    }
    .export(to: outputURL)
}

// MARK: - 6. Per-clip crop

/// Reframe each clip independently. Different from the composition-wide `Video.crop`
/// (which sets the output's render size); per-clip crop replaces the clip's frame
/// with the cropped region scaled to fill.
@available(iOS 16, macOS 13, *)
func v050PerClipCrop() async throws {
    let aURL = URL(fileURLWithPath: "/tmp/a.mov")
    let bURL = URL(fileURLWithPath: "/tmp/b.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v050_reframed.mp4")

    _ = try await Video {
        VideoClip(url: aURL).trimmed(to: 0...5)
            .crop(at: .center, size: .normalized(width: 0.6, height: 0.6))
        Transition.dissolve(duration: 0.5)
        VideoClip(url: bURL).trimmed(to: 0...5)
            .crop(at: .topRight, size: .normalized(width: 0.4, height: 0.4), anchor: .topRight)
    }
    .export(to: outputURL)
}

// MARK: - 7. Alpha-mask crop

/// Non-rectangular shapes — circular mask for a profile-style bug, soft-edge masks
/// for vignetted highlights, etc. Mask is stretched to fit each frame's extent.
@available(iOS 16, macOS 13, *)
func v050MaskedClip() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let maskImage = PlatformImage()    // load your circular / soft mask here
    let outputURL = URL(fileURLWithPath: "/tmp/v050_masked.mp4")

    _ = try await Video {
        VideoClip(url: videoURL).trimmed(to: 0...6).mask(maskImage)
    }
    .export(to: outputURL)
}

// MARK: - 8. End-to-end — combining v0.5 features

/// Stack everything: a graded clip with a custom vignette, masked into a circular
/// shape, plus a chapter-titled time-ranged overlay.
@available(iOS 16, macOS 13, *)
func v050Combined() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let lutURL = URL(fileURLWithPath: "/tmp/look.cube")
    let maskImage = PlatformImage()
    let outputURL = URL(fileURLWithPath: "/tmp/v050_combined.mp4")

    let lut = try LUT(url: lutURL)

    _ = try await Video {
        VideoClip(url: videoURL)
            .trimmed(to: 0...8)
            .filter(.lut(lut))
            .compositor(TimeDrivenVignette(totalDuration: CMTime(seconds: 8, preferredTimescale: 600)))
            .mask(maskImage)
    }
    .overlay(
        TextOverlay("INTRO", style: TextStyle(fontSize: 80, color: .white, alignment: .center, weight: .bold))
            .position(.top)
            .anchor(.top)
            .visible(during: 0.0...2.0)
    )
    .export(to: outputURL)
}
