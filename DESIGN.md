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
- Audio cross-fades on `AudioTrack` boundaries (volume + fades exist; cross-fades between two tracks at the same time slot are not v0.7). *(closed in v0.8 — see below)*
- Audio `.speed(_:)` (clip-side speed exists; audio-track-side speed is bigger work). *(staged for v0.9)*
- Per-Track compositor overrides — global only.

## v0.8 design — Animation & Transform

The last feature cycle before v1.0. Foundational additions that would be breaking if they landed after semver lock — per-clip transform, keyframe animations on every animatable property, animated text overlays. Plus audio cross-fades on `AudioTrack` boundaries to round out the audio surface.

**Hybrid surface — declarative on top of result-builder DSL**

```swift
// 1. Per-clip Transform (static — apply uniformly across the clip's duration)
Video {
    VideoClip(url: a)
        .trimmed(to: 0...5)
        .transform(Transform(scale: 0.5, anchor: .topRight))   // PiP in the corner
}

// 2. Keyframe-animated Transform — Ken Burns zoom-pan
Video {
    ImageClip(photo, duration: 5.0)
        .transform(.identity, animation:
            .keyframes([
                .at(0.0, value: Transform(scale: 1.0, center: .normalized(x: 0.5, y: 0.5))),
                .at(5.0, value: Transform(scale: 1.3, center: .normalized(x: 0.6, y: 0.4))),
            ], timing: .easeInOut)
        )
}

// 3. Animated TextOverlay — fade-by-letter title reveal
Video { ... }
    .overlay(
        TextOverlay("MY MOVIE", style: titleStyle)
            .position(.center)
            .animation(.fadeByLetter(duration: 1.5))   // pre-built reveal recipe
    )

// 4. Audio cross-fade on AudioTrack boundaries
Video { ... }
    .audio {
        AudioTrack(url: musicA).at(time: 0).duration(8.0)
        AudioTrack(url: musicB).at(time: 7.0).crossfade(1.0)  // 1s overlap fades A→B
    }
```

**Key decisions and rationale**

| Decision | Choice | Why |
|---|---|---|
| Transform shape | `Transform(center: Position, rotation: Double, scale: Double, anchor: Anchor)` value type | Reuses existing `Position` / `Anchor` from v0.3's overlay surface. Same coordinate space (normalized + pixel + percent + named anchors) so consumers don't relearn. Single value type covers static and animated cases. |
| Keyframe API | `Animation<T>` value type + `Animatable` protocol on conforming types | Generic on the animated property type (`Transform`, `Double` for opacity, `Filter.intensity`). User-supplied keyframe arrays + timing functions. Engine evaluates per-frame in the existing `KadrVideoCompositor` path. |
| Timing functions | Built-in `.linear` / `.easeIn` / `.easeOut` / `.easeInOut` / `.cubicBezier(p1, p2)` / `.custom((Double) -> Double)` | Mirrors CAMediaTimingFunction's surface; covers the 90% case. Custom closure form is the escape hatch. |
| Animated text | `TextOverlay.animation(any TextAnimation)` + built-in recipes (`.fadeByLetter`, `.slideIn`, `.scaleUp`) | CALayer-backed render path under the hood (the recipe builds a `CATextLayer` + `[CAAnimation]`). Static `TextOverlay`s without animation continue to use the existing fast path. |
| Engine — text rendering | Use `AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer:in:)` for the export path (animated text); `AVSynchronizedLayer` for preview consumers (kadr-ui). | Apple's intended path for animated text. Export-only at the engine level (matches what overlays already do — kadr-ui handles preview overlay rendering separately). |
| Audio cross-fades | `AudioTrack.crossfade(_ duration: CMTime/TimeInterval)` modifier — declares "fade out over `duration` from the end of *this* track, fade in over `duration` to the start of the *next* track in declaration order"  | Symmetric ramps on both sides of the boundary. Doesn't require pairing tracks explicitly; declaration order + `.at(time:)` overlaps determine which is "next". Engine emits matching volume ramps via `AVMutableAudioMixInputParameters`. |
| Animation evaluation | Engine evaluates animations at composition time, not at frame time. `KadrVideoCompositor.process` reads the current request's `compositionTime` and asks each animatable for its interpolated value. | Frame-accurate without a per-frame allocation pass. Same pattern as v0.7's time-windowed compositor selection. |
| `Transform.identity` constant | Yes — a public static for "no transform" so callers can pass `.identity` when they want only animation, no static base | Avoids the "what if I want animation only" awkwardness. Identity == `Transform(center: .normalized(x: 0.5, y: 0.5), rotation: 0, scale: 1, anchor: .center)`. |
| **Animation timing semantics** | **Clip-relative.** A `Keyframe.at(0.0, value: ...)` on a clip's animation means "the clip's first visible frame," not "composition t=0." Engine maps to absolute time at evaluation: `absoluteTime = clip.absoluteStart + keyframe.time`. Same rule applies to chain clips, `.at(time:)` free-floaters, and clips inside `Track {}` blocks. | Foundational decision — **must be locked in v0.8.0 because flipping later is breaking.** Matches CAAnimation's contract (timing relative to layer's lifetime). Reads naturally: `.keyframes([.at(0.0, ...), .at(2.0, ...)])` describes "what happens during this clip's first 2 seconds," regardless of where the clip lands on the composition timeline. |

**Public surface sketch**

