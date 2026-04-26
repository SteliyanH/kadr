import Testing
import Foundation
import Kadr
import CoreGraphics
import CoreMedia

/// Tests for the v0.4.0 public introspection surface — clips, overlays, audio tracks,
/// preset, and crop must be publicly readable so callers (e.g. KadrUI) can render their
/// own timeline / preview / hit-testing UI without re-deriving state from the DSL.
///
/// These tests intentionally use a non-`@testable` import so a regression that demotes
/// any of these properties back to `internal` will fail the build, not just the tests.
struct IntrospectionTests {

    // MARK: - Video properties are publicly readable

    @Test func clipsAreReadable() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
            ImageClip(img, duration: 2.0)
        }
        #expect(video.clips.count == 2)
        #expect(video.clips[0] is ImageClip)
        #expect(video.clips[1] is ImageClip)
    }

    @Test func clipsPreserveOrderIncludingTransitions() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 2.0)
            Transition.dissolve(duration: 0.5)
            ImageClip(img, duration: 2.0)
        }
        #expect(video.clips.count == 3)
        #expect(video.clips[1] is Transition)
    }

    @Test func overlaysAreReadable() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .overlay(TextOverlay("Hello").id("title"))
        .overlay(StickerOverlay(img).id("sticker"))

        #expect(video.overlays.count == 2)
        #expect(video.overlays[0].layerID == LayerID("title"))
        #expect(video.overlays[1].layerID == LayerID("sticker"))
    }

    @Test func overlaysPreserveDeclarationOrder() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .overlay(TextOverlay("A").id("a"))
        .overlay(TextOverlay("B").id("b"))
        .overlay(TextOverlay("C").id("c"))

        let ids = video.overlays.compactMap { $0.layerID?.rawValue }
        #expect(ids == ["a", "b", "c"])
    }

    @Test func audioTracksAreReadable() {
        let img = PlatformImage()
        let url = URL(fileURLWithPath: "/tmp/music.m4a")
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .audio { AudioTrack(url: url).volume(0.5) }

        #expect(video.audioTracks.count == 1)
        #expect(video.audioTracks[0].url == url)
        #expect(video.audioTracks[0].volumeLevel == 0.5)
    }

    @Test func presetIsReadable() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .preset(.cinema)

        // Preset doesn't conform to Equatable so we read its public derivatives.
        #expect(video.preset.resolution == CGSize(width: 1920, height: 1080))
        #expect(video.preset.frameRate == 24)
    }

    @Test func presetDefaultsToAuto() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        #expect(video.preset.resolution == CGSize(width: 1080, height: 1920))
        #expect(video.preset.frameRate == 30)
    }

    @Test func cropIsNilByDefault() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        #expect(video.crop == nil)
    }

    @Test func cropIsReadableAfterApplied() throws {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .crop(at: .center, size: .normalized(width: 0.8, height: 0.8))

        let crop = try #require(video.crop)
        #expect(crop.position == .center)
        #expect(crop.size == .normalized(width: 0.8, height: 0.8))
        #expect(crop.anchor == .center)
    }

    // MARK: - Per-clip property exposure

    @Test func videoClipPropertiesAreReadable() {
        let url = URL(fileURLWithPath: "/tmp/video.mov")
        let clip = VideoClip(url: url)
            .trimmed(to: 0.0...5.0)
            .reversed()
            .muted()
            .filter(.brightness(0.2))

        #expect(clip.url == url)
        #expect(clip.trimRange != nil)
        #expect(clip.isReversed == true)
        #expect(clip.isMuted == true)
        #expect(clip.filters.count == 1)
    }

    @Test func imageClipPropertiesAreReadable() {
        let img = PlatformImage()
        let audioURL = URL(fileURLWithPath: "/tmp/narration.m4a")
        let clip = ImageClip(img, duration: 4.0)
            .background(.black)
            .withAudio(audioURL)

        #expect(clip.duration == CMTime(seconds: 4.0, preferredTimescale: 600))
        #expect(clip.backgroundColor != nil)
        #expect(clip.audioURL == audioURL)
    }

    @Test func audioTrackPropertiesAreReadable() {
        let url = URL(fileURLWithPath: "/tmp/music.m4a")
        let track = AudioTrack(url: url)
            .volume(0.6)
            .fadeIn(1.0)
            .fadeOut(2.0)
            .ducking(0.3)

        #expect(track.url == url)
        #expect(track.volumeLevel == 0.6)
        #expect(track.fadeInDuration == CMTime(seconds: 1.0, preferredTimescale: 600))
        #expect(track.fadeOutDuration == CMTime(seconds: 2.0, preferredTimescale: 600))
        #expect(track.duckingLevel == 0.3)
    }

    // MARK: - Preset.resolution / frameRate exposure

    @Test func presetResolutionsAreCorrect() {
        #expect(Preset.auto.resolution == CGSize(width: 1080, height: 1920))
        #expect(Preset.reelsAndShorts.resolution == CGSize(width: 1080, height: 1920))
        #expect(Preset.tiktok.resolution == CGSize(width: 1080, height: 1920))
        #expect(Preset.square.resolution == CGSize(width: 1080, height: 1080))
        #expect(Preset.cinema.resolution == CGSize(width: 1920, height: 1080))
        #expect(Preset.custom(width: 720, height: 1280, frameRate: 60, codec: .h264).resolution
                == CGSize(width: 720, height: 1280))
    }

    @Test func presetFrameRatesAreCorrect() {
        #expect(Preset.auto.frameRate == 30)
        #expect(Preset.cinema.frameRate == 24)
        #expect(Preset.custom(width: 1080, height: 1920, frameRate: 60, codec: .h264).frameRate == 60)
    }
}
