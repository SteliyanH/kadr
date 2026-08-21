import Kadr
import Foundation
import CoreMedia

/// v0.9 showcase — advanced timing.
///
/// Speed curves, pitch-preserving audio speed, and the caption bridge. Each
/// function is a self-contained recipe; URLs are placeholders.

// MARK: - 1. Speed curve on a clip

/// A ramp that starts slow, accelerates through the middle, and settles.
///
/// `.curved` takes an `Animation<Double>` over *clip-relative* time, so a
/// keyframe at 0 is the clip's first frame regardless of where the clip sits in
/// the composition. The engine integrates the curve into a piecewise-linear time
/// map, and audio follows the same map.
func v090SpeedRamp() async throws {
    let source = URL(fileURLWithPath: "/tmp/action.mov")
    let output = URL(fileURLWithPath: "/tmp/v090_ramp.mp4")

    _ = try await Video {
        VideoClip(url: source)
            .trimmed(to: 0...8)
            .speed(.curved(.keyframes([
                .at(0.0, value: 0.5),   // half speed off the top
                .at(4.0, value: 2.0),   // double through the middle
                .at(8.0, value: 1.0)    // back to real time
            ])))
    }
    .export(to: output)
}

/// The simpler case: one constant rate for the whole clip.
///
/// `.flat` and `.curved` are separate cases rather than an optional parameter,
/// so a composition cannot express both at once.
func v090FlatSpeed() async throws {
    let source = URL(fileURLWithPath: "/tmp/talk.mov")
    let output = URL(fileURLWithPath: "/tmp/v090_flat.mp4")

    _ = try await Video {
        VideoClip(url: source).speed(.flat(1.25))
    }
    .export(to: output)
}

// MARK: - 2. Pitch-preserving audio speed

/// Speed a music bed up without turning it into chipmunks.
///
/// `.spectral` preserves pitch and is the right default for music and speech.
/// `.varispeed` deliberately does not — it is the tape-machine sound, useful
/// when you want the artefact.
func v090AudioSpeed() async throws {
    let video = URL(fileURLWithPath: "/tmp/clip.mov")
    let music = URL(fileURLWithPath: "/tmp/bed.m4a")
    let output = URL(fileURLWithPath: "/tmp/v090_audio_speed.mp4")

    _ = try await Video {
        VideoClip(url: video).trimmed(to: 0...12)
    }
    .audio {
        AudioTrack(url: music)
            .speed(1.5, algorithm: .spectral)
            .fadeOut(2.0)
    }
    .export(to: output)
}

// MARK: - 3. Captions

/// Attach cues so the export carries a caption track.
///
/// The engine bakes these as an `AVMetadataItem` group — a *soft* track the
/// player can switch on and off. Parsing SRT/VTT/iTT/ASS/SSA files lives in
/// `kadr-captions`; core stays the bridge. For captions burned into the frames,
/// see that package's styled-caption path.
func v090Captions() async throws {
    let source = URL(fileURLWithPath: "/tmp/interview.mov")
    let output = URL(fileURLWithPath: "/tmp/v090_captions.mp4")

    _ = try await Video {
        VideoClip(url: source).trimmed(to: 0...20)
    }
    .captions([
        Caption(text: "Everything starts somewhere.", timeRange: seconds(0.5, to: 3.0)),
        Caption(text: "Usually later than you'd like.", timeRange: seconds(3.2, to: 6.0))
    ])
    .export(to: output)
}


// MARK: - Helpers

/// `CMTimeRange` from two second values, so the recipes above read as prose.
private func seconds(_ start: Double, to end: Double) -> CMTimeRange {
    CMTimeRange(
        start: CMTime(seconds: start, preferredTimescale: 600),
        end: CMTime(seconds: end, preferredTimescale: 600)
    )
}