```swift
public struct Transform: Sendable, Equatable {
    public var center: Position
    public var rotation: Double      // radians; positive = CCW
    public var scale: Double         // uniform; 1.0 = unchanged
    public var anchor: Anchor        // pivot for rotation + scale

    public init(center: Position = .normalized(x: 0.5, y: 0.5),
                rotation: Double = 0,
                scale: Double = 1,
                anchor: Anchor = .center)

    public static let identity: Transform
}

public struct Animation<Value: Animatable>: Sendable {
    public let keyframes: [Keyframe<Value>]
    public let timing: TimingFunction

    public struct Keyframe<V: Animatable>: Sendable {
        public let time: CMTime
        public let value: V
        public static func at(_ seconds: TimeInterval, value: V) -> Keyframe<V>
        public static func at(_ time: CMTime, value: V) -> Keyframe<V>
    }

    public static func keyframes(_ keyframes: [Keyframe<Value>], timing: TimingFunction = .linear) -> Animation<Value>
}

public protocol Animatable: Sendable {
    /// Interpolate between two values at fraction `t` in 0...1. Engine drives this
    /// per-frame from the current composition time mapped through the timing function.
    static func interpolate(_ a: Self, _ b: Self, t: Double) -> Self
}
extension Transform: Animatable
extension Double: Animatable    // for opacity / filter intensity

public enum TimingFunction: Sendable {
    case linear, easeIn, easeOut, easeInOut
    case cubicBezier(_ p1: CGPoint, _ p2: CGPoint)
    case custom(@Sendable (Double) -> Double)
}

public extension VideoClip {
    func transform(_ transform: Transform) -> VideoClip
    func transform(_ base: Transform, animation: Animation<Transform>) -> VideoClip
    func opacity(_ opacity: Double) -> VideoClip
    func opacity(_ base: Double, animation: Animation<Double>) -> VideoClip
}
public extension ImageClip { /* same surface */ }
public extension TitleSequence { /* same surface */ }

public extension TextOverlay {
    func animation(_ animation: any TextAnimation) -> TextOverlay
}

public protocol TextAnimation: Sendable {
    /// Returns a CAAnimation tree (or layer-tree fragment) for the engine's
    /// CALayer-backed text render. Engine-internal — consumers use the public
    /// recipes below.
    func makeAnimations(in layer: CALayer, duration: CMTime) -> [CAAnimation]
}

public extension TextAnimation where Self == FadeByLetter {
    static func fadeByLetter(duration: CMTime) -> FadeByLetter
    static func fadeByLetter(duration: TimeInterval) -> FadeByLetter
}
// + SlideIn, ScaleUp, …

public extension AudioTrack {
    func crossfade(_ duration: CMTime) -> AudioTrack
    func crossfade(_ duration: TimeInterval) -> AudioTrack
}
```

**Tier breakdown**

- **Tier 0** *(this RFC)* — design doc only.
- **Tier 1** — Per-clip Transform. `Transform` value type + modifiers + engine wiring through `AVMutableVideoCompositionLayerInstruction.transform`. Static case only — no animations yet. ~250 LOC + tests.
- **Tier 2** — Keyframe system. `Animation<T>`, `Animatable`, `TimingFunction`, animated `transform(_:animation:)` and `opacity(_:animation:)` modifiers. Engine evaluates animations per-frame in `KadrVideoCompositor` and the simple-path layer instruction. ~400 LOC + tests.
- **Tier 3** — Animated `TextOverlay`. CALayer-backed render path for the export pipeline via `AVVideoCompositionCoreAnimationTool`. Built-in recipes (`fadeByLetter`, `slideIn`, `scaleUp`). ~350 LOC + tests.
- **Tier 4** — Audio cross-fades. `AudioTrack.crossfade(_:)` modifier + engine ramp generation in `buildBackgroundAudioMixParameters`. ~120 LOC + tests.
- **Tier 5** — Release prep: ROADMAP / CHANGELOG / README / V080Showcase / develop → main / tag.

**v0.8.x patches — staged after v0.8.0, before v0.9.0**

These are real user needs that don't have to ship in the headline cycle but should land before v0.9 starts. All additive, none breaking.

- **v0.8.1 — `Position` / `Size` as `Animatable`** + `.position(_:animation:)` / `.size(_:animation:)` modifiers on `ImageOverlay` / `StickerOverlay` / `Watermark`. The v0.8.0 `Animatable` protocol covers `Transform` and `Double`; extending it to coordinate types is a small, mechanical addition (interpolate is straightforward arithmetic) that unlocks animated image/sticker overlays — sliding watermarks, animated logo placements, drifting stickers.
- **v0.8.2 — Filter intensity animation.** `VideoClip.filter(_:animation:)` taking a single `Filter` + `Animation<Double>`. Engine composes the animated intensity scalar with the static filter at evaluation time. Real use cases: animated blur sweeps, gradual sepia fades, intensity-ramped vignette.
- **v0.8.3 — `AudioTrack.volumeRamp(start:end:during:)`.** Granular volume automation between two points. Sister API to `.fadeIn` / `.fadeOut` for arbitrary ramps mid-track.
- **v0.8.4 — More `Filter` presets.** `gaussianBlur`, `vignette`, `sharpen`, `zoomBlur`, `glow`. Closes the parity gap with IMG.LY (60+ filters) and VideoLab.

**Truly deferred — wishlist (may never ship)**

These were considered and intentionally left off the roadmap. They're additive — adding them later is non-breaking — but the user need is thin enough that we may never implement them. Captured here so future maintainers don't redo the analysis.

