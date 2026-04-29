import Testing
import CoreMedia
import AVFoundation
import Foundation
@testable import Kadr

/// Tests for v0.9.2 — Caption value type, Video.captions(_:) modifier, AVMetadataItem
/// writer. Coverage: surface, modifier accumulation, MetadataItem mapping.
struct CaptionTests {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func range(_ start: Double, _ end: Double) -> CMTimeRange {
        CMTimeRange(start: cmt(start), end: cmt(end))
    }

    // MARK: - Caption value type

    @Test func captionStoresTextAndRange() {
        let c = Caption(text: "Hello", timeRange: range(0, 2))
        #expect(c.text == "Hello")
        #expect(CMTimeGetSeconds(c.timeRange.start) == 0)
        #expect(CMTimeGetSeconds(c.timeRange.duration) == 2)
    }

    @Test func captionEqualityHonorsTextAndRange() {
        let a = Caption(text: "X", timeRange: range(0, 1))
        let b = Caption(text: "X", timeRange: range(0, 1))
        let c = Caption(text: "Y", timeRange: range(0, 1))
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - AVMetadataItem mapping

    @Test func makeMetadataItemSetsTextValue() {
        let item = Caption(text: "Hi", timeRange: range(0, 1)).makeMetadataItem()
        #expect((item.value as? String) == "Hi")
    }

    @Test func makeMetadataItemSetsTimeAndDuration() {
        let c = Caption(text: "X", timeRange: range(2, 5))
        let item = c.makeMetadataItem()
        #expect(CMTimeGetSeconds(item.time) == 2)
        #expect(CMTimeGetSeconds(item.duration) == 3)
    }

    @Test func makeMetadataItemUsesDescriptionIdentifier() {
        let item = Caption(text: "X", timeRange: range(0, 1)).makeMetadataItem()
        #expect(item.identifier == .commonIdentifierDescription)
    }

    // MARK: - Video.captions(_:) modifier

    @Test func defaultVideoHasNoCaptions() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        #expect(video.captions.isEmpty)
    }

    @Test func captionsModifierStoresCues() {
        let cues = [
            Caption(text: "A", timeRange: range(0, 1)),
            Caption(text: "B", timeRange: range(1, 2)),
        ]
        let video = Video {
            ImageClip(PlatformImage(), duration: 2.0)
        }
        .captions(cues)
        #expect(video.captions.count == 2)
        #expect(video.captions == cues)
    }

    @Test func multipleCaptionsCallsAccumulate() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 3.0)
        }
        .captions([Caption(text: "A", timeRange: range(0, 1))])
        .captions([Caption(text: "B", timeRange: range(1, 2)),
                   Caption(text: "C", timeRange: range(2, 3))])
        #expect(video.captions.count == 3)
        #expect(video.captions.map(\.text) == ["A", "B", "C"])
    }

    @Test func captionsModifierPreservesOtherFields() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 2.0)
        }
        .audio(url: URL(fileURLWithPath: "/dev/null"))
        .overlay(TextOverlay("title"))
        .captions([Caption(text: "X", timeRange: range(0, 1))])
        #expect(video.audioTracks.count == 1)
        #expect(video.overlays.count == 1)
        #expect(video.captions.count == 1)
    }

    @Test func otherModifiersPreserveCaptions() {
        // Latent-bug guard: setting captions then calling other Video modifiers must
        // preserve the captions array.
        let video = Video {
            ImageClip(PlatformImage(), duration: 2.0)
        }
        .captions([Caption(text: "X", timeRange: range(0, 1))])
        .audio(url: URL(fileURLWithPath: "/dev/null"))
        .overlay(TextOverlay("title"))
        .preset(.square)
        #expect(video.captions.count == 1)
        #expect(video.captions[0].text == "X")
    }
}
