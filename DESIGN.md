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

## v0.6 design — Multi-Track Timeline

DSL evolution to support parallel tracks. Fully additive: every v0.5 single-track composition continues to compile and behave identically.

**Hybrid DSL — three shapes from least to most explicit**

```swift
// 1. Top-level chain (unchanged from v0.5)
Video {
    VideoClip(url: a).trimmed(to: 0...5)
    Transition.fade(duration: 0.5)
    VideoClip(url: b).trimmed(to: 0...5)
}

// 2. .at(time:) — single floating overlay
Video {
    VideoClip(url: a).trimmed(to: 0...10)            // main track
    VideoClip(url: pip).trimmed(to: 0...3)
        .at(time: 2.0)                                // floats over the main at t=2s
}

// 3. Track { } — grouped parallel sub-timeline
Video {
    VideoClip(url: a).trimmed(to: 0...10)            // main track
    Track(at: 2.0) {                                  // parallel track starting at t=2s
        VideoClip(url: pipA).trimmed(to: 0...2)
        VideoClip(url: pipB).trimmed(to: 0...2)
    }
}
```

Top-level clips without `.at(...)` form an implicit "main track" — current v0.5 behavior. Clips with `.at(...)` and `Track {}` blocks become parallel video tracks anchored at the declared time.

**Key decisions and rationale**