- **Per-segment timing functions** (different ease per keyframe segment) — global `TimingFunction` per `Animation<T>` plus `.custom((Double) -> Double)` covers ~95% of cases. The remaining 5% can write their own piecewise curve in the `.custom` closure. Likely never adds enough value to justify the API expansion.
- **Equal-power / S-curve audio cross-fades** — niche audio-engineering polish. Linear ramps in v0.8.0 are perceptually fine for most music swaps; pro-audio apps that care can build their own ramps via `.volumeRamp(...)`. Probably stays a nice-to-have forever.
- **`Animation<T>` on `Compositor` parameters** — custom compositors are stateless `Sendable`; animated compositor parameters (e.g., a chroma-key threshold that animates) belong on the calling site, not as a kadr-managed surface. Compositor authors handle their own animation state if they need it.
- **`CropRegion` keyframes** (composition-level animated crop) — clip-level `Transform` animation already covers the common Ken Burns use case (apply to an `ImageClip` or `VideoClip`). Composition-level animated crop is genuinely rare. Defer indefinitely.
- **Real-time DSP audio nodes** (reverb, EQ, compression on `AudioTrack`) — already explicit non-goal. AudioKit is the right answer for DSP-heavy audio work; kadr's audio surface stays declarative + `AVMutableAudioMix`-shaped.

**Engineering notes**

- **Animation eval cost.** `KadrVideoCompositor.process` is called per frame; computing interpolated values per frame is fine for tens of animatable properties but could matter for compositions with hundreds. Decision: cache the resolved keyframe segments at instruction-build time (one-time CPU work) so per-frame eval is one binary search + one `interpolate(_:_:t:)` call. Validated once we benchmark in v1.0.
- **Existing animation-free fast path stays.** Compositions without animations skip the per-frame eval entirely — the existing `AVMutableVideoCompositionLayerInstruction` static-transform path is faster and we keep it.
- **`AVVideoCompositionCoreAnimationTool` export-only constraint.** Already documented in the v0.4 architectural note. Animated text follows the same constraint — engine bakes it into the export, kadr-ui v0.6 will provide the preview surface via `AVSynchronizedLayer`.

**Migration**

Pure additive. Every v0.7 composition compiles unchanged. New surface is opt-in:
- No `.transform(_:)` call → no transform applied (engine sees `nil`)
- No `.animation` argument → static value, existing layer-instruction path
- No `TextOverlay.animation(_:)` → existing fast text render
- No `AudioTrack.crossfade(_:)` → existing audio behavior

## v0.9 design — Advanced timing

The pre-v1.0 timing cleanup. Three additions that finish kadr's timing story before semver lock: non-linear playback speed on `VideoClip`, pitch-preserving speed on `AudioTrack`, and caption authoring / ingest. All additive — every v0.8 composition compiles unchanged.

### Problem

Kadr 0.2 introduced `VideoClip.speed(_:)` as a flat multiplier — the whole clip plays at 0.5× or 2×. The signature CapCut feature is a *speed curve*: ease into slow-motion at a specific moment, hold, ease back to normal. v0.9 closes that.

`AudioTrack` has fade-in / fade-out / volume ramps / crossfade (v0.7 + v0.8.3) but no speed control. Pitch-preserving audio speed is a v0.7-deferred item that would feel awkward to add post-v1.0.

Captions are the missing piece for a complete "ready to share" video composition. AVFoundation supports embedding them as an `AVMetadataItem` group at export.

### Scope lock

In scope:
- **Speed curves** on `VideoClip` — `.speed(curve:)` accepting an `Animation<Double>` whose values are speed multipliers over clip-relative time. Engine integrates the curve into a piecewise-linear time map and applies via repeated `scaleTimeRange(_:toDuration:)` segments.
- **`AudioTrack.speed(_:)`** — pitch-preserving via `AVMutableCompositionTrack.scaleTimeRange` + `AVAudioMixInputParameters.audioTimePitchAlgorithm = .timeDomain` (good for music) or `.spectral` (good for voice). Default `.spectral` for voice-friendly; opt-in `.timeDomain`.
- **Caption surface in core** — `Caption` value type (text + timeRange), `Video.captions(_:)` modifier, engine bakes as `AVMetadataItem` group at export. The AVFoundation bridge only.
- Reuses `Animation<Double>` for speed curves — no new keyframe machinery.

Out of scope (moved to `kadr-captions` adapter or deferred):
- **SRT / VTT / iTT file parsers and writers** — moved to the `kadr-captions` adapter (its v0.1.0 scope). Parsing real-world caption files has more variance than it looks (UTF-8 BOM / Windows-1252 fallback, malformed timestamps, VTT cue settings, inline styles); that's a separate package's job, not core's. Reading and writing the same format are dual operations — splitting them across packages would be incoherent, so both directions live in the adapter.
- **Caption styling / positioning / animation** — adapter scope; maps onto v0.8 `TextOverlay` + `textAnimation`.
- **Speed curves on `AudioTrack`** — requires AVAudioEngine for non-linear pitch preservation; current AVAudioMix + `scaleTimeRange` is linear-only. Flat speed multiplier is the v0.9 deliverable; non-linear stays out.
- **Speed curves on `ImageClip` / `TitleSequence`** — these have synthetic timelines; "speed" doesn't apply. Use animation on the clip's `transform` / `opacity` if you want time-shaping.
- **`SpeedCurve` as its own value type** — speed curves are `Animation<Double>` semantically; introducing a parallel type would mean two animation systems. Reuse keeps the surface coherent.

### Captions decision: AVFoundation bridge in core, parsers in adapter (locked)

The roadmap left this open. Locking it: **`Caption` + `Video.captions(_:)` + engine writer in core; SRT / VTT / iTT parsers + writers in `kadr-captions`**. Reasoning:

