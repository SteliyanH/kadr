# Changelog

All notable changes to Kadr will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.11.0] - 2026-05-12

API hardening + correctness cycle. Closes three load-bearing issues surfaced by a cross-package audit before the v1.0 stability commitment: a data race in the export cancellation path, the documented-but-not-type-level mutual exclusion between flat and curved speed, and the parallel-index drift between filters and their animations. All three would have been breaking changes to fix post-v1.0; bundle now so consumers (kadr-ui v0.10.0, kadr-reels-studio v0.6.0) migrate once.

### Added

- **`Speed` enum** — canonical representation of clip playback speed. `.flat(Double)` and `.curved(Animation<Double>)` are mutually exclusive at the type level. New `VideoClip.speed(_ value: Speed)` setter + `var speed: Speed` getter (`.curved` wins over `.flat` when both storage fields are non-default, matching the engine's existing precedence).
- **`FilterID`** struct mirroring `ClipID` / `LayerID` shape — `Hashable`, `Sendable`, `ExpressibleByStringLiteral`. Static `.generate()` returns a UUID-backed id.
- **`VideoClip.filterIDs: [FilterID]`** — new public stored property parallel to `filters`. Auto-generated on every `.filter(_:)` call; threaded through every modifier rebuild so identities survive trim / id / opacity / speed / clearing modifiers.
- **Keyed filter API** on `VideoClip`:
  - `filter(for: FilterID) -> Filter?`
  - `filterAnimation(for: FilterID) -> Animation<Double>?`
  - `filterAnimation(for: FilterID, _ animation: Animation<Double>?) -> VideoClip`
  - `setFilter(for: FilterID, _ filter: Filter) -> VideoClip` — mutate filter payload while preserving id + bound animation. The intended migration target for consumers rebuilding via `withScalar`.
  - `removeFilter(for: FilterID) -> VideoClip` — drops the slot and its animation; leaves neighbors intact.

### Fixed

- **`CancellationToken` race.** Pre-v0.11 the type used `@unchecked Sendable` with **no synchronization** around `_isCancelled` and `exportSession`. `register()` (export background) and `cancel()` (UI) racing produced undefined behavior under Swift 6 strict concurrency. v0.11 backs the `@unchecked Sendable` claim with a real `NSLock` guarding every field access. AVFoundation calls (`cancelExport()`) happen outside the lock to avoid reentrancy with delegate callbacks. `@unchecked` stays because `AVAssetExportSession` lacks a `Sendable` conformance on macOS — but it's now load-bearing on the lock invariant, not "trust me".

### Deprecated (removal target v0.12)

- `VideoClip.speed(_ rate: Double)` → use `speed(.flat(rate))`.
- `VideoClip.speed(curve: Animation<Double>)` → use `speed(.curved(curve))`.
- `VideoClip.filterAnimation(at index: Int, _ animation: Animation<Double>?)` → use `filterAnimation(for: filterID, _: animation)`. The index-based surface is fragile under filter reordering; the keyed surface survives.

### Internal

- Stale v0.6-pre status comments removed from `Clip.swift`, `VideoClip.swift`, `ImageClip.swift`, `Video.swift` (placeholders for engine wiring that shipped in v0.6.0).

### Tests

30 new tests across three suites: `CancellationTokenTests` (8) covering single-thread sanity / both ordering paths / concurrent stress via GCD; `SpeedEnumTests` (8) covering both round-trip directions / structural exclusivity / deprecated-overload dispatch / field-preservation regression; `FilterIDTests` (14) covering id generation / `.filter(_:)` auto-population / `filter(for:)` lookup / animation setter round-trip + clear / `setFilter` preserves id+animation / `removeFilter` drops slot+animation.

### Compatibility

- **Breaking** for `VideoClip.speed` getter (now returns `Speed` enum, not `Double`). Deprecated setters cover the migration window.
- **Pure additive** for `FilterID` + keyed API. Existing `filters` / `filterAnimations` stored properties stay public for back-compat with downstream Codable mirrors.
- **No-op** for `CancellationToken` consumers — internal field protection only.
- Downstream `ProjectDocument`-style mirrors that serialize filter animations need a schema bump that adds `filterID` per filter; v0.10.x docs assign deterministic ids on load. Handled in kadr-reels-studio v0.6 Tier 2.

### Notes

- The `FilterID` design is **surgical** — `FilterID` lives on `VideoClip` parallel to `filters`, not on the `Filter` enum itself. Consumers passing `Filter` values around independently don't carry the id across copies; the keyed mutation path (`setFilter(for:_:)`) is the supported way to preserve identity across rebuilds. If a future consumer needs id-on-the-`Filter`-value semantics, escalate to a v0.12.x patch.

## [0.10.1] - 2026-05-05

Animation-clearing modifiers. Closes the install-but-can't-uninstall asymmetry that forced editor consumers (kadr-reels-studio's `ProjectStore`, every other keyframe-authoring UI) to reconstruct clips from `init(...)` and re-apply every property just to clear an animation. Pure additive — no existing modifier signature is touched.

### Added

