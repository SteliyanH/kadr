import Testing
import Foundation
// Plain import: `Video { }` failing to compile is a client-facing problem, and
// no in-package test wrote it because every fixture has at least one clip.
import Kadr

/// Tests for the empty composition — `Video { }`.
///
/// An empty timeline is a real state, not a degenerate one: a project that has
/// just been created, or one whose last clip was deleted. Before v0.21 the
/// literal did not compile at all — an empty block was ambiguous between
/// `VideoBuilder`'s two variadic `buildBlock` overloads.
struct EmptyCompositionTests {

    @Test("An empty composition compiles and holds no clips")
    func emptyVideo() {
        let video = Video { }
        #expect(video.clips.isEmpty)
        #expect(video.duration == .zero)
    }

    @Test("An empty composition still carries its settings")
    func emptyVideoKeepsSettings() {
        let video = Video { }.preset(.tiktok).quality(.bitrate(3_000_000))
        #expect(video.preset == .tiktok)
        #expect(video.quality == .bitrate(3_000_000))
        #expect(video.clips.isEmpty)
    }

    @Test("A loop yielding nothing produces an empty composition")
    func emptyLoop() {
        let none: [VideoClip] = []
        let video = Video { for clip in none { clip } }
        #expect(video.clips.isEmpty)
    }

    @Test("Preset is Equatable across every case")
    func presetEquality() {
        #expect(Preset.auto == Preset.auto)
        #expect(Preset.tiktok != Preset.square)
        #expect(Preset.custom(width: 1080, height: 1920, frameRate: 30, codec: .h264)
                == Preset.custom(width: 1080, height: 1920, frameRate: 30, codec: .h264))
        #expect(Preset.custom(width: 1080, height: 1920, frameRate: 30, codec: .h264)
                != Preset.custom(width: 1080, height: 1920, frameRate: 60, codec: .h264))
    }
}