| Decision | Choice | Why |
|---|---|---|
| DSL shape | Hybrid: top-level chain + `.at(time:)` + `Track {}` | Smallest change for v0.5 users (no breaking change); `.at(time:)` covers PiP with one modifier; `Track {}` covers grouped sub-timelines. Each shape's call site reads exactly as much complexity as the use case requires. |
| Layer ordering | Declaration order = render order (later on top) | Symmetry with `Video.overlay(_:)` which already chains this way. Explicit z-order can land later if needed. |
| Multi-input API | New `MultiInputCompositor` protocol (separate from v0.5's `Compositor`) | Additive; v0.5 single-input conformers stay source-compatible. Single protocol enriched with `[CIImage]` would have been a breaking change. |
| Default track blend | Alpha-composite later-over-earlier | Most-expected default for layered video. Custom blending (e.g., subject + plate, custom transitions) attaches via `MultiInputCompositor`. |
| Audio model | Unchanged | `Video.audio { AudioTrack }` already supports parallel audio tracks. Clips inside `Track {}` contribute their clip audio same as top-level. Don't force unrelated nesting. |
| Engine path | `AVVideoCompositing` for multi-track; `applyingCIFiltersWithHandler` fast path stays for single-track | Apple's lower-level path is needed for multi-source blending. Single-track compositions don't pay for it. |

**Public surface sketch**

```swift
public struct Track: Sendable {
    public init(at time: CMTime, @VideoBuilder _ content: () -> [any Clip])
    public init(at time: TimeInterval, @VideoBuilder _ content: () -> [any Clip])
}

public extension VideoClip {
    func at(time: CMTime) -> VideoClip
    func at(time: TimeInterval) -> VideoClip
}

public protocol MultiInputCompositor: Sendable {
    func process(images: [CIImage], context: CompositorContext) -> CIImage
}

public extension Video {
    func compositor(_ compositor: any MultiInputCompositor) -> Video    // Composition-wide multi-track blender
}
```

**Out of scope for v0.6**

- kadr-ui's multi-lane `TimelineView` — kadr-ui v0.5+, lands after kadr v0.6 ships
- Automatic time-aware compositor selection (e.g., "use this compositor only between t=2s and t=5s") — could land in v0.6.x if needed; v0.6 keeps the engine attaching one global multi-track blender

## v0.7 design — Multi-track polish & audio timing

Closes the v0.6 deferrals on transitions-in-chain and time-ranged compositors, adds named Tracks for downstream tooling, and introduces the first real audio timing controls. Fully additive — every v0.6 composition continues to compile and behave identically.

**Four shipped items**

```swift
// 1. Track(name:) — public label for tooling
Video {
    VideoClip(url: main).trimmed(to: 0...10)
    Track(at: 2.0, name: "B-Roll") {
        VideoClip(url: alt).trimmed(to: 0...3)
    }
}

// 2. Transitions in the implicit chain alongside multi-track parallel clips
//    (closes v0.6 deferral — was rejected with KadrError.notYetImplemented)
Video {
    VideoClip(url: a).trimmed(to: 0...5)
    Transition.dissolve(duration: 0.5)
    VideoClip(url: b).trimmed(to: 0...5)
    Track(at: 1.0) { VideoClip(url: pip).trimmed(to: 0...3) }
}

// 3. Time-ranged compositor selection
Video { ... }
    .compositor(MultiplyBlend(), during: 2.0...5.0)   // active only in that window

// 4. AudioTrack timing — sound effects pinned to a moment
Video { ... }
    .audio {
        AudioTrack(url: musicURL)                          // plays full composition
        AudioTrack(url: sfxURL).at(time: 3.0).duration(1.5) // SFX from t=3s, capped 1.5s
    }
```

**Key decisions and rationale**

| Decision | Choice | Why |
|---|---|---|
| Chain-with-transitions in multi-track | Pre-render the chain to a temp `.mp4`, insert as a single piece on the main video track | Mirrors the existing v0.6 tier-4c Tracks-with-transitions pre-render. Reuses the single-track-with-transitions builder path that already works. Avoids extending the multi-track assembler's cursor model to handle alternating transition tracks alongside parallel ones — disproportionate engineering cost for what's a minor convenience over the documented `Track { }` workaround. |
| Compositor time window | Single `during: CMTimeRange?` parameter on `Video.compositor(_:during:)` | One global compositor with one optional window. No multiplexing-by-time of multiple compositors — keeps the engine simple. Outside the window, default `AlphaCompositeBlender` runs. CMTime + TimeInterval overloads matching the rest of the API. |
| Audio timing storage | New `startTime: CMTime?` and `explicitDuration: CMTime?` on `AudioTrack` (both optional) | `nil` = current behavior (plays full asset, starts at t=0). `.at(time:)` and `.duration(_:)` modifiers populate them. `nil` defaults preserve every v0.6 audio call site. |
| Audio insertion in engine | `audio.startTime ?? .zero` for insertion time; `min(explicitDuration ?? compositionEnd, compositionEnd - startTime)` for length | Single helper threads through both the standard chain path and `buildMultiTrack`'s audio path. Volume / fade / ducking automation timing shifts to the new window. |
| Named Tracks | Stored `name: String?` (default nil), three new init overloads | kadr-ui v0.5.x already auto-generates "Track 1" / "Track 2"; named Tracks let consumers pass through real labels. Source-compatible. |

**Public surface sketch**

```swift
public struct Track: Clip, Sendable {
    public let name: String?
    public init(name: String?, @VideoBuilder _ content: () -> [any Clip])
    public init(at time: CMTime, name: String? = nil, @VideoBuilder _ content: () -> [any Clip])
    public init(at time: TimeInterval, name: String? = nil, @VideoBuilder _ content: () -> [any Clip])
}

public struct AudioTrack: Sendable {
    public let startTime: CMTime?
    public let explicitDuration: CMTime?
    public func at(time: CMTime) -> AudioTrack
    public func at(time: TimeInterval) -> AudioTrack
    public func duration(_ duration: CMTime) -> AudioTrack
    public func duration(_ duration: TimeInterval) -> AudioTrack
}

public extension Video {
    func compositor(_ compositor: any MultiInputCompositor, during range: CMTimeRange) -> Video
    func compositor(_ compositor: any MultiInputCompositor, during range: ClosedRange<TimeInterval>) -> Video
    // The existing `compositor(_:)` (no range) keeps working — equivalent to "active for the full composition".
}
```

**Tier breakdown**

- **Tier 0** *(this RFC)* — design doc only.
- **Tier 1** — `Track(name:)` + close transitions-in-chain deferral. Generalize `preRenderTrackToTempFile` → `preRenderClipsToTempFile`. Lift the rejection in `buildMultiTrack`. Bundled because both are small and engine-localized.
- **Tier 2** — Time-ranged compositor selection. Engine work in `Video` storage and `KadrVideoCompositor.startRequest`.
- **Tier 3** — AudioTrack timing. Modifiers + storage + engine assembly + edge-case tests. Largest tier.
- **Tier 4** — Release prep: ROADMAP, CHANGELOG, develop → main, tag, release.

**Out of scope for v0.7**

- Multiple compositors multiplexed by time window (chain of `(compositor, range)` pairs). One global compositor with one optional window only.
- Audio cross-fades on `AudioTrack` boundaries (volume + fades exist; cross-fades between two tracks at the same time slot are not v0.7).
- Audio `.speed(_:)` (clip-side speed exists; audio-track-side speed is bigger work).
- Per-Track compositor overrides — global only.
