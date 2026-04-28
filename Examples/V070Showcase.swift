import Kadr
import Foundation
import CoreMedia
import CoreImage

/// v0.7.0 showcase — multi-track polish + audio timing.
///
/// Each function below is a self-contained recipe. URLs are placeholders — wire to
/// real assets to run.

// MARK: - 1. Named Track for downstream tooling

/// `Track(name:)` attaches a human-readable label that surfaces through `Video.clips`.
/// kadr-ui's `TimelineView` uses it for lane labels.
@available(iOS 16, macOS 13, *)
func v070NamedTrack() async throws {
    let mainURL = URL(fileURLWithPath: "/tmp/main.mov")
    let bRollURL = URL(fileURLWithPath: "/tmp/broll.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v070_named_track.mp4")

    _ = try await Video {
        VideoClip(url: mainURL).trimmed(to: 0...10)
        Track(at: 2.0, name: "B-Roll") {
            VideoClip(url: bRollURL).trimmed(to: 0...3)
        }
    }
    .export(to: outputURL)
}

// MARK: - 2. Transitions in the implicit chain alongside multi-track

/// Previously rejected with `KadrError.notYetImplemented` — workaround was to wrap
/// the chain in a `Track {}`. As of v0.7 the engine pre-renders the chain to a temp
/// `.mp4` and inserts it as a single piece on the main video track.
@available(iOS 16, macOS 13, *)
func v070TransitionsInChainWithMultiTrack() async throws {
    let aURL = URL(fileURLWithPath: "/tmp/a.mov")
    let bURL = URL(fileURLWithPath: "/tmp/b.mov")
    let pipURL = URL(fileURLWithPath: "/tmp/pip.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v070_chain_transitions.mp4")

    _ = try await Video {
        VideoClip(url: aURL).trimmed(to: 0...5)
        Transition.dissolve(duration: 0.5)
        VideoClip(url: bURL).trimmed(to: 0...5)

        // Multi-track parallel content alongside the chain.
        VideoClip(url: pipURL).trimmed(to: 0...3).at(time: 1.0)
    }
    .export(to: outputURL)
}

// MARK: - 3. Time-windowed compositor — protocol form

/// `Video.compositor(_:during:)` runs the user's blender only inside `range`. Outside
/// the window, the engine's default alpha-composite blender takes over per frame.
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
func v070TimeWindowedCompositor() async throws {
    let baseURL = URL(fileURLWithPath: "/tmp/base.mov")
    let overlayURL = URL(fileURLWithPath: "/tmp/overlay.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v070_windowed_blend.mp4")

    _ = try await Video {
        VideoClip(url: baseURL).trimmed(to: 0...8)
        VideoClip(url: overlayURL).trimmed(to: 0...8).at(time: 0)
    }
    // Multiply blend only fires between t=2s and t=5s; before/after, plain alpha.
    .compositor(MultiplyBlend(), during: 2.0...5.0)
    .export(to: outputURL)
}

// MARK: - 4. Time-windowed compositor — closure form

/// Inline closure for one-off blends inside a window.
@available(iOS 16, macOS 13, *)
func v070TimeWindowedCompositorClosure() async throws {
    let baseURL = URL(fileURLWithPath: "/tmp/base.mov")
    let overlayURL = URL(fileURLWithPath: "/tmp/overlay.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/v070_windowed_screen.mp4")

    let window = CMTimeRange(
        start: CMTime(seconds: 2, preferredTimescale: 600),
        end: CMTime(seconds: 5, preferredTimescale: 600)
    )
    _ = try await Video {
        VideoClip(url: baseURL).trimmed(to: 0...8)
        VideoClip(url: overlayURL).trimmed(to: 0...8).at(time: 0)
    }
    .compositor(during: window) { images, _ in
        guard images.count >= 2 else { return images.first ?? CIImage(color: .clear) }
        return CIFilter(name: "CIScreenBlendMode", parameters: [
            kCIInputImageKey: images[1],
            kCIInputBackgroundImageKey: images[0],
        ])?.outputImage ?? images[0]
    }
    .export(to: outputURL)
}

