import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

struct SugarTests {

    private func testOutputURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func loadTestVideoURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "mov") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.mov"))
        }
        return url
    }

    private func loadTestAudioURL() throws -> URL {
        if let url = Bundle.module.url(forResource: "sample", withExtension: "mp3") { return url }
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "wav") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.wav"))
        }
        return url
    }

    // MARK: - Timecode

    @Test func timecodeFormatBasic() {
        let tc = Timecode(fps: .fps30)
        #expect(tc.format(.zero) == "00:00:00:00")
        #expect(tc.format(CMTime(seconds: 1.0, preferredTimescale: 600)) == "00:00:01:00")
        #expect(tc.format(CMTime(seconds: 65.5, preferredTimescale: 600)) == "00:01:05:15")
        #expect(tc.format(CMTime(seconds: 3661.0, preferredTimescale: 600)) == "01:01:01:00")
    }

    @Test func timecodeFormatDifferentFrameRates() {
        // Same wall time, different frame counts
        let oneAndAHalfSeconds = CMTime(seconds: 1.5, preferredTimescale: 600)
        #expect(Timecode(fps: .fps24).format(oneAndAHalfSeconds) == "00:00:01:12")
        #expect(Timecode(fps: .fps30).format(oneAndAHalfSeconds) == "00:00:01:15")
        #expect(Timecode(fps: .fps60).format(oneAndAHalfSeconds) == "00:00:01:30")
    }

    @Test func timecodeFormatNegativeClamps() {
        let tc = Timecode(fps: .fps30)
        let negative = CMTime(seconds: -5, preferredTimescale: 600)
        #expect(tc.format(negative) == "00:00:00:00")
    }

    @Test func timecodeRoundTrip() {
        let tc = Timecode(fps: .fps30)
        let original = CMTime(value: 1965, timescale: 30)  // exactly 65.5s
        let formatted = tc.format(original)
        let parsed = tc.parse(formatted)
        #expect(parsed == original)
    }

    @Test func timecodeParseValid() {
        let tc = Timecode(fps: .fps30)
        let parsed = tc.parse("00:01:05:15")
        // 65.5 seconds = 1965 frames at 30fps
        #expect(parsed == CMTime(value: 1965, timescale: 30))
    }

    @Test func timecodeParseInvalid() {
        let tc = Timecode(fps: .fps30)
        #expect(tc.parse("nope") == nil)
        #expect(tc.parse("00:00:00") == nil)             // missing frames component
        #expect(tc.parse("00:00:00:30") == nil)          // frames out of range at 30fps
        #expect(tc.parse("00:60:00:00") == nil)          // minutes out of range
        #expect(tc.parse("00:00:60:00") == nil)          // seconds out of range
        #expect(tc.parse("-1:00:00:00") == nil)
    }

    @Test func timecodeCustomFrameRate() {
        let tc = Timecode(fps: .custom(48))
        let oneSecond = CMTime(seconds: 1.0, preferredTimescale: 600)
        #expect(tc.format(oneSecond) == "00:00:01:00")
        #expect(tc.parse("00:00:01:24") == CMTime(value: 72, timescale: 48))  // 1.5s
    }

    // MARK: - BackgroundMusic

    @Test func backgroundMusicDefaults() {
        let url = URL(fileURLWithPath: "/tmp/music.mp3")
        let bg = BackgroundMusic(url: url)
        #expect(bg.url == url)
        #expect(bg.volume == 0.6)
        #expect(bg.fadeIn == 0.5)
        #expect(bg.fadeOut == 1.0)
        #expect(bg.duckingLevel == 0.3)
    }

    @Test func backgroundMusicCustomValues() {
        let url = URL(fileURLWithPath: "/tmp/music.mp3")
        let bg = BackgroundMusic(url: url, volume: 0.4, fadeIn: 1.0, fadeOut: 2.0, duckingLevel: 0.1)
        #expect(bg.volume == 0.4)
        #expect(bg.fadeIn == 1.0)
        #expect(bg.fadeOut == 2.0)
        #expect(bg.duckingLevel == 0.1)
    }

    @Test func backgroundMusicCanDisableDucking() {
        let bg = BackgroundMusic(url: URL(fileURLWithPath: "/tmp/m.mp3"), duckingLevel: nil)
        #expect(bg.duckingLevel == nil)
        let track = bg.audioTrack
        #expect(track.duckingLevel == nil)
    }

    @Test func videoBackgroundMusicURLSugar() {
        let url = URL(fileURLWithPath: "/tmp/music.mp3")
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .backgroundMusic(url: url)
        #expect(video.audioTracks.count == 1)
        #expect(video.audioTracks.first?.url == url)
        #expect(video.audioTracks.first?.volumeLevel == 0.6)
        #expect(video.audioTracks.first?.duckingLevel == 0.3)
    }

    @Test func videoBackgroundMusicSpecOverload() {
        let url = URL(fileURLWithPath: "/tmp/music.mp3")
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/x.mov")).trimmed(to: 0...3)
        }
        .backgroundMusic(BackgroundMusic(url: url, volume: 0.4, duckingLevel: nil))
        #expect(video.audioTracks.first?.volumeLevel == 0.4)
        #expect(video.audioTracks.first?.duckingLevel == nil)
    }

    @Test func exportWithBackgroundMusic() async throws {
        let videoURL = try loadTestVideoURL()
        let audioURL = try loadTestAudioURL()
        let outputURL = testOutputURL("bg_music")

        let result = try await Video {
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .backgroundMusic(url: audioURL)
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        let asset = AVURLAsset(url: result)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty)
        try? FileManager.default.removeItem(at: result)
    }

    // MARK: - TitleSequence

    @Test func titleSequenceDefaults() {
        let title = TitleSequence("HELLO")
        #expect(title.text == "HELLO")
        #expect(title.style == .default)
        #expect(CMTimeGetSeconds(title.duration) == 3.0)
    }

    @Test func titleSequenceTimeIntervalDuration() {
        let title = TitleSequence("MY TITLE", duration: 5.0)
        #expect(abs(CMTimeGetSeconds(title.duration) - 5.0) < 0.001)
    }

    @Test func titleSequenceCMTimeDuration() {
        let exactTwoSeconds = CMTime(value: 60, timescale: 30)
        let title = TitleSequence("TITLE", duration: exactTwoSeconds)
        #expect(title.duration == exactTwoSeconds)
    }

    @Test func titleSequenceCustomStyle() {
        let style = TextStyle(fontSize: 96, alignment: .center, weight: .bold)
        let title = TitleSequence("BIG", duration: 2.0, style: style, background: .white)
        #expect(title.style == style)
    }

    @Test func titleSequenceRendersImage() {
        let title = TitleSequence("X", duration: 1.0)
        let image = title.render(at: CGSize(width: 200, height: 200))
        #expect(image.size.width == 200)
        #expect(image.size.height == 200)
    }

    @Test func exportWithTitleSequence() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("title_sequence")

        let result = try await Video {
            TitleSequence("HELLO", duration: 1.5,
                          style: TextStyle(fontSize: 80, alignment: .center, weight: .bold))
            VideoClip(url: videoURL).trimmed(to: 0...2)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        // 1.5s title + 2s clip = 3.5s total
        let asset = AVURLAsset(url: result)
        let dur = CMTimeGetSeconds(try await asset.load(.duration))
        #expect(dur > 3.0)
        #expect(dur < 4.0)
        try? FileManager.default.removeItem(at: result)
    }

    @Test func exportWithTitleAndTransition() async throws {
        let videoURL = try loadTestVideoURL()
        let outputURL = testOutputURL("title_transition")

        let result = try await Video {
            TitleSequence("INTRO", duration: 2.0)
            Transition.fade(duration: 0.5)
            VideoClip(url: videoURL).trimmed(to: 0...3)
        }
        .export(to: outputURL)

        #expect(FileManager.default.fileExists(atPath: result.path))
        try? FileManager.default.removeItem(at: result)
    }
}
