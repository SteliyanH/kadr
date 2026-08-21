import Kadr
import Foundation
import CoreMedia

/// v0.14 showcase — thumbnail generation.

// MARK: - One generator, many frames

/// Build a filmstrip without paying to compose the video once per frame.
///
/// `Video.thumbnail(at:)` is fine for a single frame, but it composes the whole
/// composition each time it is called. A generator composes once and reuses a
/// single `AVAssetImageGenerator` across every request, which is the difference
/// between a scrub bar that keeps up and one that does not.
func v140Filmstrip() async throws {
    let source = URL(fileURLWithPath: "/tmp/scene.mov")
    let video = Video { VideoClip(url: source).trimmed(to: 0...30) }

    let generator = try await video.thumbnailGenerator()
    defer { generator.cancel() }

    // Twenty evenly spaced frames.
    let times = (0..<20).map { CMTime(seconds: Double($0) * 1.5, preferredTimescale: 600) }

    for try await thumbnail in generator.thumbnails(at: times) {
        _ = thumbnail   // hand to a strip view as each frame arrives
    }
}

/// A single frame, when that is genuinely all you need — a poster image.
func v140PosterFrame() async throws {
    let video = Video { VideoClip(url: URL(fileURLWithPath: "/tmp/scene.mov")) }
    let generator = try await video.thumbnailGenerator()
    _ = try await generator.thumbnail(at: CMTime(seconds: 2, preferredTimescale: 600))
}

/// Scrubbing means abandoning requests constantly; `cancel()` is how you stop
/// paying for frames nobody will see.
func v140CancelOnScrub() async throws {
    let video = Video { VideoClip(url: URL(fileURLWithPath: "/tmp/scene.mov")) }
    let generator = try await video.thumbnailGenerator()
    generator.cancel()
}
