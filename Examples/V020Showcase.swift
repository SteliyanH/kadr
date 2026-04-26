import Kadr
import Foundation

/// v0.2.0 showcase — transitions, speed, and audio ducking working together.
///
/// Builds a 13-second highlight reel:
///   intro (3s) → dissolve (0.5s) → slow-mo action (8s, played at 0.5x = 16s shown? No — speed 0.5 doubles duration so we trim to 4s source which becomes 8s) → slide-from-right → outro (3s)
@available(iOS 16, macOS 13, *)
func v020ShowcaseExample() async throws {
    let introURL = URL(fileURLWithPath: "/tmp/intro.mov")
    let actionURL = URL(fileURLWithPath: "/tmp/action.mov")
    let outroURL = URL(fileURLWithPath: "/tmp/outro.mov")
    let musicURL = URL(fileURLWithPath: "/tmp/music.mp3")
    let outputURL = URL(fileURLWithPath: "/tmp/highlight_reel.mp4")

    _ = try await Video {
        VideoClip(url: introURL).trimmed(to: 0...3)
        Transition.dissolve(duration: 0.5)

        // 4 seconds of source plays back at 0.5x → 8 seconds of slow-mo on the timeline
        VideoClip(url: actionURL).trimmed(to: 5...9).speed(0.5)
        Transition.slide(direction: .fromRight, duration: 0.4)

        VideoClip(url: outroURL).trimmed(to: 0...3)
    }
    // Music plays at 80% volume normally, ducks to 20% whenever clip audio is present.
    .audio { AudioTrack(url: musicURL).volume(0.8).ducking(0.2).fadeIn(0.5).fadeOut(1.0) }
    .preset(.reelsAndShorts)
    .export(to: outputURL)
}

/// Slide-direction sampler — exports four versions of the same edit, one per direction.
@available(iOS 16, macOS 13, *)
func slideDirectionsExample() async throws {
    let clipA = URL(fileURLWithPath: "/tmp/a.mov")
    let clipB = URL(fileURLWithPath: "/tmp/b.mov")

    for direction in [SlideDirection.fromLeft, .fromRight, .fromTop, .fromBottom] {
        let outURL = URL(fileURLWithPath: "/tmp/slide_\(direction).mp4")
        _ = try await Video {
            VideoClip(url: clipA).trimmed(to: 0...2)
            Transition.slide(direction: direction, duration: 0.5)
            VideoClip(url: clipB).trimmed(to: 0...2)
        }
        .export(to: outURL)
    }
}

/// Fast-forward + ducking — useful for vlog-style content where commentary plays over a sped-up b-roll.
@available(iOS 16, macOS 13, *)
func vlogStyleExample() async throws {
    let bRollURL = URL(fileURLWithPath: "/tmp/broll.mov")
    let commentaryURL = URL(fileURLWithPath: "/tmp/voiceover.mp3")
    let bgMusicURL = URL(fileURLWithPath: "/tmp/lofi.mp3")
    let outputURL = URL(fileURLWithPath: "/tmp/vlog.mp4")

    _ = try await Video {
        // 30s of b-roll played at 3x speed = 10s on the timeline. Original audio replaced by commentary.
        VideoClip(url: bRollURL).trimmed(to: 0...30).speed(3.0).withAudio(commentaryURL)
    }
    // Music ducks to 30% whenever the (replacement) commentary track is present, then back up.
    .audio { AudioTrack(url: bgMusicURL).ducking(0.3) }
    .export(to: outputURL)
}
