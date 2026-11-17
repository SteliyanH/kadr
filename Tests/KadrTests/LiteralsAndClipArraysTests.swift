import Testing
import Foundation
import Kadr

/// `.speed(0.5)` and `Video { urls.map { VideoClip(url: $0) } }`.
///
/// Both are spellings people reach for first. Before this they did not compile:
/// a `Double` is not a `Speed`, and the builder took one clip per line, not a list.
/// Imported without `@testable` on purpose: what matters is that the public
/// surface accepts these spellings.
struct LiteralsAndClipArraysTests {

    private let url = URL(fileURLWithPath: "/tmp/kadr-literals.mov")

    private func clip(_ id: String) -> VideoClip {
        VideoClip(url: url).id(ClipID(id))
    }

    private func ids(_ clips: [any Clip]) -> [String] {
        clips.map { $0.clipID?.description ?? "-" }
    }

    // MARK: - Speed literals

    @Test func floatLiteralIsAFlatRate() {
        let literal = VideoClip(url: url).speed(0.5)
        let explicit = VideoClip(url: url).speed(.flat(0.5))
        #expect(literal.speedRate == explicit.speedRate)
        #expect(literal.speedCurve == nil)
        guard case .flat(let rate) = literal.speed else {
            Issue.record("expected .flat, got \(literal.speed)")
            return
        }
        #expect(rate == 0.5)
    }

    @Test func integerLiteralIsAFlatRate() {
        let clip = VideoClip(url: url).speed(2)
        #expect(clip.speedRate == 2.0)
        #expect(clip.speedCurve == nil)
    }

    @Test func literalReplacesACurve() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 1.0), .at(1.0, value: 0.5)])
        let clip = VideoClip(url: url).speed(.curved(curve)).speed(1.5)
        #expect(clip.speedCurve == nil)
        #expect(clip.speedRate == 1.5)
    }

    @Test func literalInitialisesASpeedValue() {
        let half: Speed = 0.5
        let double: Speed = 2
        guard case .flat(0.5) = half, case .flat(2.0) = double else {
            Issue.record("expected .flat(0.5) and .flat(2.0), got \(half) and \(double)")
            return
        }
    }

    /// A literal skips no validation: an out-of-range rate fails at export with
    /// the same error `.flat` gives. Needs a real asset, because the rate is
    /// checked after the source loads.
    @Test func outOfRangeLiteralThrowsLikeFlat() async throws {
        let sample = try #require(Bundle.module.url(forResource: "sample", withExtension: "mov"))
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadr-literal-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        do {
            _ = try await Video { VideoClip(url: sample).speed(10) }.export(to: output)
            Issue.record("expected KadrError.invalidSpeed(10)")
        } catch KadrError.invalidSpeed(let rate) {
            #expect(rate == 10)
        }
    }

    // MARK: - Clip arrays in the builder

    @Test func mappedArrayBecomesClips() {
        let names = ["a", "b", "c"]
        let video = Video { names.map { clip($0) } }
        #expect(ids(video.clips) == names)
    }

    @Test func arrayVariableOfConcreteClips() {
        let clips: [VideoClip] = [clip("a"), clip("b")]
        let video = Video { clips }
        #expect(ids(video.clips) == ["a", "b"])
    }

    @Test func arrayOfMixedClipsKeepsTransitions() {
        let clips: [any Clip] = [clip("a"), Transition.dissolve(duration: 0.5), clip("b")]
        let video = Video { clips }
        #expect(video.clips.count == 3)
        #expect(video.clips[1] is Transition)
    }

    @Test func arraySplicesInPlaceBetweenSingleClips() {
        let video = Video {
            clip("first")
            ["b", "c"].map { clip($0) }
            clip("last")
        }
        #expect(ids(video.clips) == ["first", "b", "c", "last"])
    }

    /// Splicing a list must build the same timeline as writing the clips out.
    @Test func arrayMatchesTheSameClipsWrittenOut() {
        let spliced = Video { ["a", "b"].map { clip($0) } }
        let written = Video {
            clip("a")
            clip("b")
        }
        #expect(ids(spliced.clips) == ids(written.clips))
    }

    @Test func emptyArrayAddsNothing() {
        let none: [VideoClip] = []
        let video = Video {
            clip("only")
            none
        }
        #expect(ids(video.clips) == ["only"])
    }

    @Test func arrayInsideControlFlow() {
        let includeExtras = true
        let video = Video {
            clip("a")
            if includeExtras {
                ["x", "y"].map { clip($0) }
            }
        }
        #expect(ids(video.clips) == ["a", "x", "y"])
    }

    @Test func arrayInsideTrack() {
        let track = Track(at: 2.0, name: "B-Roll") { ["a", "b"].map { clip($0) } }
        #expect(ids(track.clips) == ["a", "b"])
    }

    @Test func imageClipArray() {
        let images = [PlatformImage(), PlatformImage()]
        let video = Video { images.map { ImageClip($0, duration: 1.0) } }
        #expect(video.clips.count == 2)
        #expect(video.clips.allSatisfy { $0 is ImageClip })
    }
}
