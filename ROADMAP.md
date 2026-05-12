# Kadr Roadmap

This document outlines the planned feature releases for Kadr. Versions and timelines are subject to change based on community feedback.

## v0.1.0 — Stable Release ✓ shipped

Post-alpha stabilization based on community feedback.

- ✓ Bug fixes reported during alpha
- ✓ Documentation improvements
- ✓ Performance profiling of ImageEncoder and CompositionBuilder
- ✓ Edge case handling (very long videos, large images, corrupted input files)

## v0.2.0 — Transitions & Speed ✓ shipped

Implemented the transition engine and speed control. See [CHANGELOG.md](CHANGELOG.md#020---2026-04-26).

- ✓ Transition engine: `.fade` (fade-through-black), `.dissolve` (cross-blend), `.slide` (4 directions)
- ✓ Speed control: `.speed(_:)` modifier on `VideoClip` (0.25x to 4x), pitch-preserving
- ✓ Audio ducking: `.ducking(_:)` on `AudioTrack` — auto-lowers music when clip audio plays

## v0.2.1 — Frame-accurate timing ✓ shipped

Polish patch in response to community feedback. See [CHANGELOG.md](CHANGELOG.md#021---2026-04-26).

- ✓ `CMTime` accepted across the time-related API surface (overlays for `TimeInterval` retained)
- ✓ Engine arithmetic operates in `CMTime` end-to-end (exact halving, no float drift)
- ✓ DocC across every public symbol + `FrameAccuracy` catalog article

## v0.3.0 — Overlay DSL & Filters ✓ shipped

Visual composition layered on top of video, plus the coordinate primitives that unblock KadrUI in v0.4. See [CHANGELOG.md](CHANGELOG.md#030---2026-04-26).

**Foundational**

- ✓ `Position` (`.normalized` default, `.pixels`, `.percent` plus 9 named anchors), `Size` (with `.aspectFit` / `.aspectFill`), `Anchor`, `LayerID`

**Overlay DSL**

- ✓ `ImageOverlay`, `TextOverlay` + `TextStyle`, `StickerOverlay` (with `.shadow` and `.rotation`) — all conforming to a public `Overlay` protocol so `Video.overlay(_:)` is heterogeneous
- ✓ Watermarking: `Video.watermark(_:position:size:opacity:)` sugar over the overlay primitives
- ✓ Sugar: `BackgroundMusic` (defaults: volume / fades / ducking), `TitleSequence` (in-engine text rendering)

**Filters & cropping**

- ✓ Filters: `VideoClip.filter(_:)` with built-in `CIFilter` presets — `.brightness`, `.contrast`, `.saturation`, `.exposure`, `.sepia`, `.mono`. Variadic and chainable.
- ✓ Crop: `Video.crop(at:size:anchor:)` — composition-wide rectangular crop sharing the layout coordinate system

**Polish**

- ✓ SMPTE timecode formatter: `Timecode(fps:)` — `HH:MM:SS:FF` format/parse at `.fps24` / `.fps25` / `.fps30` / `.fps50` / `.fps60` / `.custom(Int)`. Drop-frame intentionally not supported.

**Deferred to v0.5** (alongside custom compositors)

- Per-clip cropping (`VideoClip.crop(...)`)
- Alpha-mask cropping (non-rectangular shapes)
- Time-ranged overlay visibility (overlays appearing during a portion of the composition)

## v0.4.0 — Composition Introspection & Preview Primitives ✓ shipped

Public APIs that let any caller — including the new [`kadr-ui`](https://github.com/SteliyanH/kadr-ui) package — render previews, generate thumbnails, draw timelines, and hit-test overlays without re-deriving state from the DSL. See [CHANGELOG.md](CHANGELOG.md#040---2026-04-27).

**Introspection**

- ✓ Public read-only access on `Video`: `clips`, `overlays`, `audioTracks`, `preset`, `crop`
- ✓ `CropRegion` made public; `Preset.resolution` and `Preset.frameRate` exposed
- ✓ Per-clip property exposure (`VideoClip.trimRange`/`isReversed`/`isMuted`/`speedRate`/`filters`, `ImageClip.backgroundColor`/`audioURL`, `AudioTrack.volumeLevel`/`fadeInDuration`/`fadeOutDuration`/`duckingLevel`)

**Preview**

- ✓ `Video.makePlayerItem() async throws -> AVPlayerItem` (`@MainActor`) for `AVKit.VideoPlayer` integration
- ✓ `Video.thumbnail(at: CMTime)` and `thumbnail(at: TimeInterval)` for composition-level frame rendering

**Layout**

- ✓ Public `Layout.resolveFrame(position:size:anchor:in:)` mirroring the engine's internal frame resolver — KadrUI uses this for pixel-exact hit-testing in the same coordinate space the engine renders in

**Architectural note**

- Overlays are intentionally **not** baked into the preview surface (`makePlayerItem` / `thumbnail`) — `AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer:in:)` is export-only and crashes if attached to a playback `videoComposition`. Preview consumers render overlays as views layered over the player using `Layout.resolveFrame(...)`. The exported file still bakes them in.

The `kadr-ui` SwiftUI package consuming these primitives ships on its own version track. See its [roadmap](https://github.com/SteliyanH/kadr-ui#status) for `VideoPreview`, `TimelineView`, `ThumbnailStrip`, and gesture-handler component plans.

## v0.4.1 — Clip identity ✓ shipped

Additive patch driven by kadr-ui's `TimelineView` selection / reorder / trim work. Pure introspection-style addition; no breaking changes. See [CHANGELOG.md](CHANGELOG.md#041---2026-04-27).

- ✓ `ClipID` — stable, user-supplied per-clip identifier mirroring `LayerID`'s role for overlays
- ✓ `.id(_:)` modifier on `VideoClip`, `ImageClip`, `TitleSequence` — preserved across modifier chains
- ✓ `Clip.clipID: ClipID?` protocol requirement (defaulted to `nil`); `Transition` keeps the default

## v0.5.0 — Advanced Composition (per-clip processing) ✓ shipped

Per-clip processing features built on a public custom-compositor surface. See [CHANGELOG.md](CHANGELOG.md#050---2026-04-27).

**Standalone additive features**

- ✓ Time-ranged overlay visibility — `.visible(during:)` (CMTimeRange + TimeInterval overloads) on every overlay type
- ✓ LUTs — `Filter.lut(LUT)` + `Filter.lut(url:)` factory; standalone `LUT` value type
- ✓ Chroma key — `Filter.chromaKey(color:threshold:)` + standalone `ChromaKey` value type

**Foundation: custom compositors**

- ✓ `Compositor` protocol (`Sendable`) + `CompositorContext` struct
- ✓ `VideoClip.compositor(any Compositor)` and closure form `.compositor { image, ctx in ... }`
- ✓ Pipeline integrated through the existing per-clip pre-render pass (after `Filter`s)

**Custom-compositor consumers**

- ✓ Per-clip cropping — `VideoClip.crop(at:size:anchor:)`, built as a thin built-in `Compositor`
- ✓ Alpha-mask cropping — `VideoClip.mask(_: CIImage)` / `mask(_: PlatformImage)`, also built as a built-in `Compositor`

## v0.6.0 — Multi-Track Timeline ✓ shipped

DSL evolution to support parallel tracks and explicit time placement. Fully additive — every v0.5 single-track composition continues to compile and behave identically. See [CHANGELOG.md](CHANGELOG.md#060---2026-04-27).

**DSL — hybrid shape**

- ✓ `.at(time:)` modifier on `VideoClip` / `ImageClip` / `TitleSequence` — pins a clip to an explicit composition time. CMTime + TimeInterval overloads
- ✓ `Track { ... }` block — groups clips into a parallel sub-timeline anchored at `Track(at:)`. Always parallel; never participates in the implicit chain
- ✓ Top-level clips without `.at(...)` continue to chain as today (the implicit "main track")
- ✓ Layer ordering: declaration order = render order (later renders on top), matching `Video.overlay(_:)`

**Multi-input compositors**

- ✓ `MultiInputCompositor` protocol (separate from v0.5's single-input `Compositor`) — `func process(images: [CIImage], context: CompositorContext) -> CIImage`. Additive; v0.5 conformers unchanged
- ✓ `Video.compositor(_:)` modifier (protocol form + closure form) — attaches a multi-track blender. Default when no custom compositor is set: alpha-composite later-over-earlier (`AlphaCompositeBlender`)

**Engine**

- ✓ `CompositionBuilder.buildMultiTrack` — detects multi-track compositions and assembles per-piece parallel video tracks; default `AVMutableVideoComposition` layer-instruction blending
- ✓ Custom `AVVideoCompositing` (`KadrVideoCompositor`) — engaged when a `MultiInputCompositor` is set; pulls source frames from each parallel track per request, calls the user compositor, renders the result to a fresh `CVPixelBuffer`
- ✓ Recursive Track composition — Tracks containing transitions or nested Tracks are pre-rendered to a temp `.mp4` then inserted as a single piece on the parent's parallel video track. Same pattern as `FilterProcessor`

**Out of scope (carries over)**

- Transitions in the implicit chain alongside multi-track parallel clips still rejected with `KadrError.notYetImplemented`. Workaround: wrap the chain in a `Track { }` — Tracks support transitions internally *(closed in v0.7 via chain pre-render)*
- kadr-ui's multi-lane `TimelineView` ships with kadr-ui v0.5+ as a follow-up milestone, same staging as the v0.4 → kadr-ui v0.4 cycle *(shipped in kadr-ui v0.5.0 / v0.5.1)*

## v0.7.0 — Multi-track polish & audio timing ✓ shipped

Closes the v0.6 deferrals on transitions-in-chain and time-ranged compositors, adds named Tracks for downstream tooling, and introduces the first audio timing controls. Pure additive — every v0.6 composition compiles and behaves identically. See [CHANGELOG.md](CHANGELOG.md#070---2026-04-28).

**Polish**

- ✓ `Track(name:)` — optional human-readable label on Track. Surfaces via `Video.clips` for downstream tooling; kadr-ui v0.5.x consumes it for `TimelineView` lane labels.
- ✓ Closes v0.6 deferral: transitions in the implicit chain alongside multi-track parallel clips. Engine pre-renders the chain to a temp `.mp4` (same pattern as Tracks-with-transitions in v0.6 tier 4c).

**Time-windowed compositors**

- ✓ `Video.compositor(_:during:)` — single global multi-input compositor active only during a `CMTimeRange` / `ClosedRange<TimeInterval>`. Outside the window, the engine falls back to its built-in alpha-composite blender.
- ✓ Closure forms: `Video.compositor(during:){ images, ctx in ... }`.

**Audio timing**

- ✓ `AudioTrack.at(time:)` — pin an audio track to start at a composition time. CMTime + TimeInterval overloads.
- ✓ `AudioTrack.duration(_:)` — explicit cap on playback length from `startTime`. Engine inserts at `min(asset duration, available window, explicit cap)`.
- ✓ All volume / fade-in / fade-out / ducking automation re-anchored to absolute composition time so timing-aware tracks layer correctly with chain audio and other background tracks.

## v0.8.0 — Animation & Transform ✓ shipped

The last feature cycle before v1.0. Foundational additions locked in before semver — per-clip transform, keyframe animations, animated text overlays, audio cross-fades. Pure additive — every v0.7 composition compiles and behaves identically. See [CHANGELOG.md](CHANGELOG.md#080---2026-04-28).

- ✓ **Per-clip Transform** — `Transform(center:rotation:scale:anchor:)` on `VideoClip` / `ImageClip` / `TitleSequence`. Static case wires to `AVMutableVideoCompositionLayerInstruction.transform`; animation feeds into the keyframe pipeline.
- ✓ **Keyframe animations** — `Animation<T>` generic + `Animatable` protocol conformances on `Transform` and `Double`. `TimingFunction` (linear, easeIn, easeOut, easeInOut, cubicBezier, custom). Clip-relative timing semantics. Drives both export and `makePlayerItem()` preview.
- ✓ **Animated `TextOverlay`** — `TextAnimation` protocol + built-in recipes (`FadeIn`, `SlideIn`, `ScaleUp`). CALayer-backed export render via `AVVideoCompositionCoreAnimationTool`.
- ✓ **Audio cross-fades** — `AudioTrack.crossfade(_:)` modifier with declaration-order pairing. Engine emits matching volume ramps over `min(crossfadeDuration, overlap)` and overrides user fades at overlap boundaries so AVFoundation doesn't see overlapping ramps.

## v0.8.x — Patches before v0.9

Real user needs that don't have to ship in the v0.8.0 headline but should land before v0.9 starts. All additive, none breaking. Each ships as its own minor release.

- **v0.8.1** ✓ shipped — `Position` / `Size` as `Animatable` + `.position(_:animation:)` / `.size(_:animation:)` on `ImageOverlay` / `StickerOverlay`. Unlocks animated image/sticker overlays (sliding watermarks, drifting stickers, animated logo placements).
- **v0.8.2** ✓ shipped — Filter intensity animation: `VideoClip.filter(_:animation:)` taking a single `Filter` + `Animation<Double>`. Animated blur sweeps, gradual sepia fades, intensity-ramped vignette. Also lifts the v0.8 Tier 1 inner-Track clip Transform / animation deferral for the pure-media Track fast path.
- **v0.8.3** ✓ shipped — `AudioTrack.volumeRamp(start:end:during:)` — granular volume automation between two points. Engine drops user ramps that overlap implicit fadeIn / fadeOut / crossfade / ducking ranges to avoid AVFoundation's overlapping-ramp exception.
- **v0.8.4** ✓ shipped — More `Filter` presets: `gaussianBlur`, `vignette`, `sharpen`, `zoomBlur`, `glow`. Each animatable via `Filter.withScalar(_:)`. Closes the parity gap with IMG.LY and VideoLab. **v0.8 cycle complete.**

## v0.9.x — Advanced timing

The pre-v1.0 cleanup of timing-related deferrals. Each tier ships as its own minor.

- **v0.9.0** ✓ shipped — Speed curves on `VideoClip` via `.speed(curve: Animation<Double>)`. Non-linear speed (ease in/out, custom Bézier, hold), beyond v0.2's flat speed multiplier. The signature CapCut feature.
- **v0.9.1** ✓ shipped — `AudioTrack.speed(_:algorithm:)` — pitch-preserving via `audioTimePitchAlgorithm` (.spectral / .timeDomain / .varispeed). Closes the v0.7-deferred audio-side speed.
- **v0.9.2** ✓ shipped — `Caption` value type + `Video.captions(_:)` modifier + engine `AVMetadataItem` writer. The AVFoundation bridge only — SRT / VTT / iTT parsers live in the [`kadr-captions`](#kadr-captions) adapter package. **v0.9 cycle complete.**

## v0.10.0 — Pre-v1.0 polish ✓ shipped

Three small additions before semver lock — closes gaps real consumers hit while building against v0.9.x. Pure additive.

- **`Filter.withScalar(_:)` made public** — was internal in v0.8.2; consumers building inspector UIs can now reuse the helper instead of duplicating the 11-case switch.
- **`ImageClip.color(_:duration:)`** — solid-color clip factory backed by a 1×1 PlatformImage source.
- **`Track.opacity(_:)`** — per-track opacity multiplier. Engine multiplies every inner clip's effective opacity by the track factor at layer-instruction-build time.

## v0.10.1 — Animation-clearing modifiers ✓ shipped

Defensive plumbing patch closing the install-but-can't-uninstall asymmetry on every animation field. Adds `transformAnimation(_:)` / `opacityAnimation(_:)` / `filterAnimation(at:_:)` setters across `VideoClip` / `ImageClip` / `TitleSequence`, plus `positionAnimation(_:)` / `sizeAnimation(_:)` on `ImageOverlay` / `StickerOverlay`. Pass `nil` to clear; non-nil to replace. Pure additive — every v0.10.0 composition compiles unchanged.

This is the last *non-breaking* public-API expansion before the v0.11 hardening cycle.

## v0.11.0 — API hardening + correctness *(planned)*

Pre-v1.0 cycle absorbing three breaking-but-necessary fixes flagged in a cross-package audit before the v1.0 stability commitment. Four tiers:

1. **`CancellationToken` atomicity** — `OSAllocatedUnfairLock` around `_isCancelled` + `exportSession`; `@unchecked Sendable` removed.
2. **`VideoClip.speed` collapsed to a `Speed` enum** (`.flat(Double)` / `.curved(Animation<Double>)`); compile-time exclusivity. Deprecated overloads for one minor.
3. **`FilterID` + keyed animations** — `filterAnimations` becomes `[FilterID: Animation<Double>?]`; reorders / deletes don't silently re-map. Deprecated index-based surface for one minor.
4. **Stale-comment sweep** + release prep + tag.

Consumer impact: kadr-ui v0.10.0 + reels-studio v0.6.0 bump kadr floor to ≥ 0.11.0.

## v0.12.0 — Engine perf *(planned)*

CIImage pooling in `KadrVideoCompositor`; `Video.duration` caching; `OverlayRenderer` per-frame batching. Driven by reels-studio v0.7's perf test suite.

## v0.13.0 — HDR / Dolby Vision / projected media *(planned)*

HDR transfer-function preservation through the compositor; Dolby Vision metadata pass-through; Apple Projected Media Profile (APMP) read awareness. Pairs with kadr-photos v0.7.

## v1.0.0 — Production Ready

Semver stability guarantee. Every public surface from v0.8 / v0.9 is locked.

- API stability commitment — no breaking changes without major version bump
- Comprehensive DocC tutorials: Slideshow, Multi-track, Custom compositors, Keyframe animations, Editor app walkthrough
- Performance benchmarks — single-track export, multi-track with `KadrVideoCompositor`, keyframe-heavy compositions
- Migration guide v0.x → v1.0
- CocoaPods support (if community demand warrants it)

---

## Adapter packages (separate repos, optional)

Small, focused, dependency-bearing packages that consume kadr's public surface without bloating the core. Each lives in its own GitHub repo and ships on its own version track.

### `kadr-photos`

Photos-library integration. Adds clip source types backed by `PHAsset`. Lives in its own repo because it depends on the `Photos` / `PhotosUI` frameworks, which kadr core deliberately avoids.

- `PHAssetClip(asset:)` — adopt `Clip`, load video / image data from a Photos library asset
- Live Photo support (still + motion as a unit)
- iCloud download progress reporting

Targets first release after kadr v0.8 ships (when `Transform` is stable for image-clip framing).

### `kadr-captions`

SRT / VTT / iTT caption file parsing and authoring. Could land as part of kadr v0.9 instead of as a separate package if the surface stays small (one parser + one author + one `AVMetadataItem` builder). Decision in the v0.9 RFC.

---

## Example application — `kadr-reels-studio`

Flagship example app demonstrating the full kadr + kadr-ui surface end-to-end. Lives in its own repo (not buried in `Examples/`) so it gets its own README, screenshots, App Store-quality demo. Ships as a real free app on the App Store alongside kadr v1.0.

**Purpose**

- Integration test for the full kadr + kadr-ui surface — feature gaps surface as missing in the app
- Marketing material — screenshots and GIFs for launch posts and the README
- A real reference implementation showing the "post-FFmpegKit / Pixel SDK" replacement story

**Feature surface (matches kadr's release cadence)**

- **v0.1** (against kadr v0.7 / kadr-ui v0.5.3) — Slideshow + multi-track timeline + overlays + BGM with ducking + time-pinned SFX + presets + export with progress
- **v0.2** (after kadr v0.8 / kadr-ui v0.6) — adds Inspector panel (Transform, Filters, Opacity sliders), keyframe editor surface, animated text reveals
- **v1.0** — alongside kadr v1.0; production-ready, App Store distribution

---

## Kadr Pro

Premium features under a commercial license in the separate `kadr-pro` repository. Kicks off **after kadr v1.0** so the OSS core's API surface is locked first. Apple-platform–native — no GPU-bound research pipelines.

- **HDR / pro export:** HDR10, Dolby Vision, ProRes.
- **On-device AI:** auto-captions (`Speech`), smart crop (`Vision` saliency / face detection), background removal (`VNGenerateForegroundInstanceMask`). Runs on Apple Neural Engine; no cloud, no GPU dependencies.
- **Custom Metal shader effects:** user-supplied `.metal` shaders for per-frame effects.
- **Templates engine:** brand-consistency layer for SDK consumers (matches IMG.LY's templates surface).
- **Priority support.**

> Note: Text-driven generative AI editing (e.g. CLIP-based pipelines like Text2LIVE) is intentionally **out of scope**. Those need research-grade GPUs and don't fit the Apple-platform-native, ship-on-iPhone model. If we do anything in that direction it would be via on-device CoreML / Apple Intelligence APIs as they mature.

---

## Explicit non-goals

Captured here to keep scope focused — these are *not* on any roadmap unless community demand changes.

**Hard non-goals (architectural)**

- AR / face tracking effects (Banuba's lane)
- Multiplexed compositor chains — keyframe animations on a single compositor cover this
- Per-Track compositor overrides — time-windowed global compositor covers it
- Real-time DSP audio nodes (reverb, EQ, compression) — users wanting that should reach for AudioKit
- After-Effects-style pre-compose / `RenderLayerGroup` — `Track {}` already covers the use case
- Templates engine in the OSS core — application-level concern; kadr-pro covers SDK-consumer templates

**Wishlist (may never ship — additive if they do)**

These were considered for v0.8 / v0.9 and intentionally left off. They're not breaking to add later, but the user need is thin enough that we may never implement them. Captured so the analysis isn't redone every cycle.

- Per-keyframe timing functions (different ease per `Animation<T>` segment) — global timing + `.custom` closure covers 95%
- Equal-power / S-curve audio cross-fades — linear is perceptually fine; pro-audio apps can build via `.volumeRamp(...)`
- `Animation<T>` on `Compositor` parameters — compositor authors hold their own animation state
- `CropRegion` keyframes (composition-level animated crop) — clip-level `Transform` animation covers Ken Burns

---

## Contributing

Want to help build the next version? Check [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. If a feature you want isn't on this roadmap, open an issue to discuss it.
