import Testing
import CoreMedia
import AVFoundation
import Foundation
@testable import Kadr

/// Tests for v0.9.1 — `AudioTrack.speed(_:algorithm:)`.
/// Coverage: surface, field preservation across modifiers, default algorithm,
/// AVFoundation algorithm bridge.
struct AudioSpeedTests {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    // MARK: - Surface

    @Test func defaultSpeedIsOne() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
        #expect(t.speedRate == 1.0)
        #expect(t.pitchAlgorithm == .spectral)
    }

    @Test func speedModifierStoresRate() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null")).speed(1.5)
        #expect(t.speedRate == 1.5)
        #expect(t.pitchAlgorithm == .spectral)  // default
    }

    @Test func speedModifierAcceptsExplicitAlgorithm() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .speed(1.25, algorithm: .timeDomain)
        #expect(t.speedRate == 1.25)
        #expect(t.pitchAlgorithm == .timeDomain)
    }

    @Test func varispeedAlgorithmIsExposed() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .speed(2.0, algorithm: .varispeed)
        #expect(t.pitchAlgorithm == .varispeed)
    }

    // MARK: - Field preservation across modifiers

    @Test func volumeModifierPreservesSpeed() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .speed(1.5, algorithm: .timeDomain)
            .volume(0.7)
        #expect(t.speedRate == 1.5)
        #expect(t.pitchAlgorithm == .timeDomain)
        #expect(t.volumeLevel == 0.7)
    }

    @Test func fadeModifiersPreserveSpeed() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .speed(0.8)
            .fadeIn(1.0)
            .fadeOut(2.0)
        #expect(t.speedRate == 0.8)
        #expect(CMTimeGetSeconds(t.fadeInDuration) == 1.0)
        #expect(CMTimeGetSeconds(t.fadeOutDuration) == 2.0)
    }

    @Test func crossfadeModifierPreservesSpeed() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .speed(1.5)
            .crossfade(1.0)
        #expect(t.speedRate == 1.5)
        #expect(t.crossfadeDuration != nil)
    }

    @Test func volumeRampModifierPreservesSpeed() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .speed(1.5, algorithm: .timeDomain)
            .volumeRamp(start: 1.0, end: 0.5, during: 0...1)
        #expect(t.speedRate == 1.5)
        #expect(t.pitchAlgorithm == .timeDomain)
        #expect(t.volumeRamps.count == 1)
    }

    @Test func atTimeModifierPreservesSpeed() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .speed(2.0)
            .at(time: 5.0)
        #expect(t.speedRate == 2.0)
        #expect(CMTimeGetSeconds(t.startTime ?? .zero) == 5.0)
    }

    @Test func durationModifierPreservesSpeed() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .speed(1.5)
            .duration(10.0)
        #expect(t.speedRate == 1.5)
        #expect(CMTimeGetSeconds(t.explicitDuration ?? .zero) == 10.0)
    }

    @Test func duckingModifierPreservesSpeed() {
        let t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .speed(1.5)
            .ducking(0.3)
        #expect(t.speedRate == 1.5)
        #expect(t.duckingLevel == 0.3)
    }

    // MARK: - AVFoundation algorithm bridge

    @Test func algorithmMapsToAVConstants() {
        #expect(AudioTimePitchAlgorithm.spectral.avAlgorithm == .spectral)
        #expect(AudioTimePitchAlgorithm.timeDomain.avAlgorithm == .timeDomain)
        #expect(AudioTimePitchAlgorithm.varispeed.avAlgorithm == .varispeed)
    }
}