- **`VideoClip.transformAnimation(_:)`** / **`VideoClip.opacityAnimation(_:)`** / **`VideoClip.filterAnimation(at:_:)`** — replace the named animation field, preserving the static base value and every other field. `filterAnimation(at:)` is a no-op for out-of-range indices (matches the editor-consumer mental model where stale indices can race with reorders).
- **`ImageClip.transformAnimation(_:)`** / **`ImageClip.opacityAnimation(_:)`**.
- **`TitleSequence.transformAnimation(_:)`** / **`TitleSequence.opacityAnimation(_:)`**.
- **`ImageOverlay.positionAnimation(_:)`** / **`ImageOverlay.sizeAnimation(_:)`**.
- **`StickerOverlay.positionAnimation(_:)`** / **`StickerOverlay.sizeAnimation(_:)`**.

Pass `nil` to clear; pass a non-nil `Animation<T>` to replace.

### Tests

18 new tests in `AnimationClearingModifiersTests` covering: set non-nil installs the field; set nil clears it; every other field preserves; `filterAnimation(at:)` addresses the indexed slot without disturbing siblings; out-of-range / negative indices no-op; field isolation per overlay kind. Suite: 521 → 536.

### Compatibility

- Pure additive. Every v0.10.0 composition compiles unchanged.
- One small visibility adjustment: `TitleSequence._duration` private → internal so the modifiers (in `Modifiers/Clip+AnimationClearing.swift`) can read it. No public-API change.

### Notes

- **Consumer follow-up**: kadr-reels-studio's `ProjectStore+Keyframes.swift` can drop the `rebuildVideoClip` / `rebuildImageClip` / `rebuildTitleSequence` helpers (~120 LOC) and use the new modifiers directly.
- **`AudioTrack.volumeAnimation`?** Not added — kadr's `AudioTrack.volumeRamps` is array-based, not `Animation<Double>`. A future tier could unify the surface.

## [0.10.0] - 2026-05-03

Pre-v1.0 polish. Three small additions before semver lock — closes gaps real consumers (kadr-reels-studio's `ProjectStore`, kadr-ui's `InspectorPanel`) hit while building against the v0.9.x surface. Pure additive — every v0.9.x composition compiles unchanged.

### Added

- **`Filter.withScalar(_:)` made public.** Was internal in v0.8.2 (engine-only). kadr-ui's `InspectorPanel` emits new scalar values through its `onFilterIntensity` callback, expecting consumers to rebuild filter cases — without a public helper they duplicate the 11-case switch (kadr-reels-studio v0.1.0 did exactly that). Pure visibility flip; no behavior change.
- **`ImageClip.color(_:duration:)`** — new static factory producing an `ImageClip` backed by a 1×1 `PlatformImage` of the given color. Memory-efficient (single pixel), artifact-free on stretch (every pixel identical). `CMTime` and `TimeInterval = 3.0` overloads. Replaces the ~30 LOC of swatch-rendering boilerplate in sample-project setups.
- **`Track.opacity(_:)`** — per-track opacity multiplier. Engine multiplies every inner clip's effective opacity by the track's factor at layer-instruction-build time. Common edit: "fade B-roll over A-roll" without per-clip wiring. Composes with per-clip `.opacity(_:)` (a clip at `.opacity(0.8)` inside a track at `.opacity(0.5)` renders at effective opacity `0.4`).

### Engine

- `ClipAnimationInfo` gains `opacityFactor: Double` (default `1.0`); explicit init keeps all existing call-sites compiling.
- `makeLayerInstruction` multiplies sampled (animated) or static opacity by `opacityFactor` before emitting `setOpacity`. When the clip has no per-clip opacity but the factor isn't `1.0`, the engine emits `setOpacity(Float(factor), at: clipStart)` so the fade applies uniformly.
- Multi-track pure-media fast path propagates `track.opacityFactor` to inner-clip records.
- Multi-track recursive pre-render path emits a single `ClipAnimationInfo` for the pre-rendered piece carrying the track factor.

### Tests

- 12 new tests covering `Filter.withScalar` public surface, `ImageClip.color` (CMTime / TimeInterval / default-duration / 1×1 source), `Track.opacityFactor` defaults + chainability, and an export smoke test that builds a `Video` with `Track.opacity(0.5)` over `ImageClip.color` sources and confirms export. Suite: 506 → 518.

### Notes

- Pure additive surface. Existing `kadr-ui` and `kadr-reels-studio` versions keep working; both can drop their duplicated `withScalar` shim once they bump their kadr dep floor to 0.10.0.
- This is the last public-API expansion before v1.0 (semver lock, DocC tutorials, perf benchmarks). See [ROADMAP.md](ROADMAP.md).

## [0.9.2] - 2026-04-29

Caption ingest — the AVFoundation bridge for caption metadata. Tier 3 of the v0.9 cycle and the final tier; **completes v0.9**.

Per the v0.9 RFC's locked split, this release ships only the AVFoundation bridge in core. SRT / VTT / iTT file-format parsers and writers live in the [`kadr-captions`](https://github.com/SteliyanH/kadr-captions) adapter (planned post-v0.9), which produces `Caption` values that flow into ``Video/captions(_:)`` here.

### Added

