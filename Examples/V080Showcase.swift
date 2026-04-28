import Kadr
import Foundation
import CoreMedia
import CoreGraphics

/// v0.8.0 showcase — Animation & Transform.
///
/// Each function below is a self-contained recipe. URLs are placeholders — wire to
/// real assets to run.

// MARK: - 1. Picture-in-picture via static Transform

/// Drop a clip in the corner at 40% scale. No animation — the transform applies
/// uniformly across the clip's lifetime.
@available(iOS 16, macOS 13, *)
func v080PictureInPicture() async throws {
    let mainURL = URL(fileURLWithPath: "/tmp/main.mov")
    let pipURL = URL(fileURLWithPath: "/tmp/pip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v080_pip.mp4")

    _ = try await Video {
        VideoClip(url: mainURL).trimmed(to: 0...10)
        VideoClip(url: pipURL)
            .trimmed(to: 0...3)
            .at(time: 2.0)
            .transform(Transform(center: .topRight, scale: 0.4, anchor: .topRight))
    }
    .export(to: outputURL)
}

// MARK: - 2. Ken Burns zoom-pan via Transform animation

/// Animate a still image from full-size to 1.3x, drifting toward the lower-right.
/// Easing makes the motion feel natural rather than mechanical.
@available(iOS 16, macOS 13, *)
func v080KenBurns() async throws {
    let photo = try makeTestImage()
    let outputURL = URL(fileURLWithPath: "/tmp/v080_ken_burns.mp4")

    _ = try await Video {
        ImageClip(photo, duration: 5.0)
            .transform(.identity, animation: .keyframes([
                .at(0.0, value: Transform(scale: 1.0, center: .normalized(x: 0.5, y: 0.5))),
                .at(5.0, value: Transform(scale: 1.3, center: .normalized(x: 0.6, y: 0.4))),
            ], timing: .easeInOut))
    }
    .export(to: outputURL)
}

// MARK: - 3. Fade-in opacity animation

/// Animate clip opacity from 0 to 1 over the first half-second, then hold full
/// opacity. Outside the keyframe range the engine holds at the nearest keyframe's
/// value, so 0.5s onward stays at 1.0.
@available(iOS 16, macOS 13, *)
func v080OpacityFadeIn() async throws {
    let clipURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v080_fade_in.mp4")

    _ = try await Video {
        VideoClip(url: clipURL)
            .trimmed(to: 0...3)
            .opacity(1.0, animation: .keyframes([
                .at(0.0, value: 0.0),
                .at(0.5, value: 1.0),
            ]))
    }
    .export(to: outputURL)
}

// MARK: - 4. Animated TextOverlay reveal

/// Title fades in over 1 second using the built-in `FadeIn` recipe. The animation
/// runs from composition t=0 (`AVCoreAnimationBeginTimeAtZero`) by default.
@available(iOS 16, macOS 13, *)
func v080AnimatedTitleFadeIn() async throws {
    let clipURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v080_title_fade.mp4")

    _ = try await Video {
        VideoClip(url: clipURL).trimmed(to: 0...5)
    }
    .overlay(
        TextOverlay("MY MOVIE", style: TextStyle(fontSize: 96, alignment: .center, weight: .bold))
            .position(.center)
            .animation(.fadeIn(duration: 1.0))
    )
    .export(to: outputURL)
}

// MARK: - 5. Slide-in subtitle from the bottom edge

/// Subtitle slides up from below the canvas using `SlideIn(.fromBottom, ...)`.
/// Pair with `.visible(during:)` to show the subtitle only while it's relevant.
@available(iOS 16, macOS 13, *)
func v080SlideInSubtitle() async throws {
    let clipURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v080_subtitle.mp4")

    _ = try await Video {
        VideoClip(url: clipURL).trimmed(to: 0...10)
    }
    .overlay(
        TextOverlay("LOCATION: HQ", style: TextStyle(fontSize: 40, weight: .medium))
            .position(.bottom)
            .anchor(.bottom)
            .animation(.slideIn(from: .fromBottom, duration: 0.4))
    )
    .export(to: outputURL)
}

// MARK: - 6. Audio cross-fade between two music tracks

/// Music swap mid-composition. Track A ends at t=8s, Track B starts at t=7s,
/// `.crossfade(1.0)` on Track A makes the engine fade A out and B in over the 1s
/// overlap. Cross-fade overrides user `fadeIn` / `fadeOut` at that boundary so
/// AVFoundation doesn't see overlapping ramps.
@available(iOS 16, macOS 13, *)
func v080AudioCrossfade() async throws {
    let clipURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let musicAURL = URL(fileURLWithPath: "/tmp/musicA.m4a")
    let musicBURL = URL(fileURLWithPath: "/tmp/musicB.m4a")
    let outputURL = URL(fileURLWithPath: "/tmp/v080_crossfade.mp4")

    _ = try await Video {
        VideoClip(url: clipURL).trimmed(to: 0...12)
    }
    .audio {
        AudioTrack(url: musicAURL).at(time: 0).duration(8.0).crossfade(1.0)
        AudioTrack(url: musicBURL).at(time: 7.0)  // 1s overlap fades A → B
    }
    .export(to: outputURL)
}

// MARK: - 7. End-to-end — combining v0.8 features

/// A composition that uses every shape of the v0.8 surface: per-clip Transform,
/// Transform animation, opacity animation, animated TextOverlay, and an audio
/// cross-fade.
@available(iOS 16, macOS 13, *)
func v080Combined() async throws {
    let mainURL = URL(fileURLWithPath: "/tmp/main.mov")
    let pipURL = URL(fileURLWithPath: "/tmp/pip.mov")
    let photo = try makeTestImage()
    let musicAURL = URL(fileURLWithPath: "/tmp/musicA.m4a")
    let musicBURL = URL(fileURLWithPath: "/tmp/musicB.m4a")
    let outputURL = URL(fileURLWithPath: "/tmp/v080_combined.mp4")

    _ = try await Video {
        // Photo with a Ken Burns zoom-pan + fade-in opacity
        ImageClip(photo, duration: 5.0)
            .transform(.identity, animation: .keyframes([
                .at(0.0, value: Transform(scale: 1.0)),
                .at(5.0, value: Transform(scale: 1.3, center: .normalized(x: 0.6, y: 0.4))),
            ], timing: .easeInOut))
            .opacity(1.0, animation: .keyframes([
                .at(0.0, value: 0.0),
                .at(0.5, value: 1.0),
            ]))

        // Main video continues
        VideoClip(url: mainURL).trimmed(to: 0...10)

        // PiP corner overlay scaled down (static Transform on a free-floater)
        VideoClip(url: pipURL).trimmed(to: 0...3)
            .at(time: 6.0)
            .transform(Transform(center: .topRight, scale: 0.4, anchor: .topRight))
    }
    .overlay(
        TextOverlay("CHAPTER ONE", style: TextStyle(fontSize: 80, alignment: .center, weight: .bold))
            .position(.center)
            .visible(during: 0.0...2.0)
            .animation(.scaleUp(duration: 0.5))
    )
    .audio {
        AudioTrack(url: musicAURL).at(time: 0).duration(8.0).crossfade(1.0)
        AudioTrack(url: musicBURL).at(time: 7.0)
    }
    .preset(.reelsAndShorts)
    .export(to: outputURL)
}

// MARK: - Helpers

private func makeTestImage() throws -> PlatformImage {
    // Placeholder — wire to a real image file or a system-symbol render
    // (see Examples/SimpleEditor for the symbol pattern).
    PlatformImage()
}
