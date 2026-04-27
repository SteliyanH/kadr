# Changelog

All notable changes to Kadr will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased] — v0.6.0 in progress

The "Multi-Track Timeline" cycle. Per the design locked in #55, v0.6 adds parallel tracks to the DSL via a hybrid shape (`.at(time:)` + `Track {}`) plus a `MultiInputCompositor` protocol for blending the new parallel tracks. Lands in tiers — see [ROADMAP.md](ROADMAP.md#v060--multi-track-timeline). This entry will accumulate as PRs land.

### Added — `MultiInputCompositor` protocol (Tier 3)

The multi-track / multi-input counterpart to v0.5's single-input ``Compositor``. Surface only — engine wiring lands with Tier 4.

- **`MultiInputCompositor` protocol** (`Sendable`) — `func process(images: [CIImage], context: CompositorContext) -> CIImage`. Synchronous return; same per-frame contract as v0.5's `Compositor`. `images` is the per-track contributions in declaration order (earlier = lower / background, later = higher / foreground).
- **`Video.compositor(any MultiInputCompositor)`** — attach a multi-track blender. Replaces any prior compositor (single-compositor model — multi-track output has one merge step).
- **`Video.compositor(@Sendable closure)`** — closure form, wraps in an internal `ClosureMultiInputCompositor`.
- **`Video.multiInputCompositor: (any MultiInputCompositor)?`** — public read-only storage. `nil` (default) means the engine uses its built-in alpha-composite later-over-earlier blender (`AlphaCompositeBlender`, internal) when more than one parallel track is active.
- Single-track compositions don't engage this surface — the v0.5 fast-path pipeline bypasses it entirely.

### Added — `Track {}` block (Tier 2)

Hybrid DSL's grouping form. A ``Track`` is a parallel sub-timeline anchored at an explicit composition time; clips inside chain in track-relative time and the whole track lives alongside the main timeline.

- **`Track`** — value type conforming to ``Clip``. Holds an ordered `[any Clip]` plus a `startTime`. Always parallel — never participates in the implicit linear chain. Inner clips chain among themselves following the same single-track rules (transitions allowed).
- **`Track { ... }`** — parameter-less init starts the track at composition `.zero`.
- **`Track(at: CMTime, ...)`** / **`Track(at: TimeInterval, ...)`** — anchored start.
- `Track.duration` sums inner clip durations. `Track.clipID` is `nil` (the inner clips carry their own IDs); inner clips remain individually addressable via `track.clips`.

Surface only — engine wiring lands with Tier 4. Tracks compile, read back through ``Video/clips``, and expose their inner clips via `Track.clips` for inspection; the engine still treats them like clips in the implicit chain in v0.6.0-pre builds.

### Added — `.at(time:)` surface (Tier 1)

The smallest piece of the v0.6 hybrid DSL. Pin a clip to an explicit composition start time; the clip opts out of the implicit linear chain and becomes a free-floating parallel track.

- **`Clip.startTime: CMTime?`** — protocol requirement with default `nil` implementation. Existing custom conformers don't change. ``Transition`` keeps the default since transitions don't make sense as free-floating tracks.
- **`.at(time:)` modifier** on ``VideoClip``, ``ImageClip``, ``TitleSequence``. Both `CMTime` (frame-accurate) and `TimeInterval` (ergonomic) overloads. Preserved across the existing modifier chain.

> **Surface only.** Engine wiring lands in the multi-track engine PR. Setting `.at(time:)` in v0.6.0-pre builds has no runtime effect yet — the clip still participates in the implicit chain. Final behavior arrives with Tier 4.

### Tests

- New `ClipAtTimeTests` suite (12 tests) covering the public-API contract via a non-`@testable` import — defaults across all clip types, both range forms, modifier-chain survival end-to-end, generic `[any Clip]` access, and surface-level visibility on `Video.clips` after building.
- New `TrackTests` suite (10 tests) covering `Track` construction (parameter-less + `at: CMTime` + `at: TimeInterval` overloads), duration summing (with and without transitions), Track-as-`Clip` participation in `Video.clips`, internal `clipID` addressability, generic protocol access, nested-track structural legality.
- New `MultiInputCompositorTests` suite (6 tests) covering the public `Video.compositor(_:)` modifier surface — defaults, protocol form, closure form, replacement semantics, survival across other Video modifiers, and inline closure-context assertion. Plus an `AlphaCompositeBlenderTests` suite (3 tests, `@testable`) exercising the engine-side default blender's empty / single / multi-input paths.