- **`Caption`** value type — `text: String` + `timeRange: CMTimeRange`. `Sendable`, `Equatable`.
- **`Video.captions(_:)`** modifier — attaches caption cues to the composition. Multiple calls accumulate.
- **Engine writer** — when captions are non-empty, `ExportEngine` assigns `exportSession.metadata` to `captions.map { $0.makeMetadataItem() }`. Each `AVMetadataItem` carries `.commonIdentifierDescription` plus the cue's `time` / `duration`. Players that surface video metadata (Apple Photos, system quick-look, AVPlayer's metadata APIs) read these directly.

### Behavior

- `captions` field is threaded through `Video.init`, every `Video` modifier, `Exporter.init`, and `Video.exporter(to:)` — no latent field-loss.
- Empty / `nil` captions array produces no metadata writes (no behavior change for v0.9.1 compositions).

### Tests

- 10 new tests covering surface (storage, equality), `AVMetadataItem` mapping (text value, time / duration, identifier), modifier behavior (default empty, single call, accumulation, field preservation), and the latent-bug guard. Suite: 496 → 506.

### Notes

- v0.9 cycle is now complete. Speed curves (`v0.9.0`), pitch-preserving audio speed (`v0.9.1`), and caption ingest (`v0.9.2`) collectively close the timing-related deferrals that were called out in the v0.9 RFC.
- Caption styling / animation belongs in the `kadr-captions` adapter — it can map onto v0.8 `TextOverlay` + `textAnimation`. Not a kadr-core surface.

## [0.9.1] - 2026-04-29

Pitch-preserving speed on `AudioTrack`. Closes the v0.7-deferred audio-side speed and is Tier 2 of the v0.9 cycle.

### Added

- **`AudioTrack.speed(_:algorithm:)`** — pitch-preserving speed multiplier in `0.25...4.0`. `1.5` plays the audio 1.5× faster; the configured algorithm keeps the pitch unchanged. Composes with all v0.7 / v0.8.3 audio surface — fades, ramps, ducking, and crossfades operate on the **scaled** (timeline) duration.
- **`AudioTimePitchAlgorithm`** public enum — `.spectral` (voice, default), `.timeDomain` (music at small ratios), `.varispeed` (no pitch correction; use for sound-design pitch shifts).
- **`speedRate: Double`** + **`pitchAlgorithm: AudioTimePitchAlgorithm`** fields on `AudioTrack` (additive — `1.0` / `.spectral` for v0.8 compositions).

### Engine

- Per-track `scaleTimeRange` on each `AVMutableCompositionTrack` + matching `audioTimePitchAlgorithm` on the mix input parameters.
- `insertEnd` accounts for the scaled duration so v0.8 cross-fade detection between adjacent tracks still works correctly under speed scaling.

### Behavior

- Out-of-range `speedRate` throws `KadrError.invalidSpeed` at export.
- All existing modifiers (volume, fadeIn/Out, ducking, crossfade, volumeRamp, at, duration) preserve `speedRate` / `pitchAlgorithm` — no latent field-loss.

### Tests

- 12 new tests covering surface (default speed, modifier storage, explicit algorithm, varispeed exposure), field preservation across all 8 existing modifiers, and the AVFoundation algorithm bridge. Suite: 484 → 496.

## [0.9.0] - 2026-04-29

Speed curves on `VideoClip` — non-linear playback rate over clip-relative time. The headline CapCut feature, and the first tier of the v0.9 cycle (advanced timing).

### Added

- **`VideoClip.speed(curve: Animation<Double>)`** — apply a non-linear speed curve. Values in the animation are speed multipliers (1.0 = normal, 0.5 = half-speed, 2.0 = 2×). Engine discretizes the curve at 30 Hz into piecewise-linear segments and emits one `scaleTimeRange` per segment, applying the same time map to audio when present. Composes with `trimmed(to:)`, `filter(_:animation:)`, `transform(_:animation:)`, and `opacity(_:animation:)`.
- **`speedCurve: Animation<Double>?`** field on `VideoClip` (additive — `nil` for v0.8 compositions, takes precedence over `speedRate` when set).
- **`SpeedCurveSampler`** internal helper module — pure discretization + integration helpers, fully unit-tested.

### Behavior

- Setting `speed(curve:)` overrides flat `speed(_:)`. Setting flat `speed(_:)` clears any previously-set curve. The two surfaces are mutually exclusive.
- Per-sample multipliers outside `0.25...4.0` clamp at the boundaries rather than throwing — animated curves may pass through extremes briefly, and clamping preserves the export rather than aborting it.
- `VideoClip.duration` integrates the curve when set, so synchronous timeline math agrees with the engine's per-segment scaling.

### Fixed

- **Latent v0.8 bug in `.speed(_:)`** — the existing flat-speed modifier silently dropped `transform` / `opacity` / animation / `clipID` / `startTime` fields when called (rebuilt the clip with an incomplete arg list, falling back to defaults). Now preserves them. Same bug-class would have hit the new curve modifier; both go through the full-fidelity rebuild path.

### Tests

- 17 new tests covering `SpeedCurveSampler` discretization (zero / negative / flat / extreme / out-of-range / contiguity), `VideoClip.speed(curve:)` modifier surface (storage, field preservation, mutual exclusion with flat speed), and `VideoClip.duration` math under a curve. Suite: 467 → 484.

## [0.8.4] - 2026-04-29