- The `AVMetadataItem` writer (~100 LOC) is the only piece that genuinely belongs in core — it's the AVFoundation bridge, and AVFoundation is already a core dependency. Plus the `Caption` value type (~30 LOC) and `Video.captions(_:)` modifier (~20 LOC). Total core surface: ~150 LOC.
- File parsers (~400 LOC across SRT + VTT + iTT, plus their writers) don't earn the core slot. They have real-world variance (encodings, malformed-timestamp recovery, cue settings) that warrants its own package's release cadence and test surface.
- "Parsers in core, writers in adapter" would be incoherent — reading and writing the same format are dual operations. Both go in the adapter.
- Keeps core's binary-size and surface-area cost down for users who never touch captions.
- Adapter consumers do `import Kadr; import KadrCaptions; let caps = try Caption.load(srt: url); video.captions(caps)`. The parser produces core's `Caption` values; the modifier comes from core. Clean handoff.

### API examples

```swift
import Kadr

// 1. Speed curve — slow-mo dip then ease back to normal
VideoClip(url: clipURL)
    .trimmed(to: 0...4)
    .speed(curve: .keyframes([
        .at(0.0, value: 1.0),
        .at(1.5, value: 0.25),
        .at(2.5, value: 0.25),
        .at(4.0, value: 1.0),
    ], timing: .easeInOut))

// 2. Audio speed — pitch-preserving 1.25× narration
AudioTrack(url: vo)
    .speed(1.25)               // default .spectral, voice-friendly
    .speed(1.25, algorithm: .timeDomain)  // music-friendly opt-in

// 3. Captions — handcrafted in DSL
Video {
    VideoClip(url: clipURL)
}
.captions([
    Caption(text: "Hello world", timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))),
    Caption(text: "Welcome back", timeRange: CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 600), duration: CMTime(seconds: 3, preferredTimescale: 600))),
])

// 4. Captions — load from SRT (kadr-captions adapter)
import KadrCaptions  // separate package
let captions = try Caption.load(srt: srtURL)  // adapter extension on Caption
video.captions(captions)
```

### Public surface sketch

```swift
public extension VideoClip {
    /// Apply a speed curve — non-linear playback rate over clip-relative time. Values
    /// in the animation are speed multipliers (1.0 = normal, 0.5 = half-speed, 2.0 = 2×).
    /// Engine integrates the curve into a piecewise-linear time map. Composes with
    /// `trimmed(to:)`: trim is applied first (selects the source range), then the
    /// speed curve maps that range to the timeline.
    func speed(curve: Animation<Double>) -> VideoClip
}

public extension AudioTrack {
    /// Pitch-preserving speed multiplier. `1.0` = normal, `1.25` = 25% faster while
    /// keeping the original pitch. Default `algorithm` is `.spectral` (voice-friendly).
    /// Use `.timeDomain` for music-friendly time stretching at small ratios.
    func speed(_ multiplier: Double, algorithm: AudioTimePitchAlgorithm = .spectral) -> AudioTrack
}

public enum AudioTimePitchAlgorithm: Sendable {
    case spectral    // best for voice
    case timeDomain  // best for music at small ratios (0.75x – 1.5x)
    case varispeed   // no pitch correction (chipmunk effect)
}

public struct Caption: Sendable, Equatable {
    public let text: String
    public let timeRange: CMTimeRange
    public init(text: String, timeRange: CMTimeRange)
}

public extension Video {
    /// Attach a caption track. Engine bakes as an `AVMetadataItem` group with
    /// `.subtitle` identifier at export. Multiple calls accumulate (later wins on
    /// timing overlap).
    func captions(_ captions: [Caption]) -> Video
}

// SRT / VTT / iTT parsers and writers live in the `kadr-captions` adapter package,
// not in core. They produce / consume the `Caption` value type defined here.
```

### Engine notes

- **Speed curves.** Discretize the `Animation<Double>` into N piecewise-linear segments at a fixed sampling rate (suggest 30 Hz to match preview frame rate). For each segment compute source-range and target-duration, then call `AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)` per segment. AVFoundation handles the per-segment time mapping; we trade resolution for AVFoundation's fast path. Higher-frequency sampling improves smoothness at the cost of more `scaleTimeRange` calls; benchmark in tier 1.
- **Speed curves and audio.** When a `VideoClip` carries a speed curve, the clip's audio (if not muted, no replacement audio) follows the same time map. We piggyback on the same per-segment scaleTimeRange. Pitch correction defaults to `.spectral` for parity with v0.9's `AudioTrack.speed`.
- **AudioTrack.speed.** Apply `scaleTimeRange(_:toDuration:)` on the audio composition track at insert time, set `audioTimePitchAlgorithm` on the corresponding `AVMutableAudioMixInputParameters`. Composes with all v0.7 / v0.8.3 audio surface (fades, ramps, ducking, crossfade) — those operate on the *target* duration after scaling.
- **Captions.** Build `[AVMetadataItem]` with key `commonKey: .commonKeyDescription` and key space `.common`, plus `time`/`duration` set per caption. Attach to the export's `metadata` array. Compatible with QuickTime / iOS Photos but does not produce a styled subtitle track; for real subtitle tracks (visible in YouTube / Final Cut), the post-v1.0 `kadr-captions` adapter will offer an `AVAssetWriter`-based path.

### Tier breakdown

Mirrors the established RFC-then-tiers staging.

- **Tier 0** *(this PR)* — design doc only. Locks the surface and the captions decision. No code.
- **Tier 1** — `VideoClip.speed(curve:)`. The biggest tier — engine work for piecewise scaleTimeRange + per-segment audio handling. ~500 LOC + tests. Ships as **v0.9.0**.
- **Tier 2** — `AudioTrack.speed(_:)`. Surface + engine wiring. ~150 LOC + tests. Ships as **v0.9.1**.
- **Tier 3** — `Caption` type + `Video.captions(_:)` modifier + engine `AVMetadataItem` writer. The AVFoundation bridge only. ~150 LOC + tests. Ships as **v0.9.2**.

