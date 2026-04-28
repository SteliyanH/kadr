import Testing
import Foundation
import Kadr
import CoreMedia

/// Tests for the v0.6 ``Track`` block — Tier 2 of the v0.6 multi-track timeline cycle.
/// Surface only; engine wiring lands in Tier 4.
struct TrackTests {

    // MARK: - Construction

    @Test func parameterlessInitStartsAtZero() {
        let track = Track {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        #expect(track.startTime == .zero)
        #expect(track.clips.count == 1)
    }

    @Test func atCMTimeInit() {
        let t = CMTime(seconds: 2.5, preferredTimescale: 600)
        let track = Track(at: t) {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        #expect(track.startTime == t)
    }

    @Test func atTimeIntervalInit() {
        let track = Track(at: 1.5) {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        #expect(track.startTime != nil)
        #expect(CMTimeGetSeconds(track.startTime!) == 1.5)
    }

    // MARK: - Name (v0.7)

    @Test func nameDefaultsToNilOnAllInitForms() {
        let bare = Track { ImageClip(PlatformImage(), duration: 1.0) }
        let cmt = Track(at: CMTime(seconds: 1, preferredTimescale: 600)) {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        let ti = Track(at: 1.0) { ImageClip(PlatformImage(), duration: 1.0) }
        #expect(bare.name == nil)
        #expect(cmt.name == nil)
        #expect(ti.name == nil)
    }

    @Test func parameterlessInitWithName() {
        let track = Track(name: "B-Roll") {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        #expect(track.name == "B-Roll")
        #expect(track.startTime == .zero)
    }

    @Test func atCMTimeInitWithName() {
        let t = CMTime(seconds: 2.5, preferredTimescale: 600)
        let track = Track(at: t, name: "Cutaway") {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        #expect(track.name == "Cutaway")
        #expect(track.startTime == t)
    }

    @Test func atTimeIntervalInitWithName() {
        let track = Track(at: 1.5, name: "Reaction") {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        #expect(track.name == "Reaction")
        #expect(CMTimeGetSeconds(track.startTime!) == 1.5)
    }

    // MARK: - Duration

    @Test func durationSumsClipDurations() {
        let img = PlatformImage()
        let track = Track {
            ImageClip(img, duration: 2.0)
            ImageClip(img, duration: 3.0)
        }
        #expect(CMTimeGetSeconds(track.duration) == 5.0)
    }

    @Test func durationIncludesTransitions() {
        let img = PlatformImage()
        let track = Track {
            ImageClip(img, duration: 2.0)
            Kadr.Transition.dissolve(duration: 0.5)
            ImageClip(img, duration: 2.0)
        }
        #expect(CMTimeGetSeconds(track.duration) == 4.5)
    }

    // MARK: - Track in a Video composition

    @Test func tracksAppearInVideoClips() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 2.0)
            Track(at: 1.0) {
                ImageClip(img, duration: 1.0)
            }
        }
        #expect(video.clips.count == 2)
        #expect(video.clips[0] is ImageClip)
        #expect(video.clips[1] is Track)
        let track = video.clips[1] as? Track
        #expect(CMTimeGetSeconds(track!.startTime!) == 1.0)
    }

    @Test func trackClipsAreAddressableInternally() {
        // Clips inside a Track keep their own clipIDs. KadrUI and other consumers can
        // recurse into Track.clips to read them.
        let img = PlatformImage()
        let track = Track(at: 0) {
            ImageClip(img, duration: 1.0).id("intro")
            ImageClip(img, duration: 1.0).id("body")
        }
        let ids = track.clips.compactMap { $0.clipID?.rawValue }
        #expect(ids == ["intro", "body"])
    }

    @Test func trackItselfHasNilClipID() {
        // Track conforms to Clip but doesn't carry an ID itself — its inner clips do.
        let track = Track(at: 0) {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        #expect(track.clipID == nil)
    }

    // MARK: - Generic protocol access

    @Test func trackParticipatesInClipProtocol() {
        // [any Clip] iteration handles Track alongside concrete clip types.
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 2.0)
            Track(at: 1.0) { ImageClip(img, duration: 1.0) }
            ImageClip(img, duration: 1.0).at(time: 5.0)
        }
        let kinds: [String] = video.clips.map {
            if $0 is Track { return "Track" }
            if $0 is ImageClip { return "ImageClip" }
            return "Other"
        }
        #expect(kinds == ["ImageClip", "Track", "ImageClip"])
    }

    @Test func nestedTracksAllowed() {
        // Track-in-track is structurally legal (Track conforms to Clip; VideoBuilder
        // accepts any Clip). Engine semantics for nested tracks land with Tier 4.
        let img = PlatformImage()
        let outer = Track(at: 1.0) {
            ImageClip(img, duration: 1.0)
            Track(at: 0.5) {
                ImageClip(img, duration: 0.5)
            }
        }
        #expect(outer.clips.count == 2)
        #expect(outer.clips[1] is Track)
    }
}