Five new `Filter` presets — `gaussianBlur`, `vignette`, `sharpen`, `zoomBlur`, `glow`. Closes the parity gap with IMG.LY and VideoLab. Final v0.8.x patch — v0.8 cycle is complete. Pure additive.

### Added

- **`Filter.gaussianBlur(radius:)`** — Maps to `CIGaussianBlur.inputRadius`. Default `10`. Animatable scalar: `radius`.
- **`Filter.vignette(intensity:)`** — Maps to `CIVignetteEffect.inputIntensity` (with fixed `inputRadius` of 1.5). Default `1.0`. Animatable scalar: `intensity`.
- **`Filter.sharpen(amount:)`** — Maps to `CISharpenLuminance.inputSharpness`. Default `0.4`. Animatable scalar: `amount`.
- **`Filter.zoomBlur(amount:)`** — Maps to `CIZoomBlur.inputAmount` (center fixed at the image's natural center). Default `20`. Animatable scalar: `amount`.
- **`Filter.glow(intensity:)`** — Maps to `CIBloom.inputIntensity` (with fixed `inputRadius` of 10). Default `1.0`. Animatable scalar: `intensity`.

Each new preset participates fully in the v0.8.2 filter intensity animation surface — the `withScalar(_:)` helper rebuilds with a substituted scalar so `.filter(_:animation:)` works on every new preset.

### Tests

- 14 new tests covering: default constructors, `withScalar` rebuild for each preset, CIFilter name mapping, application smoke (CIImage → CIImage no-throw), modifier chain participation in static + animated forms. Suite: 453 → 467.

### Why these five

The choices match what IMG.LY's 60-filter library covers as "essentials" and what VideoLab's `LookupFilter` / `ZoomBlur` / `Bloom` ship. Multi-parameter filters (with center positions, secondary radii, blend modes) are deferred — a future minor release can expose secondary parameters if there's demand.

### v0.8 cycle complete

This is the last v0.8.x patch. Counting v0.8.0 + v0.8.1 + v0.8.2 + v0.8.3 + v0.8.4: 110 new tests across the cycle (357 → 467).

Next cycle: **v0.9.0** — Advanced timing (speed curves on `VideoClip`, pitch-preserving `AudioTrack.speed(_:)`, caption authoring/ingest).

## [0.8.3] - 2026-04-29

`AudioTrack.volumeRamp(start:end:during:)` — granular volume automation curves between two points in track-relative time. Pure additive — every v0.8.2 composition compiles and behaves identically.

### Added

- **`AudioTrack.volumeRamp(start:end:during:)`** — accumulating modifier (CMTime + ClosedRange<TimeInterval> overloads). Each ramp linearly interpolates from `startVolume` to `endVolume` across `range`. Multiple calls accumulate.
- **`AudioTrack.VolumeRamp`** value type — public, `Equatable`. Track-relative time range.
- **`AudioTrack.volumeRamps: [VolumeRamp]`** — public storage, default empty.

### Engine

- `buildBackgroundAudioMixParameters` collects engine-emitted ramp ranges (effective fadeIn / fadeOut / crossfade / ducking) into an `occupiedRanges` array. User volumeRamps that overlap any occupied range are silently dropped — AVFoundation rejects overlapping ramps with an exception, so the engine takes the safe-by-default path. Non-overlapping user ramps are appended to the input parameters.
- New internal helper `rangesOverlap(_:_:)` — adjacency (a.end == b.start) treated as non-overlapping.

### Tests

- 8 new (modifier composition: defaults / CMTimeRange / ClosedRange / accumulate / preserved-through-chain; engine integration: emit-mix-params / overlapping-fadeIn-dropped / adjacent-ramps-both-apply). Suite: 445 → 453.

### Known limitation

Volume ramps are linear (matching AVFoundation's `setVolumeRamp` shape). Equal-power / S-curve ramps are still on the v0.8 RFC wishlist — pro-audio apps that need them can compose multiple linear ramps to approximate.

## [0.8.2] - 2026-04-29

Filter intensity animation + lifts the v0.8 Tier 1 inner-Track Transform / animation deferral. Pure additive — every v0.8.1 composition compiles and behaves identically.

### Added

- **`VideoClip.filter(_:animation:)`** modifier — apply a single ``Filter`` with a clip-relative keyframe animation driving the filter's primary scalar parameter. The engine samples the animation per frame inside ``FilterProcessor`` and rebuilds the filter with the new scalar via ``Filter/withScalar(_:)``.
- **`VideoClip.filterAnimations: [Animation<Double>?]`** — public storage parallel to `filters`. Calling `.filter(_:)` (static) appends a `nil`; calling `.filter(_:animation:)` appends the animation. Defensive engine path pads / truncates if the lengths drift.
- **`Filter.withScalar(_:)`** — internal helper that rebuilds a `Filter` case with a new scalar. Used by `FilterProcessor`. Filters without a primary scalar (`.mono`, `.lut`, `.chromaKey`) ignore the substitution and return self.
- Animation timing for filters is **clip-relative** (matches the v0.8 Transform / opacity contract): `.at(0.0, ...)` maps to the clip's first frame after trim. The engine offsets `request.compositionTime` by the clip's `trimRange.start` before sampling.

### Fixed — inner-Track clip Transform / animation deferral lifted

- v0.8 Tier 1 deferred per-clip `Transform` and animations on clips inside `Track {}` blocks. v0.8.2 lifts that deferral for the **pure-media Track fast path** (Track with only media clips, no transitions or nested Tracks). Inner-clip `transform`, `opacity`, and animations are now collected into the parallel-track's animations array and emitted as per-clip `setTransform` / `setOpacity` calls on the parallel track's layer instruction.
- Tracks-with-transitions / nested-Tracks already supported inner-clip transforms / animations via the recursive pre-render path (the inner clips go through `build()` → `buildMultiTrack` recursively, where Tier 1 / Tier 2 surface already applies). v0.8.2 just confirms the contract.

### Tests

- 11 new tests covering `Filter.withScalar` rebuilding, modifier composition (defaults / static-gets-nil-slots / animated-stores-pair / mix / chain preservation), engine integration (filter-animation export round-trip), and inner-Track clip Transform / animation in the fast path. Suite: 434 → 445.

### Known limitation

Filter intensity animation is per-filter scalar only. Filters with multi-parameter shapes (`.chromaKey`'s color + threshold, `.lut`'s data) aren't animatable in v0.8.2. Those would need a different surface (animate threshold separately) — defer until requested.

## [0.8.1] - 2026-04-28

First v0.8.x patch. Adds public `Animatable` conformance on `Position` and `Size`, plus animated `.position(_:animation:)` / `.size(_:animation:)` modifiers on `ImageOverlay` and `StickerOverlay`. Pure additive — every v0.8.0 composition compiles and behaves identically.

### Added

- `Position: Animatable` — public conformance promoting the v0.8.0 internal helper. Mixed-type pairs (e.g. `.normalized` ↔ `.pixels`) resolve at a unit canvas and lerp into a `.normalized` result; matching-type pairs lerp components directly.
- `Size: Animatable` — same shape. `.aspectFit` / `.aspectFill` cases use the unit-canvas resolution path; authors that care about preserving the aspect constraint mid-animation should switch to `.normalized` / `.pixels` / `.percent` keyframe values.
- `Overlay` protocol gains optional `positionAnimation: Animation<Position>?` and `sizeAnimation: Animation<Size>?` requirements (default nil). `TextOverlay` and `Watermark` keep defaults; `ImageOverlay` and `StickerOverlay` override with storage.
- `ImageOverlay.position(_:animation:)` and `.size(_:animation:)` modifiers
- `StickerOverlay.position(_:animation:)` and `.size(_:animation:)` modifiers
- Animation timing on overlays is **composition-relative** (not clip-relative) — overlays don't have a "clip lifetime" frame of reference. A keyframe `.at(0.0, ...)` maps to composition t=0.

### Engine

- `OverlayRenderer.applyOverlayLayoutAnimation` samples animations at 30 fps over the composition's duration and emits `CAKeyframeAnimation` for `position` (always when any layout animation is active — size animation also shifts the resolved frame's center) and `bounds.size` (only when size animation is active).

### Tests

- 14 new tests across `OverlayLayoutAnimationTests` covering `Animatable` math on `Position` / `Size`, mixed-type fallback, modifier composition on `ImageOverlay` / `StickerOverlay`, `TextOverlay` carrying nil defaults, and `OverlayRenderer` engine smoke. Suite: 420 → 434.

### Known limitation

When size animates with a non-`.center` overlay anchor, the layer's `anchorPoint` stays at `(0.5, 0.5)`, so size growth visually centers on the layer rather than preserving the anchor's render-space target. Workaround: pin overlays with size animations to `.center` anchor. Will be polished in a future patch if anyone hits it in practice.

## [0.8.0] - 2026-04-28

The "Animation & Transform" release. Last feature cycle before v1.0. Locks in foundational surface that would be breaking to add after semver — per-clip Transform, keyframe animations, animated TextOverlay, audio cross-fades. Built across an RFC + 4 implementation tiers ([#72](https://github.com/SteliyanH/kadr/pull/72) → [#73](https://github.com/SteliyanH/kadr/pull/73) → [#74](https://github.com/SteliyanH/kadr/pull/74) → [#75](https://github.com/SteliyanH/kadr/pull/75) → [#76](https://github.com/SteliyanH/kadr/pull/76)). Pure additive — every v0.7 composition compiles and behaves identically.

### Added — Per-clip Transform ([#73](https://github.com/SteliyanH/kadr/pull/73))

- New `Transform(center:rotation:scale:anchor:)` value type. Reuses existing `Position` / `Anchor` from v0.3 overlays so the coordinate space is one consumers already know. `Transform.identity` constant for "no transform".
- `Clip` protocol gains optional `transform: Transform?` requirement (default nil); `Transition` and `Track` keep the default.
- `.transform(_:)` modifier on `VideoClip`, `ImageClip`, `TitleSequence`. Calling twice replaces (transforms don't accumulate).
- Engine: `build()` routing now promotes transform-bearing single-track compositions through `buildMultiTrack` so `setTransform(_:at:)` calls have a videoComposition + layer instructions to live in. `makeLayerInstruction` accepts per-clip transforms and composes `base × userTransform.resolved(in: renderSize) × cropTransform` at each clip's start time.
- Inner-Track clip transforms are deferred to v0.8.2 (engine ignores; round-trips at value level).

### Added — Keyframe animation system ([#74](https://github.com/SteliyanH/kadr/pull/74))

- New `Animation<Value: Animatable>` generic + `Keyframe` nested type. `.keyframes(_:timing:)` factory sorts on construction.
- New `Animatable` protocol — single `interpolate(_:_:t:)` requirement. Built-in conformances on `Double` (linear lerp) and `Transform` (per-component lerp; anchor enum snaps at midpoint). `Position` interpolation is internal in v0.8.0; public conformance lands in v0.8.1 alongside overlay position/size animation.
- New `TimingFunction` — `linear` / `easeIn` / `easeOut` / `easeInOut` / `cubicBezier(p1, p2)` / `custom` closure. Newton-Raphson cubic-bezier solver matches CSS / `CAMediaTimingFunction`.
- `Clip` protocol gains optional `transformAnimation`, `opacity`, `opacityAnimation` requirements (default nil).
- New modifiers on each media clip type:
  - `.transform(_:animation:)` — base transform + clip-relative keyframes
  - `.opacity(_:)` — static opacity in `0...1`
  - `.opacity(_:animation:)` — base opacity + animation
- **Animation timing is clip-relative.** A keyframe `.at(0.0, value:)` maps to the clip's first frame, not composition t=0. Foundational contract — flipping later would be breaking.
- Engine: samples animations at the preset's frame rate within each clip's window; emits one `setTransform` / `setOpacity` call per sample. AVFoundation interpolates linearly between samples — sampling at frame rate gives the user's eased timing without further engine work.

### Added — Animated TextOverlay ([#75](https://github.com/SteliyanH/kadr/pull/75))

- New `TextAnimation` protocol — `func makeAnimations(for layer: CALayer) -> [CAAnimation]`. Custom conformers can drive any Core-Animation effect on the overlay's `CATextLayer`.
- Three built-in recipes:
  - `FadeIn(duration:from:beginTime:)` — opacity ramps from `from` (default 0) to the layer's base opacity
  - `SlideIn(from:duration:beginTime:)` — animates `position.x` or `position.y` from off-screen with default easeOut timing
  - `ScaleUp(from:duration:beginTime:)` — animates `transform.scale` from `from` (default 0) to 1.0
- Convenience factories: `.fadeIn(duration:)`, `.slideIn(from:duration:)`, `.scaleUp(duration:)`
- New `TextOverlay.animation(_:)` modifier
- Engine: `OverlayRenderer` attaches recipe animations to the text layer with stable keys (`kadr.textAnimation.<index>`) so they don't collide with the existing visibility-timing animation
- `FadeByLetter` (per-letter staggered reveal) staged for v0.8.x — char-level CATextLayer layout is its own focused work; `TextAnimation` accommodates it without breaking changes

### Added — Audio cross-fades ([#76](https://github.com/SteliyanH/kadr/pull/76))

- New `AudioTrack.crossfade(_:)` modifier (CMTime + TimeInterval overloads) and `crossfadeDuration: CMTime?` stored field
- Engine: when set and the next `AudioTrack` in declaration order overlaps this one's end, emits matching volume ramps — fade out on this track, fade in on the next — over `min(crossfadeDuration, overlap)`. Overrides user `fadeIn` / `fadeOut` at the boundary so AVFoundation never sees overlapping ramps. Ducking exclusions use the effective fades (not raw user values).
- `buildBackgroundAudioMixParameters` refactored into two phases (insertion ranges first, then ramps with crossfade-aware overrides) for O(1) neighbor lookups
- Equal-power / S-curve crossfades remain wishlist (linear ramps are perceptually fine for music swaps; pro-audio apps can build their own via the v0.8.3 `volumeRamp` API)

### Tests

- 63 new tests across the cycle:
  - 15 `Transform` value-type math + modifier composition + engine routing
  - 24 `Animation<T>` / `Animatable` / `TimingFunction` math + modifier composition + engine routing
  - 15 `TextAnimation` modifier composition + recipe correctness + engine smoke
  - 9 `AudioTrack.crossfade` modifier + engine integration on overlap / non-overlap / last-track edge cases
- Suite: 357 → 420.

### v0.8.x patches (planned, in order)

Per the [RFC](DESIGN.md#v08-design--animation--transform) and [ROADMAP](ROADMAP.md#v08x--patches-before-v09):

- **v0.8.1** — `Position` / `Size` as `Animatable`; animated `.position(_:animation:)` / `.size(_:animation:)` on `ImageOverlay` / `StickerOverlay` / `Watermark`
- **v0.8.2** — Filter intensity animation: `VideoClip.filter(_:animation:)` taking a single Filter + `Animation<Double>`. Also lifts the inner-Track clip-Transform deferral.
- **v0.8.3** — `AudioTrack.volumeRamp(start:end:during:)` for granular volume automation
- **v0.8.4** — More `Filter` presets: `gaussianBlur`, `vignette`, `sharpen`, `zoomBlur`, `glow`

## [0.7.0] - 2026-04-28

Multi-track polish + audio timing. Closes the two v0.6 deferrals (transitions-in-chain alongside multi-track, time-ranged compositor selection), adds named `Track` blocks for downstream tooling, and introduces real audio timing controls. Built across an RFC + 3 implementation tiers ([#65](https://github.com/SteliyanH/kadr/pull/65) → [#66](https://github.com/SteliyanH/kadr/pull/66) → [#67](https://github.com/SteliyanH/kadr/pull/67) → [#68](https://github.com/SteliyanH/kadr/pull/68)). Pure additive — every v0.6 composition compiles and behaves identically.

### Added — Track names ([#66](https://github.com/SteliyanH/kadr/pull/66))

- `Track.name: String?` — optional human-readable label on `Track`. `nil` by default. Three init overloads gain a `name:` parameter:
  - `Track(name:_:)`
  - `Track(at: CMTime, name:_:)`
  - `Track(at: TimeInterval, name:_:)`
- Surfaces via `Video.clips` for downstream tooling. kadr-ui v0.5.x will use this for `TimelineView` lane labels in place of auto-generated "Track 1" / "Track 2" captions.

### Fixed — Transitions in implicit chain alongside multi-track ([#66](https://github.com/SteliyanH/kadr/pull/66))

- Closes the v0.6.0 deferral. Previously the engine threw `KadrError.notYetImplemented` when the chain had a transition in multi-track mode (workaround: wrap the chain in a `Track {}`). Now it just works.
- Engine fix: `preRenderTrackToTempFile` generalized to `preRenderClipsToTempFile(clips:preset:)`. In `buildMultiTrack`'s chain handler, when the chain contains a transition, the full chain is pre-rendered to a temp `.mp4` and inserted as a single piece on the main video track. Same recursive pre-render pattern as v0.6 tier 4c.
- `clipAudioRanges` spans the full pre-rendered piece so background-music ducking continues to apply during the chain's duration.

### Added — Time-windowed compositors ([#67](https://github.com/SteliyanH/kadr/pull/67))

- `Video.compositor(_:during:)` — single global multi-input compositor active only during a window. Outside the window, the engine runs its built-in `AlphaCompositeBlender`. Frame-accurate; the active compositor is selected per frame at the composition-time level.
- Four overloads:
  - `compositor(any MultiInputCompositor, during: CMTimeRange) -> Video`
  - `compositor(any MultiInputCompositor, during: ClosedRange<TimeInterval>) -> Video`
  - `compositor(during: CMTimeRange) { images, ctx in ... } -> Video`
  - `compositor(during: ClosedRange<TimeInterval>) { images, ctx in ... } -> Video`
- New stored field `Video.compositorWindow: CMTimeRange?` (nil default, public read). Threaded through `Video → Exporter → CompositionBuilder.build → KadrVideoCompositionInstruction → KadrVideoCompositor.process`. Preview path (`PlaybackComposer`) also threaded so `makePlayerItem()` matches export.

### Added — AudioTrack timing ([#68](https://github.com/SteliyanH/kadr/pull/68))

- `AudioTrack.at(time:)` — pin an audio track to start at an explicit composition time. CMTime + TimeInterval overloads. Sound effects and time-anchored music are first-class.
- `AudioTrack.duration(_:)` — explicit cap on playback length from `startTime`. CMTime + TimeInterval overloads. When `nil` (default), the track plays the asset from `startTime` to its natural end, clamped to the composition's end.
- New stored fields: `AudioTrack.startTime: CMTime?`, `AudioTrack.explicitDuration: CMTime?`. Both nil-default — every v0.6 audio call site behaves identically.
- Engine (`CompositionBuilder.buildBackgroundAudioMixParameters`):
  - Inserts at `startTime ?? .zero` (was always `.zero`).
  - `insertDuration = min(audioDuration, totalDuration - insertionStart, explicitDuration ?? .infinity)`.
  - Volume / fade-in / fade-out / ducking automation re-anchored to absolute composition time so timing-aware tracks layer correctly with chain audio and other background tracks.
  - Tracks starting at or past `totalDuration` are skipped (no audible output, no allocated background track).

### Tests

- 19 new tests across the cycle:
  - 4 `Track(name:)` cases + 1 chain-pre-render integration test
  - 4 time-windowed compositor cases
  - 8 audio-timing modifier-storage cases + 3 engine-integration cases
- Suite: 338 → 357.

## [0.6.0] - 2026-04-27

The "Multi-Track Timeline" release. Per the design locked in #55, v0.6 adds parallel tracks to the DSL via a hybrid shape (`.at(time:)` + `Track {}`) plus a `MultiInputCompositor` protocol for blending the new parallel tracks. Shipped in tiers (#56 → #61) — see [ROADMAP.md](ROADMAP.md#v060--multi-track-timeline).

### Added — Recursive Track composition (Tier 4c)

Lifts the v0.6 Tier 4a restrictions on transitions inside `Track {}` and nested `Track {}`. Both now compose correctly via a recursive pre-render pattern.

- A `Track` containing a `Transition` or another `Track` triggers the **pre-render path**: its inner content is recursively built (via `CompositionBuilder.build` — picks up `buildSimple` / `buildWithTransitions` / `buildMultiTrack` as appropriate), exported to a temp `.mp4` via `AVAssetExportSession`, then loaded as a single `VideoClip` and inserted on the parent's parallel video track at the Track's `startTime`.
- A `Track` with only media clips (no transitions, no nested Tracks) continues to use the existing Tier 4a sequential-insert fast path — no extra encode/decode pass.
- Same pattern as `FilterProcessor`'s pre-render. Temp files are left in `FileManager.temporaryDirectory` for the system to reap; matches the rest of the engine's convention.
- Pre-render preset fallback: `AVAssetExportPresetHighestQuality` is preferred but falls back to `AVAssetExportPresetPassthrough` when incompatible with the composition shape (mirroring `ExportEngine`'s existing fallback). When passthrough is used, the inner videoComposition isn't applied — that's a known limitation for unusual composition shapes; transitions in real-video Tracks consistently take the re-encoded path.

This closes the v0.6 Tier 4 engine work. All four Tier 4a `notYetImplemented` paths (transitions in chain, transitions in Track, nested Track, custom `MultiInputCompositor`) now have engine support.

### Added — Custom `AVVideoCompositing` for `MultiInputCompositor` (Tier 4b)

Lifts the v0.6 Tier 4a "MultiInputCompositor ignored" restriction. When a user attaches a `MultiInputCompositor` via `Video.compositor(_:)`, the engine now actually invokes it per frame.

- **`KadrVideoCompositor`** (internal `NSObject`, `AVVideoCompositing`) — runs on a dedicated render queue; for each `AVAsynchronousVideoCompositionRequest`, pulls source frames from each parallel track, converts to `CIImage`, calls the user's compositor (or `AlphaCompositeBlender` as fallback), and renders the result to a fresh `CVPixelBuffer` from the request's render context.
- **`KadrVideoCompositionInstruction`** (internal `AVMutableVideoCompositionInstruction` subclass) — carries the active `MultiInputCompositor` reference and overrides `requiredSourceTrackIDs` / `passthroughTrackID` so AVFoundation knows to schedule per-track source frame decode and never to passthrough.
- **`CompositionBuilder.build`** gains a `multiInputCompositor` parameter, threaded from `Video.export` / `Exporter` / `PlaybackComposer`. When non-`nil` and the composition is multi-track, the build path attaches `KadrVideoCompositor` as the `customVideoCompositorClass` and uses the custom-instruction subclass; when `nil`, the multi-track path continues using AVFoundation's default compositor with layer-instruction blending (Tier 4a behavior).
- **`Exporter.multiInputCompositor`** internal property — Exporter retains the compositor for its build call; threaded by `Video.exporter(to:)`.

Single-track compositions continue using the v0.5 fast path (`applyingCIFiltersWithHandler`) with no change.

### Added — Multi-track engine (Tier 4a)

The first piece of v0.6's actual multi-track functionality. `CompositionBuilder` now detects multi-track compositions and wires them through a new `buildMultiTrack` path; default alpha-composite later-over-earlier blending via `AVMutableVideoComposition` layer instructions.

- **Detection** in `CompositionBuilder.build`: any clip with non-`nil` `startTime` *or* any `Track` instance routes to the multi-track path.
- **Per-piece video tracks**: implicit-chain clips on a main video track at t=0; each free-floating clip and `Track {}` on its own parallel video track at its declared start time. Each track's content goes through the existing `insertVideoClip` / `insertImageClip` / `TitleSequence` rendering helpers.
- **VideoComposition** with one instruction spanning `0...totalDuration` and one layer instruction per video track, in declaration order — AVFoundation's default compositor handles "later layer = on top".
- **Audio**: clip audio from chain and parallel pieces continues to flow through the shared composition audio track; background music mix unchanged.

**Tier 4a restrictions** (surfaced as `KadrError.notYetImplemented` so users get a clear error instead of silently-wrong output):

- Transitions in the implicit chain alongside multi-track parallel clips
- Transitions inside a `Track {}` block
- Nested `Track {}` blocks
- Custom `MultiInputCompositor`s — set on `Video.compositor(_:)` but not yet engaged. Default alpha-composite blending only.

All four lift in **Tier 4b**, which adds a custom `AVVideoCompositing` implementation for arbitrary blending and recursive Track composition.

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
- New `MultiTrackEngineTests` suite (8 tests, `@testable`) covering the multi-track dispatch path: single-track unchanged → no `videoComposition`; free-floating clip → 2 video tracks + 2 layer instructions; `Track {}` block → 2 video tracks (chain + Track-as-one); free-floating-only (no chain) → exactly N tracks; transitions-in-chain / transitions-in-Track / nested-Track all throw `KadrError.notYetImplemented`; total duration covers free-floating tails past the chain.
- New `KadrVideoCompositorTests` suite (5 tests, `@testable`) covering Tier 4b wiring: multi-track without compositor skips the custom class; multi-track with compositor attaches `KadrVideoCompositor` and upgrades the instruction to `KadrVideoCompositionInstruction` carrying the compositor reference; instruction's `requiredSourceTrackIDs` matches video-track count; `passthroughTrackID` is invalid; `Video.exporter(to:)` threads the compositor into `Exporter.multiInputCompositor`.
- New `MultiTrackRecursiveTests` suite (3 tests, integration — real `AVAssetExportSession` round-trip): Track with transition pre-renders and composes; nested Track pre-renders and composes; pure-media Track uses the fast path. The two `notYetImplemented` rejection tests for transitions-in-Track and nested-Track were removed from `MultiTrackEngineTests` since those restrictions lifted.

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