SRT / VTT / iTT parsers and writers — formerly Tier 4 — moved out of the v0.9 cycle to `kadr-captions` v0.1.0. Each in-cycle tier still ships as its own minor; no big-bang.

### Test strategy

- **Speed curves.** Pure helpers: `discretizedSegments(curve:duration:rate:)` (returns `[(sourceRange, targetDuration)]`), `integratedDuration(curve:over:)`. Engine smoke tests: a clip + speed curve exports without error, output duration matches integrated curve. Comparison test: linear curve `.keyframes([(0,1),(d,1)])` produces identical output to no curve at all.
- **AudioTrack.speed.** Pure: rounding behavior at `1.0`, integer-multiple ratios. Engine smoke test: track inserts with the correct pitch algorithm.
- **Caption metadata writer.** Engine test: an exported video with `.captions([...])` has a non-empty metadata array with the expected count, items have the correct time/duration. `Caption` value-type equality.

Target coverage: ~35 new tests across the cycle. Suite floor: 320 → 355. (Down from earlier 380 estimate after parsers moved to `kadr-captions`.)

### Compatibility

- **Pure additive.** Every v0.8 composition compiles unchanged.
- **Bumps minimum.** None — same platform floor as v0.8 (iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+, Swift 6.0).
- **kadr-ui.** v0.9 surface is engine-side; kadr-ui doesn't need to change to consume it. Speed-curve UI and caption editor land in kadr-ui v0.7 (consuming v0.9), tracked in the kadr-ui roadmap.

### Migration

None required. New surface is opt-in:
- No `.speed(curve:)` call → existing flat `speed(_:)` (or no speed at all) keeps working.
- No `AudioTrack.speed(_:)` → existing audio behavior.
- No `.captions(_:)` → no metadata embedded.

### Open questions (track in PRs, not blocking RFC merge)

- **Speed-curve sampling rate.** 30 Hz is the obvious starting point (matches preview); benchmark whether 60 Hz produces visibly smoother slow-mo at the cost of 2× scaleTimeRange calls. Decision in tier 1.
- **Speed-curve serialization.** Should a speed curve survive a `Video` round-trip through some future serialization format? Tracked under v1.0 stability work; deferred from v0.9.

## v0.10.0 design — Pre-v1.0 polish

Three small additions before semver lock. None expand the public surface meaningfully — they close gaps that real consumers (kadr-reels-studio's ProjectStore, kadr-ui's InspectorPanel) hit while building against the v0.9.x surface. Pure additive.

### Problem

Three concrete pain points the v0.9.x cycle didn't address:

1. **`Filter.withScalar(_:)` is internal.** kadr-ui's `InspectorPanel` emits a new scalar value through its `onFilterIntensity` callback, expecting the consumer to rebuild the filter. But the helper that does exactly that — `Filter.withScalar(_:)` — is internal to kadr. kadr-reels-studio's ProjectStore had to duplicate the entire 11-case switch to apply intensity edits. Any other consumer building an inspector hits the same wall.
2. **No solid-color clip primitive.** Both kadr-reels-studio's `SampleProject` and kadr-ui's `Examples/SimpleViewer` render a `PlatformImage` of solid color, then wrap in `ImageClip(_:duration:)`. ~30 LOC of boilerplate per use site, plus full-resolution memory for what's effectively a single pixel.
3. **No per-track opacity.** `Track {}` carries clip-level opacity per clip, but the track itself can't fade as a unit. Common edit ("fade B-roll over A-roll") requires manually applying the same opacity to every clip in the track.

### Scope lock

In scope:
- **`Filter.withScalar(_:)` made public** — the existing helper. No behavior change. Callers (`InspectorPanel` consumers, custom keyframe builders) can now reuse rather than duplicate.
- **`ImageClip.color(_:duration:)` static factory** — produces an `ImageClip` backed by a 1×1 solid-color `PlatformImage`. AVFoundation stretches the 1-pixel source over the render canvas; for solid color the stretch is artifact-free. Two overloads (`CMTime` and `TimeInterval = 3.0`).
- **`Track.opacity(_:)` modifier** — per-track opacity in `0...1`. Engine multiplies any per-clip opacity by `track.opacity` at layer-instruction-build time, so a track with `.opacity(0.5)` containing a clip at `.opacity(0.8)` renders that clip at effective opacity `0.4`. Inner-Track recursive pre-render path applies the same multiplier.

Out of scope:
- **`ColorClip` as a distinct type** — considered, dropped. The factory approach gives identical UX without expanding the type surface; pattern-matching by clip type rarely matters for solid backgrounds.
- **Gradient / animated color clips** — out of scope; the factory's 1×1 source can't animate. A v0.10.x patch could add a higher-res renderer if demand emerges.
- **Track-level Transform** — out of scope for v0.10; would expand `Track` substantially. Per-clip Transform inside a Track already covers the common cases.
- **Track-level animation (`opacityAnimation` / `transformAnimation`)** — out of scope; clip-level animation handles fade-in/fade-out workflows already.

### API examples

```swift
import Kadr
import AVFoundation

// 1. Filter.withScalar — public now
let f = Filter.brightness(0.2)
let f2 = f.withScalar(0.5)
// Equivalent to Filter.brightness(0.5); useful when you have a Filter value and
// only want to substitute its scalar (e.g. driving a slider).

// 2. ImageClip.color — solid-color clip
Video {
    ImageClip.color(.red, duration: 2.0)            // TimeInterval form
    ImageClip.color(.blue, duration: cmt(1.5))      // CMTime form
}

// 3. Track.opacity — per-track fade
Video {
    VideoClip(url: aroll).trimmed(to: 0...10)       // base track
    Track {
        VideoClip(url: broll1).trimmed(to: 0...3)
        VideoClip(url: broll2).trimmed(to: 0...4)
    }
    .opacity(0.6)                                   // entire B-roll track at 60%
    .at(time: 2.0)
}
```

