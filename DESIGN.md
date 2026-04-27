# Kadr — Design Document

## Scope Lock (v0.1)

Kadr v0.1 does image-to-video composition (single, paired, slideshow), video merging, reverse, trim, muted+audio-replace, and H.264/HEVC export with social presets (Reels, Square, Cinema) — accessed via a declarative DSL with async/await throughout. Nothing else ships in v0.1.

## API Examples

```swift
import Kadr
import Foundation

@available(iOS 16, macOS 13, *)
func apiValidationExamples() async throws {
    let heroImage = PlatformImage()
    let image1 = PlatformImage()
    let image2 = PlatformImage()
    let image3 = PlatformImage()
    let image4 = PlatformImage()
    let musicURL = URL(fileURLWithPath: "/tmp/music.mp3")
    let narrationURL = URL(fileURLWithPath: "/tmp/narration.mp3")
    let audio1URL = URL(fileURLWithPath: "/tmp/a1.mp3")
    let audio2URL = URL(fileURLWithPath: "/tmp/a2.mp3")
    let audio3URL = URL(fileURLWithPath: "/tmp/a3.mp3")
    let newMusicURL = URL(fileURLWithPath: "/tmp/new.mp3")
    let clipURL = URL(fileURLWithPath: "/tmp/clip.mov")
    let clip1URL = URL(fileURLWithPath: "/tmp/clip1.mov")
    let clip2URL = URL(fileURLWithPath: "/tmp/clip2.mov")
    let clip3URL = URL(fileURLWithPath: "/tmp/clip3.mov")
    let longClipURL = URL(fileURLWithPath: "/tmp/long.mov")
    let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")

    // 1. Hello world
    _ = try await Video {
        ImageClip(heroImage, duration: 5.0)
    }
    .audio(url: musicURL)
    .export(to: outputURL)

    // 2. Slideshow
    _ = try await Video {
        ImageClip(image1)
        ImageClip(image2)
        ImageClip(image3)
        ImageClip(image4)
    }
    .audio(url: narrationURL)
    .export(to: outputURL)

    // 3. Paired clips
    _ = try await Video {
        ImageClip(image1).withAudio(audio1URL)
        ImageClip(image2).withAudio(audio2URL)
        ImageClip(image3).withAudio(audio3URL)
    }
    .export(to: outputURL)

    // 4. Silent sequence with explicit durations
    _ = try await Video {
        ImageClip(image1, duration: 2.0)
        ImageClip(image2, duration: 3.0)
        ImageClip(image3, duration: 1.5)
    }
    .export(to: outputURL)

    // 5. Merge existing videos
    _ = try await Video {
        VideoClip(url: clip1URL)
        VideoClip(url: clip2URL)
        VideoClip(url: clip3URL)
    }
    .export(to: outputURL)

    // 6. Reverse a clip
    _ = try await Video {
        VideoClip(url: clipURL).reversed()
    }
    .export(to: outputURL)

    // 7. Trim to range
    _ = try await Video {
        VideoClip(url: clipURL).trimmed(to: 5...20)
    }
    .export(to: outputURL)

    // 8. Replace audio
    _ = try await Video {
        VideoClip(url: clipURL).muted()
    }
    .audio(url: newMusicURL)
    .export(to: outputURL)

    // 9. Multi-clip with transition
    _ = try await Video {
        VideoClip(url: clip1URL).trimmed(to: 0...10)
        Transition.fade(duration: 0.5)
        VideoClip(url: clip2URL).trimmed(to: 0...10)
    }
    .preset(.reelsAndShorts)
    .export(to: outputURL)

    // 10. Export with progress stream
    let exporter = Video {
        VideoClip(url: longClipURL)
    }
    .preset(.cinema)
    .exporter(to: outputURL)

    for try await progress in exporter.run() {
        _ = progress.fractionCompleted
        _ = progress.estimatedTimeRemaining
    }
}
```

## Migration: Old API → Kadr

| Old API | Kadr equivalent |
|---|---|
| `generate(... .single, ...)` | `Video { ImageClip(img) }.audio(url:).export(to:)` |
| `generate(... .multiple, ...)` | `Video { pairs.map { ImageClip($0.img).withAudio($0.audio) } }.export(to:)` |
| `generate(... .singleAudioMultipleImage, ...)` | `Video { images.map { ImageClip($0) } }.audio(url:).export(to:)` |
| `mergeMovies(videoURLs:)` | `Video { urls.map { VideoClip(url: $0) } }.export(to:)` |
| `reverseVideo(fromVideo:)` | `Video { VideoClip(url:).reversed() }.export(to:)` |
| `splitVideo(withURL:atStartTime:andEndTime:)` | `Video { VideoClip(url:).trimmed(to: s...e) }.export(to:)` |
| `mergeVideoWithAudio(videoUrl:audioUrl:)` | `Video { VideoClip(url:).muted() }.audio(url:).export(to:)` |

**Key insight:** 7 imperative public functions → 3 DSL primitives + modifiers.

## v0.5 design — Custom Compositors

Foundation feature for v0.5.0. A `Compositor` is user code that processes a single per-clip frame. Built-in compositors (per-clip crop, alpha-mask crop) consume the same protocol the public API exposes.

**Public surface**

```swift
public struct CompositorContext: Sendable {
    public let time: CMTime          // composition time of this frame
    public let renderSize: CGSize    // engine's render canvas in pixels
}

public protocol Compositor: Sendable {
    func process(image: CIImage, context: CompositorContext) -> CIImage
}

extension VideoClip {
    public func compositor(_ compositor: any Compositor) -> VideoClip
    public func compositor(_ body: @Sendable @escaping (CIImage, CompositorContext) -> CIImage) -> VideoClip
}
```

**Key decisions and rationale**

| Decision | Choice | Why |
|---|---|---|
| Pixel format | `CIImage` in / out | Composes with the existing `CIFilter` pipeline (`applyingCIFiltersWithHandler`). Lazy + GPU-backed. `CGImage` would force eager rasterization per frame and break GPU continuity. |
| Synchronicity | Synchronous return | The engine wraps the call in `applyingCIFiltersWithHandler` for the async finish. Per-frame `async` is a footgun (export rate × clip-fps = blocking work); implementers preload state at construction. |
| Concurrency | Protocol declared `Sendable`; `CIImage` is `Sendable` on iOS 14+ / macOS 11+ | Required for the engine's actor crossings. |
| Pipeline order | Per-clip pre-render, **after** `Filter`s | Filters are predictable color ops; compositors are arbitrary user code. Order: filter → compositor → composition assembly. Implementation generalizes the existing `FilterProcessor` pre-render into a "passes" pipeline. |
| Surface shape | Both protocol and closure | Protocol for reusable / named / testable compositors (used by the built-in crop + mask). Closure for ad-hoc use; wraps a closure-based conformance internally. |
| Context | Struct (`CompositorContext`) | Lets us add fields (`clipDuration`, `clipIndex`, etc.) later without breaking the protocol. |

**Out of scope for v0.5**

Multi-track / multi-input compositors (e.g., a compositor that blends two source images, like a custom transition) require the lower-level `AVVideoCompositing` path. Land with v0.6's multi-track timeline.

**Migration path for built-in features**

The v0.5 per-clip `VideoClip.crop(at:size:anchor:)` and `VideoClip.mask(_:)` ship as named built-ins on top of the same `Compositor` protocol — Tier 3 of the v0.5 plan.
