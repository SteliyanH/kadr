import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreMedia

/// Tests for v0.18 — ``VideoClip/volume(_:)``.
///
/// Per-clip volume was the most conspicuous hole in the audio surface: `VideoClip`
/// could be muted wholesale or have its audio replaced, but "play this one at 30%"
/// had no expression at all. Every volume control lived on `AudioTrack`, which is
/// background audio, not the clips themselves.
struct ClipVolumeTests {

    private let preset: Preset = .auto

    private func sampleURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "mov") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample.mov"))
        }
        return url
    }

    /// Short video WITH an audio track: sample.png for the picture, sample.wav
    /// for the sound, encoded via the engine's own ImageEncoder.
    private func createVideoWithAudio(duration: TimeInterval = 2.0) async throws -> URL {
        guard let imageURL = Bundle.module.url(forResource: "sample", withExtension: "png"),
              let audioURL = Bundle.module.url(forResource: "sample", withExtension: "wav") else {
            throw KadrError.invalidURL(URL(fileURLWithPath: "sample"))
        }
        #if canImport(UIKit)
        guard let image = PlatformImage(contentsOfFile: imageURL.path) else {
            throw KadrError.invalidURL(imageURL)
        }
        #elseif canImport(AppKit)
        guard let image = PlatformImage(contentsOf: imageURL) else {
            throw KadrError.invalidURL(imageURL)
        }
        #endif
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_volume_av_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        return try await ImageEncoder.encode(
            image: image,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            preset: .square,
            audioURL: audioURL,
            to: outputURL
        )
    }

    // MARK: - The value

    @Test func defaultsToFullVolume() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
        #expect(clip.volumeLevel == 1.0)
    }

    @Test func volumeStoresTheLevel() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null")).volume(0.3)
        #expect(clip.volumeLevel == 0.3)
    }

    @Test func volumeIsChainableAndLastWins() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .volume(0.5)
            .volume(0.25)
        #expect(clip.volumeLevel == 0.25)
    }

    /// Volume must not disturb anything else on the clip. Before v0.18 every modifier
    /// re-invoked a 17-argument initialiser by hand, and the failure mode was a
    /// silently dropped property rather than a compile error — so this asserts the
    /// neighbours explicitly rather than trusting the copy.
    @Test func volumePreservesEveryOtherProperty() {
        let base = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .trimmed(to: 0...5)
            .speed(.flat(2.0))
            .opacity(0.4)
            .id(ClipID("hero"))
            .filter(.brightness(0.2))

        let quiet = base.volume(0.3)

        #expect(quiet.volumeLevel == 0.3)
        #expect(quiet.trimRange == base.trimRange)
        #expect(quiet.speedRate == base.speedRate)
        #expect(quiet.opacity == base.opacity)
        #expect(quiet.clipID == base.clipID)
        #expect(quiet.filters.count == base.filters.count)
        #expect(quiet.filterIDs == base.filterIDs)
        #expect(quiet.isMuted == base.isMuted)
    }

    /// `muted()` and `volume(0)` are different things, and the difference is not
    /// cosmetic: muting drops the track from the composition, while volume 0 keeps a
    /// silent track in the mix.
    @Test func volumeZeroIsNotTheSameAsMuted() {
        let silent = VideoClip(url: URL(fileURLWithPath: "/dev/null")).volume(0)
        #expect(silent.volumeLevel == 0)
        #expect(silent.isMuted == false)

        let muted = VideoClip(url: URL(fileURLWithPath: "/dev/null")).muted()
        #expect(muted.isMuted)
        #expect(muted.volumeLevel == 1.0)
    }

    @Test func volumeSurvivesLaterModifiers() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .volume(0.6)
            .trimmed(to: 0...2)
            .opacity(0.9)
        #expect(clip.volumeLevel == 0.6)
    }

    // MARK: - The engine

    @Test func compositionWithClipVolumeCarriesAnAudioMix() async throws {
        // Needs a clip whose source actually HAS an audio track — the mix
        // attenuates that segment. sample.mov is video-only, so synthesize a
        // short video+audio file (image + sample.wav) for this test.
        let url = try await createVideoWithAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await CompositionBuilder.build(
            from: [VideoClip(url: url).volume(0.3)],
            audioTracks: [],
            preset: preset
        )
        let mix = try #require(result.audioMix, "A clip at non-default volume must produce an audio mix")
        #expect(mix.inputParameters.isEmpty == false)
    }

    /// Counterpart to ``mutedClipContributesNoVolumeParameters``: a clip whose
    /// source has no audio track has no segment to attenuate either. Recording
    /// a volume for it anyway would attach mix parameters to an empty
    /// composition audio track — and that empty track fails the export
    /// preset compatibility check, silently routing the export through
    /// passthrough (https://github.com/SteliyanH/kadr/issues/201).
    @Test func audiolessClipVolumeProducesNoAudioMix() async throws {
        let url = try sampleURL() // sample.mov is video-only
        let result = try await CompositionBuilder.build(
            from: [VideoClip(url: url).volume(0.3)],
            audioTracks: [],
            preset: preset
        )
        #expect(result.audioMix == nil, "An audio-less clip has no segment to attenuate")
        #expect(
            result.composition.tracks(withMediaType: .audio).isEmpty,
            "No audio inserted ⇒ the composition must not keep an empty audio track"
        )
    }

    /// The mix exists only when something asks for it. A composition of full-volume
    /// clips and no background audio has nothing to mix, and building parameters
    /// anyway would put an `AVMutableAudioMix` on every export for no reason.
    @Test func fullVolumeClipsProduceNoAudioMix() async throws {
        let url = try sampleURL()
        let result = try await CompositionBuilder.build(
            from: [VideoClip(url: url)],
            audioTracks: [],
            preset: preset
        )
        #expect(result.audioMix == nil)
    }

    @Test func clipVolumeExports() async throws {
        let url = try sampleURL()
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: out) }

        let video = Video {
            VideoClip(url: url).trimmed(to: 0...1).volume(0.25)
        }
        _ = try await video.export(to: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
    }

    @Test func mutedClipContributesNoVolumeParameters() async throws {
        let url = try sampleURL()
        let result = try await CompositionBuilder.build(
            from: [VideoClip(url: url).muted().volume(0.3)],
            audioTracks: [],
            preset: preset
        )
        #expect(result.audioMix == nil, "A muted clip has no audio segment to attenuate")
    }
}