### Public surface sketch

```swift
public extension Filter {
    /// Build a new filter case substituting `scalar` for this filter's primary
    /// numeric parameter. Filters without a scalar (.mono, .lut, .chromaKey)
    /// return `self` unchanged. Made public in v0.10 — kadr-ui's InspectorPanel
    /// emits new scalar values that consumers apply via this helper.
    func withScalar(_ scalar: Double) -> Filter
}

public extension ImageClip {
    /// Build an `ImageClip` of solid color. Memory-efficient (1×1 source image
    /// stretched by AVFoundation's aspect-fill), artifact-free on stretch because
    /// every pixel is identical.
    static func color(_ color: PlatformColor, duration: CMTime) -> ImageClip
    static func color(_ color: PlatformColor, duration: TimeInterval = 3.0) -> ImageClip
}

public extension Track {
    /// Multiply every clip's effective opacity by `factor` at layer-instruction-
    /// build time. `factor` in `0...1`; default `1.0` (no fade).
    func opacity(_ factor: Double) -> Track
}
```

### Engine notes

- **`Filter.withScalar`** — pure visibility change. No engine code touched.
- **`ImageClip.color`** — synthesizes a 1×1 `PlatformImage` once at construction (`UIGraphicsImageRenderer` on iOS, `NSImage(size:1×1)` on macOS), wraps in the existing `ImageClip(_:duration:)` init. Engine treats it identically to any other `ImageClip`; AVFoundation stretches the 1-pixel source via aspect-fill.
- **`Track.opacity`** — adds an `opacityFactor: Double` field on `Track` (default `1.0`). When the engine builds layer instructions for clips inside a `Track`, the per-clip `opacity` (defaulting to `1.0`) gets multiplied by the parent track's `opacityFactor`. The recursive pre-render path (Tracks-with-transitions, Tracks-with-nested-Tracks) applies the same multiplier on the inserted-pre-rendered-track's instruction.

### Tier breakdown

- **Tier 0** *(this PR)* — design doc only. No code.
- **Tier 1** — `Filter.withScalar` public + `ImageClip.color` factory. ~30 LOC + tests.
- **Tier 2** — `Track.opacity` modifier + engine wiring. ~100 LOC + tests.
- **Tier 3** — Release prep + ship as **v0.10.0**.

### Test strategy

- **`Filter.withScalar`** — already tested internally; expose a couple of public-surface compile-time signature checks.
- **`ImageClip.color`** — confirms duration / image are wired (1×1 source).
- **`Track.opacity`** — pure helper for the multiplier (unit-tested without engine), plus engine smoke test that exports a Video with `Track.opacity(0.5)` and asserts the AVMutableVideoCompositionLayerInstruction's recorded opacity ramps reflect the multiplier.

Target test count for v0.10: ~15 new tests. Suite: 506 → ~521.

### Compatibility

- Pure additive — every v0.9.x composition compiles unchanged.
- No platform-floor change.
- Bumps kadr-ui's recommended dep floor in a follow-up patch (kadr-ui can drop the duplicated `withScalar` shim once v0.10 ships); same for kadr-reels-studio.

### Open questions (track in PRs, not blocking RFC merge)

- **`Track` opacity vs `opacity` naming.** Short name conflicts with potential future per-track Transform's opacity field. v0.10 uses `.opacity(_:)` for the modifier and `opacityFactor` for the stored field, mirroring the Clip protocol's split. Revisit if a Transform.opacity ever lands.
- **`ImageClip.color` on macOS via NSImage.** Solid-color `NSImage` synthesis differs slightly from `UIImage`; tests on both paths.

---

## v0.10.1 — Animation-clearing modifiers

**Status:** RFC. No code yet.

### Motivation

kadr's animation-bearing properties (`Clip.transform` / `transformAnimation`, `Clip.opacity` / `opacityAnimation`, `VideoClip.filters` / `filterAnimations`) ship setter modifiers that *install* an animation but no public path to *clear* one:

```swift
// kadr v0.10 surface — installation only
clip.transform(t)                            // sets static, preserves any existing animation
clip.transform(t, animation: a)              // sets static + animation
                                             // (no signature for "clear the animation, keep the static")
```

This asymmetry forces every consumer building a keyframe-authoring UI (the canonical case: `kadr-reels-studio`) to bypass the modifier surface and reconstruct the clip from `init(...)`, manually re-applying every property:

```swift
// reels-studio v0.3 Tier 1 — ProjectStore+Keyframes.swift, ~120 LOC
nonisolated static func rebuildVideoClip(
    _ source: VideoClip,
    transform: Transform?, transformAnimation: Animation<Transform>?,
    opacity: Double?, opacityAnimation: Animation<Double>?
) -> VideoClip {
    var rebuilt = VideoClip(url: source.url)
    if let trim = source.trimRange { rebuilt = rebuilt.trimmed(to: trim) }
    if source.isReversed { rebuilt = rebuilt.reversed() }
    if source.isMuted { rebuilt = rebuilt.muted() }
    if let curve = source.speedCurve { rebuilt = rebuilt.speed(curve: curve) }
    else if source.speedRate != 1.0 { rebuilt = rebuilt.speed(source.speedRate) }
    for (i, filter) in source.filters.enumerated() { … }
    // ... and so on
}
```