// MARK: - 5. Sound effect pinned to a moment

/// `AudioTrack.at(time:)` + `.duration(_:)` pin an audio asset to a composition time
/// and cap its playback length. The asset's natural duration still wins if shorter
/// than the explicit cap.
@available(iOS 16, macOS 13, *)
func v070SoundEffect() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/main.mov")
    let musicURL = URL(fileURLWithPath: "/tmp/music.m4a")
    let sfxURL = URL(fileURLWithPath: "/tmp/sfx_whoosh.m4a")
    let outputURL = URL(fileURLWithPath: "/tmp/v070_sfx.mp4")

    _ = try await Video {
        VideoClip(url: videoURL).trimmed(to: 0...10)
    }
    .audio {
        AudioTrack(url: musicURL).volume(0.6)             // bg music for the full piece
        AudioTrack(url: sfxURL).at(time: 3.0).duration(1.5) // SFX punches in at t=3s, capped at 1.5s
    }
    .export(to: outputURL)
}

// MARK: - 6. Multiple time-pinned audio cues

/// Stack several time-pinned tracks. Volume / fade / ducking automation is anchored
/// to each track's absolute composition time so they layer correctly.
@available(iOS 16, macOS 13, *)
func v070MultipleAudioCues() async throws {
    let videoURL = URL(fileURLWithPath: "/tmp/main.mov")
    let bedURL = URL(fileURLWithPath: "/tmp/bed.m4a")
    let cue1URL = URL(fileURLWithPath: "/tmp/cue1.m4a")
    let cue2URL = URL(fileURLWithPath: "/tmp/cue2.m4a")
    let outputURL = URL(fileURLWithPath: "/tmp/v070_audio_cues.mp4")

    _ = try await Video {
        VideoClip(url: videoURL).trimmed(to: 0...12)
    }
    .audio {
        AudioTrack(url: bedURL).volume(0.4).fadeIn(0.5).fadeOut(1.0)
        AudioTrack(url: cue1URL).at(time: 2.0).duration(2.0).fadeIn(0.2).fadeOut(0.2)
        AudioTrack(url: cue2URL).at(time: 7.0).duration(3.0).fadeIn(0.2).fadeOut(0.5)
    }
    .export(to: outputURL)
}

// MARK: - 7. End-to-end — combining v0.7 features

/// A composition that uses every shape of the v0.7 surface: named Track, transitions
/// in the chain alongside multi-track, time-windowed compositor, and a pinned sound
/// effect. All on top of v0.6's hybrid multi-track DSL.
@available(iOS 16, macOS 13, *)
func v070Combined() async throws {
    let mainURL = URL(fileURLWithPath: "/tmp/main.mov")
    let bRollURL = URL(fileURLWithPath: "/tmp/broll.mov")
    let pipURL = URL(fileURLWithPath: "/tmp/pip.mov")
    let bedURL = URL(fileURLWithPath: "/tmp/bed.m4a")
    let stingURL = URL(fileURLWithPath: "/tmp/sting.m4a")
    let outputURL = URL(fileURLWithPath: "/tmp/v070_combined.mp4")

    _ = try await Video {
        VideoClip(url: mainURL).trimmed(to: 0...8)
        Transition.dissolve(duration: 0.5)               // chain transition (now legal!)
        VideoClip(url: mainURL).trimmed(to: 8...14)

        VideoClip(url: pipURL).trimmed(to: 0...3).at(time: 2.0)

        Track(at: 5.0, name: "B-Roll Cutaway") {
            VideoClip(url: bRollURL).trimmed(to: 0...2)
            Transition.fade(duration: 0.3)
            VideoClip(url: bRollURL).trimmed(to: 2...4)
        }
    }
    .compositor(MultiplyBlend(), during: 5.0...9.0)      // blend the cutaway window
    .audio {
        AudioTrack(url: bedURL).volume(0.4).ducking(0.2)
        AudioTrack(url: stingURL).at(time: 5.0).duration(0.5)
    }
    .export(to: outputURL)
}
