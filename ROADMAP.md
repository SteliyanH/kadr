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

## v0.6.0 — Multi-Track Timeline

DSL evolution to support parallel tracks and explicit time placement. Treated as a standalone milestone because it's a real DSL design effort (additive vs breaking, nesting model, kadr-ui implications), not a single feature addition.

- **Multi-track composition:** parallel timelines, e.g. `Video { Track { ... }; Track { ... } }` (exact shape under design)
- **Explicit time placement:** clips that opt into a fixed timeline range instead of the implicit "next clip starts where previous ended" semantic
- **kadr-ui:** `TimelineView` extended to render multiple lanes
- **Multi-track-aware compositors:** the v0.5 single-track-per-clip `Compositor` extended (or paired with a new protocol) for compositors that blend two source images — e.g., custom transitions

## v1.0.0 — Production Ready

Semver stability guarantee.

- API stability commitment — no breaking changes without major version bump
- Comprehensive documentation with tutorials
- Performance benchmarks
- CocoaPods support (if community demand warrants it)

---

## Kadr Pro

Premium features under a commercial license in the separate `kadr-pro` repository. Apple-platform–native — no GPU-bound research pipelines.

- **HDR / pro export:** HDR10, Dolby Vision, ProRes.
- **On-device AI:** auto-captions (`Speech`), smart crop (`Vision` saliency / face detection), background removal (`VNGenerateForegroundInstanceMask`). Runs on Apple Neural Engine; no cloud, no GPU dependencies.
- **Custom Metal shader effects:** user-supplied `.metal` shaders for per-frame effects.
- **Priority support.**

> Note: Text-driven generative AI editing (e.g. CLIP-based pipelines like Text2LIVE) is intentionally **out of scope**. Those need research-grade GPUs and don't fit the Apple-platform-native, ship-on-iPhone model. If we do anything in that direction it would be via on-device CoreML / Apple Intelligence APIs as they mature.

---

## Contributing

Want to help build the next version? Check [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. If a feature you want isn't on this roadmap, open an issue to discuss it.