The maintenance footgun: every kadr release that adds a `Clip` field (more animatable properties, future modifiers like `.colorGrade`, etc.) means every editor consumer's rebuild helper silently loses that field unless updated in lock-step. Same shape as the silent-data-loss audit caught in reels-studio v0.2 Tier 1.5 (`TextStyle.color`, `VideoClip.filters`, `Transform` all dropping in the persistence bridge for the same reason).

This is defensive plumbing every editor consumer needs — it should live in kadr core, not get re-invented downstream.

### Public API

Add three setter modifiers per animatable-property type, surfaced on every `Clip` conformer that exposes the property:

```swift
extension VideoClip {
    /// Replace the transform animation, preserving the static base
    /// transform. Pass `nil` to clear the animation; the engine then
    /// renders the static value at every frame.
    public func transformAnimation(_ animation: Animation<Transform>?) -> VideoClip

    /// Replace the opacity animation. Pass `nil` to clear.
    public func opacityAnimation(_ animation: Animation<Double>?) -> VideoClip

    /// Replace the animation on `filters[index]`. Pass `nil` to clear.
    /// No-op if `index` is out of range.
    public func filterAnimation(at index: Int, _ animation: Animation<Double>?) -> VideoClip
}

extension ImageClip {
    public func transformAnimation(_ animation: Animation<Transform>?) -> ImageClip
    public func opacityAnimation(_ animation: Animation<Double>?) -> ImageClip
}

extension TitleSequence {
    public func transformAnimation(_ animation: Animation<Transform>?) -> TitleSequence
    public func opacityAnimation(_ animation: Animation<Double>?) -> TitleSequence
}
```

**Naming.** `transformAnimation(_:)` mirrors the storage property name. The modifier signature differs from the existing `transform(_:animation:)` (which sets both) so there's no overload collision. Consumers wanting "set both" keep using `.transform(_:animation:)`; consumers wanting "set just the animation" reach for `.transformAnimation(_:)`.

**Semantics.**
- Static base property unchanged.
- Animation field assigned to the new value.
- Clip identity (`clipID`, `startTime`) preserved.
- All other fields preserved.

### Tier breakdown

- **Tier 0** *(this PR)* — RFC. No code.
- **Tier 1** — Implement the seven modifiers (3 on VideoClip, 2 each on ImageClip / TitleSequence). ~80 LOC + 15 tests. Each test verifies: the target animation field updates correctly; nil clears it; no other field is disturbed; clip identity survives.
- **Tier 2** — Release prep + ship as **v0.10.1**.

### Test strategy

Per-modifier:
- **Set non-nil:** assert the animation field is the passed value.
- **Set nil:** assert the animation field is `nil` even when one was previously installed.
- **Field isolation:** start with a clip carrying every other field set (`trimRange`, `isReversed`, `isMuted`, `speedRate`, `speedCurve`, `filters`, `transform`, `opacity`, `clipID`, `startTime`); after applying the modifier, every other field equals its pre-call value.
- **Filter index out-of-range:** `filterAnimation(at: 99, _:)` returns the clip unchanged.

Target: ~15 new tests. Suite floor unchanged otherwise.

### Compatibility

- **Pure additive.** Every v0.10.0 composition compiles unchanged. No existing modifier signature is touched.
- **No semver-major bump.** Patch release v0.10.1 — additive setter modifiers are the textbook safe surface change.
- **Recommended consumer follow-up.** Once v0.10.1 is out, `kadr-reels-studio`'s `ProjectStore+Keyframes.swift` can drop the five `rebuildVideoClip` / `rebuildImageClip` / `rebuildTitleSequence` helpers (~120 LOC) and use the new modifiers directly. Same for any other consumer that's hitting the same pattern.

### Open questions (track in PRs, not blocking RFC merge)

- **Should `filterAnimation(at:_:)` raise on out-of-range index?** RFC says no-op for parity with kadr's existing tolerance for invalid input (e.g. `Filter.withScalar` on a non-scalar filter). Could go either way — surface a `KadrError.filterIndexOutOfRange` instead. Lean: silent no-op matches the editor-consumer mental model.
- **Position / Size animations on overlays.** kadr-ui v0.7 added `Overlay.positionAnimation` / `sizeAnimation` (on `ImageOverlay` / `StickerOverlay`). Should v0.10.1 ship matching `positionAnimation(_:)` / `sizeAnimation(_:)` clearers on the overlay types? Yes, in scope — same pattern, ~40 more LOC.
- **`AudioTrack.volumeAnimation`?** Not a thing today — kadr's `AudioTrack.volumeRamps` is array-based, not `Animation<Double>`. Leave alone unless a future tier unifies the surface.

## v0.11.0 — API hardening + correctness

**Status:** RFC. No code yet.

### Motivation

A cross-package audit before the v1.0 stability commitment surfaced three load-bearing correctness gaps in the public DSL that should be fixed *before* the API freezes — once v1.0 ships, each becomes a breaking change with no clean migration window.

The cycle is intentionally breaking; the v0.10.x patch ladder isn't the right home. Bundle in one cycle so consumers (kadr-ui v0.10.0, reels-studio v0.6.0) bump together.

### Scope lock — v0.11

