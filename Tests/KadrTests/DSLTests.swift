import Testing
import Foundation
@testable import Kadr
import CoreMedia

struct DSLTests {

    // MARK: - VideoBuilder

    @Test func videoBuilderSingleClip() {
        let image = PlatformImage()
        let video = Video {
            ImageClip(image, duration: 5.0)
        }
        #expect(video.clips.count == 1)
    }

    @Test func videoBuilderMultipleClips() {
        let image = PlatformImage()
        let video = Video {
            ImageClip(image, duration: 1.0)
            ImageClip(image, duration: 2.0)
            ImageClip(image, duration: 3.0)
        }
        #expect(video.clips.count == 3)
    }

    @Test func videoBuilderMixedClipTypes() {
        let image = PlatformImage()
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let video = Video {
            ImageClip(image, duration: 1.0)
            VideoClip(url: url)
            ImageClip(image, duration: 2.0)
        }
        #expect(video.clips.count == 3)
        #expect(video.clips[0] is ImageClip)
        #expect(video.clips[1] is VideoClip)
        #expect(video.clips[2] is ImageClip)
    }

    // MARK: - ImageClip

    @Test func imageClipDefaultDuration() {
        let image = PlatformImage()
        let clip = ImageClip(image)
        let seconds = CMTimeGetSeconds(clip.duration)
        #expect(seconds > 2.9 && seconds < 3.1)
    }

    @Test func imageClipCustomDuration() {
        let image = PlatformImage()
        let clip = ImageClip(image, duration: 7.0)
        let seconds = CMTimeGetSeconds(clip.duration)
        #expect(seconds > 6.9 && seconds < 7.1)
    }

    @Test func imageClipDurationModifier() {
        let image = PlatformImage()
        let clip = ImageClip(image).duration(10.0)
        let seconds = CMTimeGetSeconds(clip.duration)
        #expect(seconds > 9.9 && seconds < 10.1)
    }

    @Test func imageClipWithAudio() {
        let image = PlatformImage()
        let audioURL = URL(fileURLWithPath: "/tmp/test.mp3")
        let clip = ImageClip(image).withAudio(audioURL)
        #expect(clip.audioURL == audioURL)
    }

    @Test func imageClipBackground() {
        let image = PlatformImage()
        let clip = ImageClip(image).background(.red)
        #expect(clip.backgroundColor != nil)
    }

    // MARK: - VideoClip

    @Test func videoClipInit() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clip = VideoClip(url: url)
        #expect(clip.url == url)
        #expect(clip.trimRange == nil)
        #expect(!clip.isReversed)
        #expect(!clip.isMuted)
        #expect(clip.replacementAudioURL == nil)
    }

    @Test func videoClipTrimmed() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clip = VideoClip(url: url).trimmed(to: 5...20)
        #expect(clip.trimRange == 5...20)
    }

    @Test func videoClipReversed() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clip = VideoClip(url: url).reversed()
        #expect(clip.isReversed)
    }

    @Test func videoClipMuted() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clip = VideoClip(url: url).muted()
        #expect(clip.isMuted)
    }

    @Test func videoClipWithAudio() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let audioURL = URL(fileURLWithPath: "/tmp/test.mp3")
        let clip = VideoClip(url: url).withAudio(audioURL)
        #expect(clip.isMuted)
        #expect(clip.replacementAudioURL == audioURL)
    }

    @Test func videoClipModifierChaining() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clip = VideoClip(url: url)
            .trimmed(to: 5...15)
            .muted()
        #expect(clip.trimRange == 5...15)
        #expect(clip.isMuted)
    }

    // MARK: - AudioTrack

    @Test func audioTrackInit() {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        let track = AudioTrack(url: url)
        #expect(track.url == url)
        #expect(track.volumeLevel == 1.0)
        #expect(track.fadeInDuration == 0)
        #expect(track.fadeOutDuration == 0)
    }

    @Test func audioTrackVolume() {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        let track = AudioTrack(url: url).volume(0.5)
        #expect(track.volumeLevel == 0.5)
    }

    @Test func audioTrackFades() {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        let track = AudioTrack(url: url).fadeIn(1.0).fadeOut(2.0)
        #expect(track.fadeInDuration == 1.0)
        #expect(track.fadeOutDuration == 2.0)
    }

    // MARK: - Video modifiers

    @Test func videoAudioURL() {
        let image = PlatformImage()
        let audioURL = URL(fileURLWithPath: "/tmp/test.mp3")
        let video = Video {
            ImageClip(image)
        }
        .audio(url: audioURL)
        #expect(video.audioTracks.count == 1)
        #expect(video.audioTracks.first?.url == audioURL)
    }

    @Test func videoAudioBuilder() {
        let image = PlatformImage()
        let url1 = URL(fileURLWithPath: "/tmp/a1.mp3")
        let url2 = URL(fileURLWithPath: "/tmp/a2.mp3")
        let video = Video {
            ImageClip(image)
        }
        .audio {
            AudioTrack(url: url1).volume(0.8)
            AudioTrack(url: url2).fadeIn(1.0)
        }
        #expect(video.audioTracks.count == 2)
    }

    @Test func videoPreset() {
        let image = PlatformImage()
        let video = Video {
            ImageClip(image)
        }
        .preset(.cinema)
        #expect(video.preset.frameRate == 24)
    }

    @Test func videoDefaultPreset() {
        let image = PlatformImage()
        let video = Video {
            ImageClip(image)
        }
        #expect(video.preset.frameRate == 30)
    }

    // MARK: - Preset

    @Test func presetResolutions() {
        #expect(Preset.reelsAndShorts.resolution == CGSize(width: 1080, height: 1920))
        #expect(Preset.tiktok.resolution == CGSize(width: 1080, height: 1920))
        #expect(Preset.square.resolution == CGSize(width: 1080, height: 1080))
        #expect(Preset.cinema.resolution == CGSize(width: 1920, height: 1080))
    }

    @Test func presetCodecs() {
        #expect(Preset.reelsAndShorts.codec == .hevc)
        #expect(Preset.tiktok.codec == .h264)
        #expect(Preset.cinema.codec == .h264)
    }

    // MARK: - Transition

    @Test func transitionDuration() {
        let t = Transition.fade(duration: 0.5)
        let seconds = CMTimeGetSeconds(t.duration)
        #expect(seconds > 0.4 && seconds < 0.6)
    }

    @Test func slideDirections() {
        _ = Transition.slide(direction: .fromLeft, duration: 1.0)
        _ = Transition.slide(direction: .fromRight, duration: 1.0)
        _ = Transition.slide(direction: .fromTop, duration: 1.0)
        _ = Transition.slide(direction: .fromBottom, duration: 1.0)
    }

    // MARK: - Video duration

    @Test func videoDurationComputedFromClips() {
        let image = PlatformImage()
        let video = Video {
            ImageClip(image, duration: 2.0)
            ImageClip(image, duration: 3.0)
        }
        let seconds = CMTimeGetSeconds(video.duration)
        #expect(seconds > 4.9 && seconds < 5.1)
    }

    // MARK: - Codec

    @Test func codecEquatable() {
        #expect(Codec.h264 != Codec.hevc)
    }
}
