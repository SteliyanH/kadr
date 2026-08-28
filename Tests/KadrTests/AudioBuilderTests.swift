import Testing
import Foundation
// Deliberately NOT `@testable` — these assert the *public* surface a downstream
// module sees. The gap this file covers (no `buildArray`) was invisible to every
// in-package test because none of them built audio from a runtime array.
import Kadr

/// Tests for `AudioBuilder`'s control flow, at parity with `VideoBuilder`.
struct AudioBuilderTests {

    private func track(_ name: String) -> AudioTrack {
        AudioTrack(url: URL(fileURLWithPath: "/tmp/\(name).m4a"))
    }

    private func names(_ video: Video) -> [String] {
        video.audioTracks.map { $0.url.deletingPathExtension().lastPathComponent }
    }

    private var clip: VideoClip {
        VideoClip(url: URL(fileURLWithPath: "/tmp/clip.mov"))
    }

    @Test("A runtime array of tracks can be spread into the builder")
    func buildArrayFromRuntimeCollection() {
        let beds = ["a", "b", "c"].map(track)
        let video = Video { clip }.audio {
            for bed in beds { bed }
        }
        #expect(names(video) == ["a", "b", "c"])
    }

    @Test("An empty runtime array yields no tracks rather than failing to compile")
    func buildArrayEmpty() {
        let beds: [AudioTrack] = []
        let video = Video { clip }.audio {
            for bed in beds { bed }
        }
        #expect(video.audioTracks.isEmpty)
    }

    @Test("`if` without `else` includes the track only when the condition holds")
    func buildOptional() {
        func make(_ include: Bool) -> Video {
            Video { clip }.audio {
                track("bed")
                if include { track("voiceover") }
            }
        }
        #expect(names(make(true)) == ["bed", "voiceover"])
        #expect(names(make(false)) == ["bed"])
    }

    @Test("`if/else` picks exactly one branch")
    func buildEither() {
        func make(_ loud: Bool) -> Video {
            Video { clip }.audio {
                if loud { track("loud") } else { track("quiet") }
            }
        }
        #expect(names(make(true)) == ["loud"])
        #expect(names(make(false)) == ["quiet"])
    }

    @Test("Loops, conditionals, and literals compose in one block, in source order")
    func mixedControlFlow() {
        let beds = ["a", "b"].map(track)
        let video = Video { clip }.audio {
            track("intro")
            for bed in beds { bed }
            if true { track("outro") }
        }
        #expect(names(video) == ["intro", "a", "b", "outro"])
    }

    @Test("Track modifiers survive the builder")
    func modifiersSurvive() {
        let video = Video { clip }.audio {
            for bed in [track("bed").volume(0.25)] { bed }
        }
        #expect(video.audioTracks.count == 1)
        #expect(video.audioTracks[0].volumeLevel == 0.25)
    }

    @Test("The plain literal form still compiles unchanged")
    func literalFormUnchanged() {
        let video = Video { clip }.audio {
            track("one")
            track("two")
        }
        #expect(names(video) == ["one", "two"])
    }

    @Test("Repeated `audio` calls append rather than replace")
    func repeatedCallsAppend() {
        let video = Video { clip }
            .audio { track("first") }
            .audio { for bed in [track("second")] { bed } }
        #expect(names(video) == ["first", "second"])
    }
}