In scope:
- **`CancellationToken` data-race fix.** Today: `_isCancelled: Bool` + `exportSession: AVAssetExportSession?` are non-atomic fields under `@unchecked Sendable`. `register()` (export background) and `cancel()` (UI) race; the `@unchecked` suppresses the compiler check without making it safe. Fix via `OSAllocatedUnfairLock` or actor isolation.
- **`VideoClip.speed` type-level exclusivity.** Today: `speed(_:)` and `speed(curve:)` mutually clear each other through a documented side-effect. Collapse to a single `Speed` enum: `.flat(Double)` / `.curved(Animation<Double>)`. Compile-time exclusivity. Migration: keep deprecated overloads for one minor.
- **`filterAnimations` keyed by stable filter ref, not parallel-array index.** Today: `filters: [Filter]` + `filterAnimations: [Animation<Double>?]` coupled by array index. Reordering one without rotating the other silently re-maps animations to the wrong filters. `ProjectDocument` v3 persistence shifts indices on filter deletion — a real bug waiting to fire. Introduce `FilterID` (UUID-backed) on each `Filter` case and key animations by id.
- **Stale comment sweep.** `Video.swift` multi-input compositor / `ImageClip.at(time:)` notes still reference "engine wiring lands in the multi-track engine PR" (shipped v0.6). Sweep.

Out of scope:
- Engine perf (CIImage pooling, duration caching) — v0.12.
- HDR / Dolby Vision pipeline — v0.13.
- Zero-duration / NaN-time defensive checks — track separately if QA flags.

### Public API changes

```swift
// MARK: - Tier 1: CancellationToken atomicity

// No public API change — internal field protection only. Callers see the
// same `register(...)` / `cancel()` surface; race-free under strict
// concurrency. `@unchecked Sendable` removed.

// MARK: - Tier 2: VideoClip.speed enum

public enum Speed: Sendable, Equatable {
    case flat(Double)
    case curved(Animation<Double>)
}

extension VideoClip {
    /// Replaces the old `speed(_:)` / `speed(curve:)` pair. Single setter,
    /// single getter. Deprecated `speed(_:)` / `speed(curve:)` overloads
    /// kept for one minor.
    public func speed(_ value: Speed) -> VideoClip
    public var speed: Speed { get }
}
```

```swift
// MARK: - Tier 3: Filter keyed by FilterID

public struct FilterID: Hashable, Sendable {
    public init(_ rawValue: String)  // matches ClipID / LayerID
}

extension Filter {
    /// Stable identity assigned at construction. Survives reorder, copy,
    /// and Codable round-trip. Animations bind to the id, not the array
    /// position.
    public var id: FilterID { get }
}

extension VideoClip {
    /// Animations are now a dictionary keyed by `FilterID`. The old
    /// parallel-array API stays for one minor (deprecated) and migrates
    /// on construction.
    public func filterAnimation(for id: FilterID, _ animation: Animation<Double>?) -> VideoClip
    public func filterAnimation(for id: FilterID) -> Animation<Double>?
}
```

### Migration

- **`speed`:** kept compat overloads emit a `Speed` case; deprecated for one minor; removed in v0.12.
- **`filterAnimations`:** the v0.10.1 `filterAnimation(at index: Int, _:)` clearer stays as a deprecated overload that resolves index → `FilterID` lazily. Consumer code (reels-studio v0.6 floor bump) flips to the keyed API. Removed in v0.12.
- **Codable shape:** `ProjectDocument`-style mirrors (reels-studio v3 schema) need a v4 bump that adds `filterID: String?` per filter; absent on v3 → assigned a deterministic id derived from `(clipID, arrayIndex)` so old projects load cleanly.
- **`CancellationToken`:** internal, no consumer changes.

### Tier breakdown

- **Tier 0** *(this PR)* — RFC. No code.
- **Tier 1** — `CancellationToken` atomicity. `OSAllocatedUnfairLock` around `_isCancelled` + `exportSession`; cancel-during-register race tests. ~50 LOC + ~6 tests.
- **Tier 2** — `Speed` enum collapse. `Speed` type; `VideoClip.speed(_ value: Speed)` setter; deprecated overloads; `SpeedSampler` updates if needed; ~80 LOC + ~10 tests.
- **Tier 3** — `FilterID` + keyed animations. `FilterID` struct; per-`Filter`-case `id` assignment; `filterAnimations: [FilterID: Animation<Double>?]` internal storage; new keyed surface; index-based deprecated overloads; ~150 LOC + ~15 tests (including ordering + Codable round-trip).
- **Tier 4** — Stale-comment sweep + release prep + tag v0.11.0.

### Test strategy

- **`CancellationToken`:** stress test 1000 concurrent `cancel()` / `register()` interleavings; assert `isCancelled` and `exportSession` reach consistent state.
- **`Speed`:** flat → curved → flat round-trip; Codable round-trip preserves case; deprecated overloads emit the right `Speed` case.
- **`FilterID`:** reorder filters → animation still attached to original filter; delete filter → animation cleared; Codable round-trip preserves `FilterID`; old-style index-based overloads resolve to the right `FilterID`.

Target: ~30 new tests. Suite: 536 → ~566.

### Compatibility

- **Breaking** for `VideoClip.speed` getter (now returns `Speed` enum, not `Double`).
- **Additive** for setters; deprecated overloads for one minor.
- **Codable schema bump** — kadr's own export shape doesn't change, but downstream `ProjectDocument` mirrors need a v3 → v4 bump (handled in reels-studio v0.6 Tier 2).
- **Kadr-ui floor** stays at ≥ 0.10.0 — no kadr-ui surface uses the changed types directly. But kadr-ui v0.10.0 bumps its kadr floor to 0.11 for cleanliness.

### Open questions

- **Should `Filter.withScalar(_:)` rebuild preserve `FilterID`?** RFC says yes — the scalar value is a property of the filter case, not its identity. Reordering or rebuilding doesn't issue a new id. Tested.
- **Should the deprecated `speed(_:)` overload accept `0` (= pause)?** Existing API does; keep the same semantics in the `.flat(0)` case so behavior doesn't shift mid-migration.
- **`@unchecked Sendable` audit on the rest of the package** — only `CancellationToken` was flagged, but worth a sweep. Track separately as a v0.11.x patch if more surface.
