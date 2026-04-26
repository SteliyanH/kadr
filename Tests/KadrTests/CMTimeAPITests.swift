import Testing
import Foundation
@testable import Kadr
import CoreMedia

/// Verifies that the public time-related API surface accepts and preserves `CMTime`
/// values losslessly, so callers can express frame-accurate edits at specific frame rates.
struct CMTimeAPITests {

    // MARK: - Transition stores CMTime exactly

    @Test func transitionFadePreservesCMTime() {
        let oneFrameAt30 = CMTime(value: 1, timescale: 30)
        let t = Transition.fade(duration: oneFrameAt30)
        #expect(t.duration == oneFrameAt30)
        #expect(t.duration.timescale == 30)
        #expect(t.duration.value == 1)
    }

    @Test func transitionDissolvePreservesCMTime() {
        let oneFrameAt60 = CMTime(value: 1, timescale: 60)
        let t = Transition.dissolve(duration: oneFrameAt60)
        #expect(t.duration == oneFrameAt60)
        #expect(t.duration.timescale == 60)
    }

    @Test func transitionSlidePreservesCMTime() {
        let halfFrameAt24 = CMTime(value: 1, timescale: 48)
        let t = Transition.slide(direction: .fromLeft, duration: halfFrameAt24)
        #expect(t.duration == halfFrameAt24)
    }

    @Test func transitionTimeIntervalOverloadStillWorks() {
        // The factory overload exists for ergonomics
        let t = Transition.fade(duration: 0.5)
        #expect(abs(CMTimeGetSeconds(t.duration) - 0.5) < 0.001)
    }

    // MARK: - VideoClip trim preserves CMTimeRange

    @Test func videoClipTrimmedCMTimeRangePreserved() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        // 5 frames in at 30fps for 30 frames (1 second)
        let start = CMTime(value: 5, timescale: 30)
        let dur = CMTime(value: 30, timescale: 30)
        let range = CMTimeRange(start: start, duration: dur)
        let clip = VideoClip(url: url).trimmed(range)
        #expect(clip.trimRange?.start == start)
        #expect(clip.trimRange?.duration == dur)
        // Verify the synchronous duration getter also preserves precision
        #expect(clip.duration == dur)
    }

    @Test func videoClipTrimTimeIntervalOverloadStillWorks() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clip = VideoClip(url: url).trimmed(to: 0...10)
        // At timescale 600 the values are 0 and 6000 — exact
        #expect(clip.trimRange?.start == CMTime(value: 0, timescale: 600))
        #expect(clip.trimRange?.duration == CMTime(value: 6000, timescale: 600))
    }

    // MARK: - ImageClip duration

    @Test func imageClipCMTimeDuration() {
        let img = PlatformImage()
        let twoFrames = CMTime(value: 2, timescale: 30)
        let clip = ImageClip(img, duration: twoFrames)
        #expect(clip.duration == twoFrames)
    }

    @Test func imageClipDurationModifierWithCMTime() {
        let img = PlatformImage()
        let custom = CMTime(value: 7, timescale: 24)
        let clip = ImageClip(img).duration(custom)
        #expect(clip.duration == custom)
    }

    // MARK: - AudioTrack fade

    @Test func audioTrackCMTimeFades() {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        let half = CMTime(value: 1, timescale: 2)
        let track = AudioTrack(url: url).fadeIn(half).fadeOut(half)
        #expect(track.fadeInDuration == half)
        #expect(track.fadeOutDuration == half)
    }

    // MARK: - Frame-accurate composition

    @Test func framePerfectFadeHalvingViaTimescale() {
        // fade(duration:) of one frame at 30fps should halve cleanly via timescale doubling.
        // This is what CompositionBuilder.outgoingTail uses internally for fade transitions.
        let oneFrame = CMTime(value: 1, timescale: 30)
        let half = CMTimeMultiplyByRatio(oneFrame, multiplier: 1, divisor: 2)
        // Result should be 1/60 — exact, no float drift
        #expect(half.value == 1)
        #expect(half.timescale == 60)
        #expect(CMTimeGetSeconds(half) == 1.0 / 60.0)
    }
}
