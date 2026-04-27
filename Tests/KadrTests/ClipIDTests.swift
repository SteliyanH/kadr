import Testing
import Foundation
import Kadr
import CoreMedia

/// Public-API tests for the v0.4.1 ``ClipID`` addition. Uses a non-`@testable` import so
/// a regression that demotes any of the new public surface fails the build.
struct ClipIDTests {

    // MARK: - ClipID type

    @Test func defaultIDIsNil() {
        let img = PlatformImage()
        let clip = ImageClip(img, duration: 1.0)
        #expect(clip.clipID == nil)
    }

    @Test func stringLiteralInitWorks() {
        let id: ClipID = "intro"
        #expect(id.rawValue == "intro")
        #expect(id.description == "intro")
    }

    @Test func clipIDIsHashable() {
        let a: ClipID = "a"
        let b: ClipID = "a"
        let c: ClipID = "c"
        #expect(a == b)
        #expect(a != c)
        let set: Set<ClipID> = [a, b, c]
        #expect(set.count == 2)
    }

    // MARK: - .id(_:) on each clip type

    @Test func imageClipIDIsAssignable() {
        let img = PlatformImage()
        let clip = ImageClip(img, duration: 1.0).id("intro")
        #expect(clip.clipID == ClipID("intro"))
    }

    @Test func videoClipIDIsAssignable() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url).id("body")
        #expect(clip.clipID == ClipID("body"))
    }

    @Test func titleSequenceIDIsAssignable() {
        let title = TitleSequence("Hello").id("title")
        #expect(title.clipID == ClipID("title"))
    }

    // MARK: - ID survives modifier chains

    @Test func videoClipIDSurvivesTrim() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .id("body")
            .trimmed(to: 0.0...5.0)
        #expect(clip.clipID == ClipID("body"))
    }

    @Test func videoClipIDSurvivesAllChains() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .id("body")
            .trimmed(to: 0.0...5.0)
            .reversed()
            .muted()
            .speed(2.0)
            .filter(.brightness(0.1))
        #expect(clip.clipID == ClipID("body"))
    }

    @Test func imageClipIDSurvivesAllChains() {
        let img = PlatformImage()
        let url = URL(fileURLWithPath: "/tmp/audio.m4a")
        let clip = ImageClip(img, duration: 1.0)
            .id("hero")
            .background(.black)
            .withAudio(url)
            .duration(2.0)
        #expect(clip.clipID == ClipID("hero"))
    }

    // MARK: - Generic protocol access

    @Test func clipProtocolExposesIDForMediaClips() {
        let img = PlatformImage()
        let clips: [any Clip] = [
            ImageClip(img, duration: 1.0).id("a"),
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).id("b"),
            TitleSequence("hi").id("c"),
        ]
        let ids = clips.compactMap { $0.clipID?.rawValue }
        #expect(ids == ["a", "b", "c"])
    }

    @Test func transitionHasNilClipID() {
        // Transition deliberately doesn't carry a ClipID — it's not addressable.
        let transition: any Clip = Kadr.Transition.dissolve(duration: 0.5)
        #expect(transition.clipID == nil)
    }

    // MARK: - ID on Video.clips after building

    @Test func videoClipsExposeIDsAfterBuilding() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0).id("intro")
            Kadr.Transition.dissolve(duration: 0.5)
            ImageClip(img, duration: 2.0).id("body")
        }
        let ids = video.clips.map { $0.clipID?.rawValue }
        #expect(ids == ["intro", nil, "body"])
    }
}