## [0.5.0] - 2026-04-27

The "Advanced Composition (per-clip processing)" release. Tier-based rollout: standalone additive features (Tier 1), the custom-compositor foundation (Tier 2), and built-in compositor consumers (Tier 3). Multi-track timeline work was scoped out to v0.6 — see [ROADMAP.md](ROADMAP.md#v060--multi-track-timeline).

### Added — Time-ranged overlay visibility

- **`Overlay.visibilityRange: CMTimeRange?`** — protocol requirement with a default `nil` implementation. Existing custom conformers don't need to change. `nil` = visible for the whole composition (current behavior).
- **`.visible(during:)`** modifier on ``ImageOverlay``, ``TextOverlay``, ``StickerOverlay``. Accepts both `CMTimeRange` (frame-accurate) and `ClosedRange<TimeInterval>` (ergonomic) per the project's CMTime/TimeInterval pattern. Preserved across the existing modifier chain.
- Engine: `OverlayRenderer.buildLayerTree` now accepts a `compositionDuration: CMTime` and attaches a `CAKeyframeAnimation` (calculation mode `.discrete`) to each visibility-bound overlay's `CALayer`, switching `opacity` between `0` and the overlay's `opacity` at the boundary times. Transition is instant (no fade); range is clamped to `[0, composition.duration]`.

### Added — Alpha-mask cropping (Tier 3)

Built on the v0.5 ``Compositor`` foundation. A second built-in `Compositor` shipped via top-level modifiers — completes the v0.5 Tier 3 alongside per-clip crop.

- **`VideoClip.mask(_ mask: CIImage)`** — masks the clip using the supplied image's alpha channel. Pixels under fully-opaque alpha pass through; under fully-transparent alpha become transparent. Anti-aliased mask edges produce proportional alpha (soft-edge masks, vignettes).
- **`VideoClip.mask(_ mask: PlatformImage)`** — convenience overload extracting `CIImage` from `UIImage` / `NSImage` cross-platform; pass-through if the conversion fails.
- Internal `MaskCompositor` uses `CIBlendWithAlphaMask` with a transparent background so masked-out regions become transparent (rather than blending with another image). Multiple `.mask` calls accumulate (logical AND of mask alphas across calls).

**Sizing.** The mask is stretched to fit each frame's extent. Authoring masks at the composition's preset resolution avoids distortion when aspect ratios differ.

### Added — Per-clip cropping (Tier 3)

Built on the v0.5 ``Compositor`` foundation — a thin built-in `Compositor` shipped via a top-level modifier.

- **`VideoClip.crop(at: Position, size: Size, anchor: Anchor = .center)`** — crops the clip's frames to a rectangular region, then scales the cropped pixels back to fill the original frame ("reframe / zoom-in" semantics). Mirrors the composition-wide ``Video/crop(at:size:anchor:)`` shape but operates per-clip. Multiple `.crop` calls accumulate (each subsequent crop further crops the previous result).
- Internal `CropCompositor` implements the geometry; users don't construct it directly.

**Aspect ratio.** If the crop's aspect ratio doesn't match the source frame's, pixels are stretched to fill (no letterbox). For aspect-preserved letterbox or composition-wide cropping, prefer ``Video/crop(at:size:anchor:)``. Documented in the modifier's DocC.

### Added — Custom compositors (Tier 2 foundation)

The architectural foundation for v0.5's per-clip processing. Public protocol consumers can write per-frame transformations as either a named conformer or an inline closure; both forms run inside the existing pre-render pass after `Filter`s.

- **`Compositor` protocol** — `Sendable`, single requirement: `func process(image: CIImage, context: CompositorContext) -> CIImage`. Synchronous return; the engine wraps in `applyingCIFiltersWithHandler` for the async finish.
- **`CompositorContext`** struct — `time: CMTime`, `renderSize: CGSize`. Wrapping in a struct (rather than loose params) leaves room for additional fields (`clipDuration`, `clipIndex`) in future releases without breaking custom conformers.
- **`VideoClip.compositor(_ compositor: any Compositor)`** — appends a named `Compositor` to the clip's compositor list.
- **`VideoClip.compositor(_ body: @Sendable @escaping (CIImage, CompositorContext) -> CIImage)`** — closure-based convenience for ad-hoc compositors.
- **`VideoClip.compositors: [any Compositor]`** — public read-only storage. Preserved across the existing modifier chain (`.trimmed`, `.reversed`, `.muted`, `.filter`, `.speed`, `.id`, `.withAudio`); every internal init now threads it through.
- **Engine**: `FilterProcessor.apply` extends to accept `compositors: [any Compositor]` alongside filters. Both run in the same `applyingCIFiltersWithHandler` per-frame closure — one extra encode/decode pass total even when both are set on a clip. Order: filters in declaration order, then compositors in declaration order.

Tier 3 features (per-clip crop, alpha-mask crop) ship as built-in `Compositor` implementations on top of this foundation.

### Out of scope for v0.5 (deferred to v0.6 alongside multi-track timeline)

- Multi-input compositors (e.g. a compositor that blends two source images for a custom transition). Requires the lower-level `AVVideoCompositing` path.

### Added — Chroma-key filter

- **`ChromaKey`** value type — `Sendable`, `Equatable`. Constructed with `ChromaKey(color: PlatformColor, threshold: Double)`. Synchronously precomputes a 64³ color cube using ITU-R BT.601 chroma distance (`(Cb, Cr)` Euclidean); pixels within `threshold` of the target's chroma are zeroed (premultiplied alpha = 0). Cube is reused across every clip the value is applied to.
- **`Filter.chromaKey(ChromaKey)`** — new case mapping to `CIColorCube`.
- **`Filter.chromaKey(color:threshold:)`** — convenience factory wrapping `ChromaKey(color:threshold:)`.
- **`ColorComponents`** value type — packed RGB-in-`[0,1]` extraction from `PlatformColor`. Public so callers can build a `ChromaKey` without going through the `PlatformColor` round-trip on macOS (where `NSColor` requires a color-space normalization step before component access).

### Added — LUT filter

- **`LUT`** value type — loads and parses a `.cube` 3D LUT file once. `Sendable`, `Equatable`. Constructed with `try LUT(url:)`; throws ``KadrError/invalidLUT(_:reason:)`` on missing file, missing `LUT_3D_SIZE`, mismatched entry count, or unsupported `LUT_1D_SIZE`. `TITLE` / `DOMAIN_MIN` / `DOMAIN_MAX` headers are accepted and ignored.
- **`Filter.lut(LUT)`** — new case mapping to `CIColorCube`. Accepts a pre-loaded `LUT` so the file is parsed once and reused across clips.
- **`Filter.lut(url:)`** throwing convenience factory — loads + wraps in one call. Equivalent to `.lut(try LUT(url: url))`.
- New `KadrError.invalidLUT(URL, reason: String)` case.

### Tests

- New `OverlayVisibilityTests` suite (7 tests) covering the public-API contract via a non-`@testable` import — defaults, both range forms, all three concrete overlays, modifier-chain survival.
- 2 new engine-side tests in `OverlayTests` verifying the keyframe animation attaches at `kadr.visibilityRange` with the right shape, and that overlays without a range still get full opacity and no animation.
- New `LUTTests` suite (12 tests) covering the `.cube` parser (valid identity LUT, comments + headers, missing dimension, mismatched count, 1D LUT rejection, malformed entries), the public init's I/O path, filter-case equality and CIFilter mapping, and the throwing convenience factory.
- New `ChromaKeyTests` suite (10 tests) covering construction, `Equatable` semantics, cube edge cases (threshold = 0 → fully opaque, threshold ≫ → fully transparent, mid threshold → partial removal), premultiplied-alpha invariant, filter-case mapping, and `ColorComponents` extraction.
- New `CompositorTests` suite (7 tests) covering the public-API contract via a non-`@testable` import — default empty list, protocol form append, closure-form wrap, multi-compositor accumulation in declaration order, modifier-chain survival, closure receives the right `CompositorContext`, and the public `CompositorContext` initializer.
- New `ClipCropTests` suite (6 tests) covering `VideoClip.crop(...)` — appends a compositor, preserves prior compositors, multiple crops accumulate, modifier-chain survival, default anchor smoke test, and a Compositor-protocol shape sanity check.
- New `ClipMaskTests` suite (6 tests) covering `VideoClip.mask(_:)` — both `CIImage` and `PlatformImage` overloads, prior-compositor preservation, multi-mask accumulation, modifier-chain survival, coexistence with `.crop`.

## [0.4.1] - 2026-04-27

Additive patch release driven by [`kadr-ui`](https://github.com/SteliyanH/kadr-ui)'s timeline component, which needs stable per-clip identity that survives reorders and trims. No breaking changes; adds one new public type and one new modifier method per media-clip type.

### Added ([#41](https://github.com/SteliyanH/kadr/pull/41))

- **`ClipID`** — stable, user-supplied identifier for clips, mirroring ``LayerID``'s role for overlays. `Hashable`, `Sendable`, `ExpressibleByStringLiteral`. Returns `nil` from ``Clip/clipID`` for unidentified clips and for ``Transition`` (which isn't an addressable unit).
- **`Clip.clipID: ClipID?`** — new protocol requirement with a default `nil` implementation. Existing custom conformers don't need to change.
- **`.id(_:)`** modifier on ``VideoClip``, ``ImageClip``, and ``TitleSequence`` — opt-in identifier assignment, preserved across the existing modifier chain (`.trimmed(to:)`, `.reversed()`, `.speed(_:)`, `.filter(_:)`, `.background(_:)`, etc.).

### Tests

- New `ClipIDTests` suite (12 tests) verifying the public surface, ID survival across modifier chains, generic protocol access via `[any Clip]`, and that ``Transition`` keeps the default `nil` ID. Full suite: 243.

### Documentation ([#42](https://github.com/SteliyanH/kadr/pull/42))

- README gains a v0.4.1 Features section.
- New `Examples/V041Showcase.swift` covering ID survival through modifier chains, generic `[any Clip]` iteration, and the selection-model pattern that timeline UIs use.

## [0.4.0] - 2026-04-27

The v0.4.0 release exposes the public introspection and preview primitives needed to build a UI layer on top of `Video`. Tracked separately from the [`kadr-ui`](https://github.com/SteliyanH/kadr-ui) SwiftUI package, which consumes these APIs.

### Added — Public introspection ([#34](https://github.com/SteliyanH/kadr/pull/34))

- `Video.clips`, `Video.overlays`, `Video.audioTracks`, `Video.preset`, `Video.crop` are now publicly readable. Iterate the composition's structure for custom timeline / preview / hit-testing UI without re-deriving state from the DSL.
- `CropRegion` is now public; its `position`, `size`, and `anchor` are publicly readable.
- `Preset.resolution: CGSize` and `Preset.frameRate: Int` are now public so callers can read pixel dimensions and fps from any preset (including `.custom`).
- `VideoClip` exposes `trimRange`, `isReversed`, `isMuted`, `replacementAudioURL`, `speedRate`, `filters` as public read-only properties.
- `ImageClip` exposes `backgroundColor` and `audioURL` as public read-only properties.
- `AudioTrack` exposes `volumeLevel`, `fadeInDuration`, `fadeOutDuration`, `duckingLevel` as public read-only properties.

### Added — Layout helpers ([#36](https://github.com/SteliyanH/kadr/pull/36))

- `Layout` — public namespace for layout helpers that mirror the engine's coordinate math.
- `Layout.resolveFrame(position:size:anchor:in:)` — resolve a `Position` + `Size` + `Anchor` triplet into the same render-space `CGRect` the export engine produces. Use from custom UI to draw hit-test regions that line up exactly with what the engine renders.

### Added — Preview API ([#37](https://github.com/SteliyanH/kadr/pull/37))

- `Video.makePlayerItem() async throws -> AVPlayerItem` (`@MainActor`) — produces an `AVPlayerItem` with the composition's videoComposition (preset resolution + frame rate, crop, transitions) and audioMix (background music, fades, ducking) pre-attached, ready for `AVKit.VideoPlayer`.
- `Video.thumbnail(at: CMTime) async throws -> PlatformImage` and `thumbnail(at: TimeInterval)` — render a single composition frame at `time` via `AVAssetImageGenerator`, honoring crop and preset resolution.
- **Overlays are intentionally not baked into the preview surface.** AVFoundation's `AVVideoCompositionCoreAnimationTool` is export-only and crashes if attached to a playback `videoComposition`. Preview consumers (e.g. kadr-ui) render overlays as views layered over the player using `Layout.resolveFrame(...)`. The exported file still bakes them in.

### Changed

- Extracted `buildSimpleVideoComposition` from `ExportEngine` to a shared internal `PlaybackComposer` ([#37](https://github.com/SteliyanH/kadr/pull/37)). Both export and preview pipelines now use the same videoComposition builder, so what plays back in `makePlayerItem()` matches what `export(to:)` writes (apart from the overlay limitation noted above). No behavior change for export.

### Tests

- New `IntrospectionTests` suite (14 tests) verifies the public read-only contract via a non-`@testable` import — a regression that demotes any introspection property back to `internal` will fail the build.
- New `LayoutHelpersTests` suite (7 tests) covers the public `Layout` API across normalized / pixel / percent / aspectFit cases and across multiple render sizes.
- New `PreviewAPITests` suite (8 tests) covers `makePlayerItem()` (image clip duration, video clip videoComposition shape, crop renderSize, overlay non-baking, identity-per-call) and `thumbnail(at:)` (returns a real frame, honors crop, accepts both `CMTime` and `TimeInterval`). Full suite: 202 → 231 across the v0.4.0 prep PRs.

### Documentation ([#38](https://github.com/SteliyanH/kadr/pull/38))

- New `Preview & Introspection (v0.4+)` Topics section in `Kadr.md` listing `Video.makePlayerItem()`, both `thumbnail(at:)` overloads, and the `Layout` namespace.
- `CropRegion` added to the Cropping section now that it's a public type.
- `README` Features gains a v0.4 row above v0.3.
- `Examples/V040Showcase.swift` — five recipes covering introspection-driven timeline, AVPlayer construction, async thumbnail strip, hit-testing via `Layout.resolveFrame`, and an end-to-end preview-then-export flow.

## [0.3.0] - 2026-04-26

Overlay DSL & filters release. Adds a coherent layer-on-top-of-video story (text, image, sticker, watermark) on a foundation that's ready for KadrUI's gesture handling in v0.4.

### Added — Foundation

- **`Position` / `Size` / `Anchor`** layout primitives ([#21](https://github.com/SteliyanH/kadr/pull/21)). `Position`: `.normalized` (default — resolution-independent), `.pixels`, `.percent`, plus 9 named anchors (`.topLeft`...`.bottomRight`). `Size` mirrors with `.aspectFit` / `.aspectFill` for media-aware layouts. `Anchor` is a 9-point alignment enum.
- **`LayerID`** stable identifier ([#22](https://github.com/SteliyanH/kadr/pull/22)). String-backed, `ExpressibleByStringLiteral`. Reserved for KadrUI hit-testing in v0.4.

### Added — Overlays

- **`ImageOverlay`** ([#23](https://github.com/SteliyanH/kadr/pull/23)) — image laid on top of the composition with `.position` / `.size` / `.anchor` / `.opacity` / `.id`. Wires `AVVideoCompositionCoreAnimationTool` into the export pipeline.
- **`Overlay`** protocol + **`TextOverlay`** + **`TextStyle`** ([#24](https://github.com/SteliyanH/kadr/pull/24)). Text overlays via `CATextLayer` with font weight, color, alignment, multi-line wrapping. `Video.overlay(_:)` is generic over any `Overlay`.
- **`StickerOverlay`** ([#25](https://github.com/SteliyanH/kadr/pull/25)) — distinct sticker primitive with `.shadow(...)` and `.rotation(_:)` modifiers (radians + degrees overloads) on top of the standard layout chain.
- **`Video.watermark(_:position:size:opacity:)`** sugar ([#26](https://github.com/SteliyanH/kadr/pull/26)) — corner-anchored, defaults to `.bottomRight` at 60% opacity. Layer ID `"watermark"`.

### Added — Filters & cropping

- **`Filter`** + **`VideoClip.filter(_ filters: Filter...)`** ([#27](https://github.com/SteliyanH/kadr/pull/27)). Six built-in `CIFilter` presets: `.brightness`, `.contrast`, `.saturation`, `.exposure`, `.sepia`, `.mono`. Variadic, accumulates with chained calls, applied per-clip via a pre-render pass through `AVMutableVideoComposition.videoComposition(applyingCIFiltersWithHandler:)`.
- **`Video.crop(at:size:anchor:)`** ([#28](https://github.com/SteliyanH/kadr/pull/28)). Composition-wide rectangular crop sharing the `Position` / `Size` / `Anchor` foundation. `videoComposition.renderSize` becomes the crop size; layer instructions are translated by `-cropOrigin` via `.concatenating(...)`.

### Added — Sugar

- **`BackgroundMusic`** + **`Video.backgroundMusic(...)`** ([#29](https://github.com/SteliyanH/kadr/pull/29)). Wraps `AudioTrack` with sensible defaults (volume 0.6, fadeIn 0.5s, fadeOut 1.0s, ducking to 0.3). `duckingLevel: nil` opts out.
- **`TitleSequence`** clip ([#29](https://github.com/SteliyanH/kadr/pull/29)). Title text + style + background, rendered to a `PlatformImage` at the export's render size when consumed by the engine. Cross-platform `NSAttributedString` rendering, multi-line via `\n`.
- **`Timecode`** SMPTE formatter ([#29](https://github.com/SteliyanH/kadr/pull/29)). `HH:MM:SS:FF` format/parse at `.fps24`/`.fps25`/`.fps30`/`.fps50`/`.fps60`/`.custom(Int)`. Drop-frame timecode (29.97/59.94 with `;`) intentionally not supported in v0.3.0.

### Changed

- `applyDucking` engine helper now skips ducking ramps that overlap fade-in/fade-out ranges via `CMTimeRangeGetIntersection` ([#29](https://github.com/SteliyanH/kadr/pull/29)). AVFoundation rejects overlapping volume ramps; this prevents the crash that surfaced when `BackgroundMusic`'s default fadeIn coincided with the start-of-clip ducking ramp.
- Single-`ImageClip` fast path in `Video.export` is now bypassed when **overlays** ([#23](https://github.com/SteliyanH/kadr/pull/23)) **or** **crop** ([#28](https://github.com/SteliyanH/kadr/pull/28)) are set — both require the videoComposition path.

### Tests

- Test count grew from 103 → **202** across new suites: `LayoutTests`, `OverlayTests`, `FilterTests`, `CropTests`, `SugarTests`.

### Documentation

- DocC `///` comments on every new public symbol.
- New "Layout / Overlays / Filters / Cropping / Sugar (v0.3+)" Topics sections in `Kadr.md`.
- Existing `FrameAccuracy` article remains the canonical reference for the `CMTime` / `TimeInterval` overload pattern, which `Position` and `Size` extend with their `.normalized` / `.pixels` / `.percent` distinction.

### Out of scope (deferred to v0.5)

- **Per-clip cropping** (`VideoClip.crop(...)`) — comes free with the planned custom-compositor work
- **Alpha-mask cropping** (any shape, not just rectangles) — same reason
- **Time-ranged overlay visibility** — overlays in v0.3.0 are visible for the entire composition. Time-ranging requires `CABasicAnimation` with `AVCoreAnimationBeginTimeAtZero`, deferred for engineering scope reasons.

## [0.2.1] - 2026-04-26

Polish release in response to community feedback. Same feature surface as v0.2.0 with frame-accurate timing throughout the API.

### Changed

- **API**: time-related parameters now accept `CMTime` for frame-accurate precision, with `TimeInterval` retained as ergonomic overloads. Internal storage of all durations migrated to `CMTime` / `CMTimeRange`. Engine arithmetic operates in `CMTime` end-to-end; fade halving uses `CMTimeMultiplyByRatio` (exact) instead of `seconds / 2`. ([#11](https://github.com/SteliyanH/kadr/pull/11))
  - `Transition.fade`, `.dissolve`, `.slide` cases now bind `CMTime`. Direct call sites (`Transition.fade(duration: 0.5)`) continue to work via static factory overloads. **Breaking** for code that pattern-matches the cases (`case .fade(let d)` now binds `CMTime`).
  - `VideoClip.trimmed(to: CMTimeRange)` added. Existing `.trimmed(to: ClosedRange<TimeInterval>)` retained.
  - `VideoClip.thumbnail(at: CMTime)` added.
  - `ImageClip(_:duration:)` and `ImageClip.duration(_:)` gain `CMTime` overloads.
  - `AudioTrack.fadeIn(_:)` / `.fadeOut(_:)` gain `CMTime` overloads.
- `VideoClip.trimmed` argument labels unified across overloads — both forms now use `to:`. ([#12](https://github.com/SteliyanH/kadr/pull/12))
- Transition validation now emits a specific error when an adjacent clip is an untrimmed `VideoClip` (synchronous duration is `.zero`), pointing the user at `.trimmed(to:)`. ([#14](https://github.com/SteliyanH/kadr/pull/14))

### Documentation

- DocC `///` comments added across every public symbol that didn't have one — `Video`, `VideoClip`, `ImageClip`, `AudioTrack`, `Clip`, `VideoBuilder`, `AudioBuilder`, `Preset`, `Codec`, `Exporter`, `ExportProgress`, `KadrError`. ([#13](https://github.com/SteliyanH/kadr/pull/13))
- New `FrameAccuracy.md` DocC catalog article explaining the `CMTime` vs `TimeInterval` overload pattern, the wall-clock vs media-time distinction, and the engine's precision guarantees.
- `ExportProgress.estimatedTimeRemaining` is documented as wall-clock (not media) time, hence `TimeInterval`.

### Tests

- Test count grew from 80 → 103. New suites: `CMTimeAPITests` (precision round-trip), `EdgeCasesTests` (mixed-timescale CMTime, speed × reverse, speed × dissolve, boundary clip durations, multiple background tracks with ducking).

## [0.2.0] - 2026-04-26

### Added

- **Transition engine** wired through `CompositionBuilder`:
  - `Transition.fade(duration:)` — fade-through-black; clips do not overlap
  - `Transition.dissolve(duration:)` — cross-blend; clips overlap by `duration`
  - `Transition.slide(direction:duration:)` — slide via `CGAffineTransform` ramp; supports `.fromLeft`, `.fromRight`, `.fromTop`, `.fromBottom`
  - All transitions overlay correctly with audio crossfades on overlapping clip audio
- **Speed control**: `VideoClip.speed(_ rate: Double)` — `0.25...4.0`. Audio pitch is preserved (`AVAssetExportSession.audioTimePitchAlgorithm = .spectral`).
- **Audio ducking**: `AudioTrack.ducking(_ targetVolume: Double)` — auto-lowers the music track's volume while clip audio is playing (100 ms ramp window).
- **Typed errors**: `KadrError.invalidTransition`, `.invalidSpeed`, `.invalidDuckingLevel` for export-time validation.

### Changed

- `Transition.fade` semantics: previously implemented as a cross-fade (overlapping clips with opposing opacity ramps). Now means **fade-through-black**, matching standard editing terminology. The previous behavior is available as `Transition.dissolve`. Since v0.1.0-alpha never wired transitions through the engine, no exported behavior is broken.
- Test suite grew from 48 → 80 tests (transitions, speed, ducking).

### Fixed

- CI: bundled `Tests/KadrTests/Resources/sample.mov` re-encoded to 540p/10s. The previous 4K source caused decode failures on the GitHub `macos-15` runner.

## [0.1.0-alpha] - 2026-04-23

### Added

- Result-builder DSL with `Video { ... }` syntax
- `ImageClip` for static image to video conversion
- `VideoClip` for existing video file manipulation
- `AudioTrack` with `.volume(_:)`, `.fadeIn(_:)`, `.fadeOut(_:)` modifiers
- Clip modifiers: `.trimmed(to:)`, `.reversed()`, `.muted()`, `.withAudio(_:)`
- Export presets: `.reelsAndShorts`, `.tiktok`, `.square`, `.cinema`, `.custom(...)`
- H.264 and HEVC codec support
- `Exporter` class with `AsyncThrowingStream<ExportProgress, Error>` for progress tracking
- `ExportProgress.estimatedTimeRemaining` time estimation
- `Exporter.cancel()` for cancelling in-progress exports
- `VideoClip.thumbnail(at:)` for frame extraction
- `VideoClip.metadata` for reading duration, resolution, frame rate
- `Transition` type (API defined, engine implementation deferred to v0.2)
- Typed errors via `KadrError`
- Platform type aliases (`PlatformImage`, `PlatformColor`) for cross-platform support
- SimpleEditor sample app
- 48 tests covering DSL, export, and API validation
