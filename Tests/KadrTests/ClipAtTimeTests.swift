import Testing
import Foundation
import Kadr
import CoreMedia

/// Tests for the v0.6 ``Clip/startTime`` surface and the ``VideoClip/at(time:)`` /
/// ``ImageClip/at(time:)`` / ``TitleSequence/at(time:)`` modifiers — Tier 1 of the v0.6
/// multi-track timeline cycle. Uses a non-`@testable` import so a regression that
/// demotes any of the new public surface fails the build.
///
/// **Surface only.** Tier 1 ships the API; engine wiring lands in the multi-track engine
/// PR. These tests verify the surface contract — that values flow through the modifier
/// chain — not runtime behavior.
struct ClipAtTimeTests {

    // MARK: - Defaults

    @Test func defaultStartTimeIsNil() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let img = PlatformImage()
        #expect(VideoClip(url: url).startTime == nil)
        #expect(ImageClip(img, duration: 1.0).startTime == nil)
        #expect(TitleSequence("hello").startTime == nil)
    }

    @Test func transitionStartTimeIsNil() {
        // Transition keeps the protocol default (Transition isn't an addressable unit).
        let t: any Clip = Kadr.Transition.dissolve(duration: 0.5)
        #expect(t.startTime == nil)
    }

    // MARK: - VideoClip

    @Test func videoClipAtCMTime() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let t = CMTime(seconds: 2.5, preferredTimescale: 600)
        let clip = VideoClip(url: url).at(time: t)
        #expect(clip.startTime == t)
    }

    @Test func videoClipAtTimeInterval() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url).at(time: 2.5)
        #expect(clip.startTime != nil)
        #expect(CMTimeGetSeconds(clip.startTime!) == 2.5)
    }

    @Test func videoClipAtTimeSurvivesAllChains() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .at(time: 2.0)
            .trimmed(to: 0.0...5.0)
            .reversed()
            .muted()
            .speed(1.5)
            .filter(.brightness(0.1))
            .compositor { image, _ in image }
            .crop(at: .center, size: .normalized(width: 0.5, height: 0.5))
            .id("hero")
        #expect(clip.startTime != nil)
        #expect(CMTimeGetSeconds(clip.startTime!) == 2.0)
        #expect(clip.clipID == ClipID("hero"))
    }

    @Test func videoClipAtTimeBeforeAnyOtherModifier() {
        // Setting .at(time:) at the END of the chain also works.
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let clip = VideoClip(url: url)
            .trimmed(to: 0.0...5.0)
            .filter(.brightness(0.1))
            .at(time: 3.0)
        #expect(CMTimeGetSeconds(clip.startTime!) == 3.0)
    }

    // MARK: - ImageClip

    @Test func imageClipAtTime() {
        let img = PlatformImage()
        let clip = ImageClip(img, duration: 2.0).at(time: 1.5)
        #expect(CMTimeGetSeconds(clip.startTime!) == 1.5)
    }

    @Test func imageClipAtTimeSurvivesChain() {
        let img = PlatformImage()
        let url = URL(fileURLWithPath: "/tmp/audio.m4a")
        let clip = ImageClip(img, duration: 2.0)
            .at(time: 1.0)
            .background(.black)
            .withAudio(url)
            .duration(3.0)
            .id("hero")
        #expect(CMTimeGetSeconds(clip.startTime!) == 1.0)
    }

    // MARK: - TitleSequence

    @Test func titleSequenceAtTime() {
        let title = TitleSequence("Hello").at(time: 0.5)
        #expect(CMTimeGetSeconds(title.startTime!) == 0.5)
    }

    @Test func titleSequenceAtTimeSurvivesChain() {
        let title = TitleSequence("Hello")
            .at(time: 0.5)
            .id("intro")
        #expect(CMTimeGetSeconds(title.startTime!) == 0.5)
        #expect(title.clipID == ClipID("intro"))
    }

    // MARK: - Generic protocol access

    @Test func clipsExposeStartTimeViaProtocol() {
        // [any Clip] iteration can read startTime regardless of concrete type.
        let img = PlatformImage()
        let clips: [any Clip] = [
            VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")).at(time: 0),
            ImageClip(img, duration: 1.0).at(time: 1),
            TitleSequence("hi").at(time: 2),
            ImageClip(img, duration: 1.0),    // no .at(...) — startTime nil
            Kadr.Transition.dissolve(duration: 0.5),  // protocol default — nil
        ]
        let seconds = clips.map { $0.startTime.map { CMTimeGetSeconds($0) } }
        #expect(seconds == [0, 1, 2, nil, nil])
    }

    @Test func videoExposesClipStartTimesAfterBuilding() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)              // chain, no startTime
            ImageClip(img, duration: 2.0).at(time: 5)  // free-floating
        }
        let times = video.clips.map { $0.startTime.map { CMTimeGetSeconds($0) } }
        #expect(times == [nil, 5])
    }
}
