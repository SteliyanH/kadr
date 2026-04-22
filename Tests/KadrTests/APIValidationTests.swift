import Testing
import Kadr
import Foundation

// These tests validate that the API surface compiles correctly.
// They do NOT run — they only prove the type signatures are correct.

struct APIValidationTests {

    @Test func example1_helloWorld() async throws {
        let heroImage = PlatformImage()
        let musicURL = URL(fileURLWithPath: "/tmp/music.mp3")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        // Must compile: single image + audio
        _ = Video {
            ImageClip(heroImage, duration: 5.0)
        }
        .audio(url: musicURL)
        .exporter(to: outputURL)
    }

    @Test func example2_slideshow() async throws {
        let image1 = PlatformImage()
        let image2 = PlatformImage()
        let image3 = PlatformImage()
        let image4 = PlatformImage()
        let narrationURL = URL(fileURLWithPath: "/tmp/narration.mp3")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        _ = Video {
            ImageClip(image1)
            ImageClip(image2)
            ImageClip(image3)
            ImageClip(image4)
        }
        .audio(url: narrationURL)
        .exporter(to: outputURL)
    }

    @Test func example3_pairedClips() async throws {
        let image1 = PlatformImage()
        let image2 = PlatformImage()
        let image3 = PlatformImage()
        let audio1URL = URL(fileURLWithPath: "/tmp/a1.mp3")
        let audio2URL = URL(fileURLWithPath: "/tmp/a2.mp3")
        let audio3URL = URL(fileURLWithPath: "/tmp/a3.mp3")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        _ = Video {
            ImageClip(image1).withAudio(audio1URL)
            ImageClip(image2).withAudio(audio2URL)
            ImageClip(image3).withAudio(audio3URL)
        }
        .exporter(to: outputURL)
    }

    @Test func example4_silentSequence() async throws {
        let image1 = PlatformImage()
        let image2 = PlatformImage()
        let image3 = PlatformImage()
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        _ = Video {
            ImageClip(image1, duration: 2.0)
            ImageClip(image2, duration: 3.0)
            ImageClip(image3, duration: 1.5)
        }
        .exporter(to: outputURL)
    }

    @Test func example5_mergeVideos() async throws {
        let clip1URL = URL(fileURLWithPath: "/tmp/clip1.mov")
        let clip2URL = URL(fileURLWithPath: "/tmp/clip2.mov")
        let clip3URL = URL(fileURLWithPath: "/tmp/clip3.mov")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        _ = Video {
            VideoClip(url: clip1URL)
            VideoClip(url: clip2URL)
            VideoClip(url: clip3URL)
        }
        .exporter(to: outputURL)
    }

    @Test func example6_reverseClip() async throws {
        let clipURL = URL(fileURLWithPath: "/tmp/clip.mov")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        _ = Video {
            VideoClip(url: clipURL).reversed()
        }
        .exporter(to: outputURL)
    }

    @Test func example7_trimToRange() async throws {
        let clipURL = URL(fileURLWithPath: "/tmp/clip.mov")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        _ = Video {
            VideoClip(url: clipURL).trimmed(to: 5...20)
        }
        .exporter(to: outputURL)
    }

    @Test func example8_replaceAudio() async throws {
        let clipURL = URL(fileURLWithPath: "/tmp/clip.mov")
        let newMusicURL = URL(fileURLWithPath: "/tmp/new.mp3")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        _ = Video {
            VideoClip(url: clipURL).muted()
        }
        .audio(url: newMusicURL)
        .exporter(to: outputURL)
    }

    @Test func example9_multiClipWithTransition() async throws {
        let clip1URL = URL(fileURLWithPath: "/tmp/clip1.mov")
        let clip2URL = URL(fileURLWithPath: "/tmp/clip2.mov")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        _ = Video {
            VideoClip(url: clip1URL).trimmed(to: 0...10)
            Transition.fade(duration: 0.5)
            VideoClip(url: clip2URL).trimmed(to: 0...10)
        }
        .preset(.reelsAndShorts)
        .exporter(to: outputURL)
    }

    @Test func example10_progressStream() async throws {
        let longClipURL = URL(fileURLWithPath: "/tmp/long.mov")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

        let exporter = Video {
            VideoClip(url: longClipURL)
        }
        .preset(.cinema)
        .exporter(to: outputURL)

        // Validate exporter exists and has the right type
        #expect(exporter is Exporter)
    }
}
