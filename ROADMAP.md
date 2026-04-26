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

## v0.3.0 — Overlay DSL & Filters

Visual composition — layers on top of video — and the foundational coordinate primitive that unblocks KadrUI.

**Foundational**

- **`Position` type:** `.normalized(0...1)` (default — resolution-independent), `.pixels(_, in: .renderSpace)`, `.percent`. Picked before overlays so KadrUI hit-testing in v0.4 doesn't force a breaking change.
- **Stable layer IDs:** every overlay node gets an ID (user-supplied or auto-derived) so `VideoPreview` / `TimelineView` can route gestures back to layers.

**Overlay DSL**

- **`Text { ... }` / `Image { ... }` / `Sticker { ... }`:** result-builder primitives with `.position(_:)`, `.anchor(_:)`, `.size(_:)`, `.opacity(_:)` modifiers. The DSL *is* the description language.
- **Watermarking:** `Video.watermark(image:position:opacity:)` — sugar over the overlay primitives.
- **`BackgroundMusic` / `TitleSequence`:** thin wrappers over the existing `AudioTrack` / `Video` APIs for ergonomic call sites.

**Filters & cropping**

- **Filters:** `VideoClip.filter(_:)` with built-in presets — brightness, contrast, saturation, exposure, sepia, mono.
- **Crop:** `Video.crop(at:size:anchor:)` — composition-wide rectangular crop sharing coordinate-system code with overlays.

**Polish**

- **SMPTE timecode formatter:** `Timecode(fps: .fps24)` — small utility for time-display use cases.

## v0.4.0 — KadrUI

Separate SwiftUI package for video editing components. Built on the v0.3.0 `Position` + layer-ID foundations.

- `VideoPreview` — preview a `Video` composition before export
- `TimelineView` — visual timeline showing clips, transitions, audio
- `ThumbnailStrip` — scrubbing strip generated from video thumbnails
- **Gesture handlers:** `.onTap`, `.onDrag` on overlay layers — hit-tests through the layer ID contract from v0.3.0
- Ships as a separate `kadr-ui` package depending on `Kadr`

## v0.5.0 — Advanced Composition

Multi-track and precision composition features.

- **Timeline API:** Multi-track composition with explicit time placement
- **Chroma key:** `.chromaKey(color:threshold:)`
- **Color grading / LUTs:** `.lut(url:)` for loading `.cube` LUT files
- **Custom compositors:** Public protocol for user-defined per-frame processing
- **Per-clip cropping:** `VideoClip.crop(...)` — different crops per clip, enabled by the custom-compositor work
- **Alpha-mask cropping:** non-rectangular shapes from an image or path, also unlocked by custom compositors

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
