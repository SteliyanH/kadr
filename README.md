# Kadr

[![CI](https://github.com/SteliyanH/kadr/actions/workflows/ci.yml/badge.svg)](https://github.com/SteliyanH/kadr/actions/workflows/ci.yml)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2016+%20|%20macOS%2013+%20|%20tvOS%2016+%20|%20visionOS%201+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

**SwiftUI for video. Compose, transform, export — in Swift you actually want to write.**

A modern, declarative Swift library for video composition on Apple platforms. Build videos using a result-builder DSL with async/await throughout. Multi-track timelines, transitions, overlays, filters with keyframe animation, custom per-frame compositors, time-anchored audio with crossfades — all on top of AVFoundation, no third-party dependencies.

> **Companion packages.** Kadr is the engine; three adapter packages consume its public surface for specific use cases. Pull them in separately as you need them — none are required for core composition / export.
>
> | Package | Purpose |
> |---|---|
> | [`kadr-ui`](https://github.com/SteliyanH/kadr-ui) | SwiftUI components — `VideoPreview`, `ThumbnailStrip`, multi-lane `TimelineView` (selection / reorder / trim / scrub / audio waveforms), `OverlayHost` with gesture-routed `LayerID` hit-testing, `InspectorPanel`, `KeyframeEditor`, animated `TextOverlay` preview, audio crossfade glyphs. |
> | [`kadr-captions`](https://github.com/SteliyanH/kadr-captions) | Caption file parsing + authoring for SRT, VTT, iTT, ASS, and SSA. Plus a styled-VTT bridge that maps a parsed cue onto kadr's `TextOverlay` + `textAnimation` for burned-in animated captions. |
> | [`kadr-photos`](https://github.com/SteliyanH/kadr-photos) | Photos library integration — resolves video / image / Live Photo `PHAsset`s into kadr clip types, ships a `PHPickerViewController` SwiftUI wrapper, surfaces PHAsset metadata, and bridges PHAssets to `ImageOverlay` / `StickerOverlay`. |

## Quick Start

The simplest possible composition — slideshow with background music:

```swift
import Kadr

let url = try await Video {
    ImageClip(heroImage, duration: 5.0)
}
.audio(url: musicURL)
.export(to: outputURL)
```

A more representative v0.8 composition — Ken Burns zoom-pan on a still, animated title reveal, picture-in-picture cutaway, and a music swap with a 1s crossfade:

```swift
let url = try await Video {
    ImageClip(heroPhoto, duration: 5.0)
        .transform(.identity, animation: .keyframes([
            .at(0.0, value: Transform(scale: 1.0)),
            .at(5.0, value: Transform(scale: 1.3, center: .normalized(x: 0.6, y: 0.4))),
        ], timing: .easeInOut))

    Transition.dissolve(duration: 0.5)
    VideoClip(url: clipURL).trimmed(to: 0...10)

    // PiP cutaway pinned at t=6s, 40% scale in the top-right
    VideoClip(url: cutawayURL).trimmed(to: 0...3)
        .at(time: 6.0)
        .transform(Transform(center: .topRight, scale: 0.4, anchor: .topRight))
}
.overlay(
    TextOverlay("MY MOVIE", style: TextStyle(fontSize: 80, alignment: .center, weight: .bold))
        .position(.center)
        .visible(during: 0.0...2.0)
        .animation(.fadeIn(duration: 1.0))
)
.audio {
    AudioTrack(url: musicAURL).at(time: 0).duration(8.0).crossfade(1.0)
    AudioTrack(url: musicBURL).at(time: 7.0)  // 1s overlap fades A → B
}
.preset(.reelsAndShorts)
.export(to: outputURL)
```

## Why Kadr?

FFmpegKit retired in January 2025. Pixel SDK sunset in February 2025. AVFoundation is powerful but verbose. The Swift video ecosystem needs a modern, native, declarative library.

**7 imperative functions become 3 DSL primitives + modifiers:**

| Before (imperative) | After (Kadr) |
|---|---|
| `generate(.single, image, audio)` | `Video { ImageClip(img) }.audio(url:).export(to:)` |
| `mergeMovies(videoURLs:)` | `Video { urls.map { VideoClip(url: $0) } }.export(to:)` |
| `reverseVideo(fromVideo:)` | `Video { VideoClip(url:).reversed() }.export(to:)` |
| `splitVideo(at:)` | `Video { VideoClip(url:).trimmed(to: 5...20) }.export(to:)` |
| `mergeVideoWithAudio(...)` | `Video { VideoClip(url:).muted() }.audio(url:).export(to:)` |

## Comparison

| | Kadr | AVFoundation (raw) | VideoLab | FFmpegKit |
|---|---|---|---|---|
| **API style** | Declarative DSL | Imperative | Layer-based | CLI wrapper |
| **Swift concurrency** | async/await native | Callbacks | No | No |
| **Swift 6 / Sendable** | Full strict concurrency | Partial | No | No |
| **Maintained (2026)** | Active | Apple (low-level) | Inactive | Retired (Jan 2025) |
| **Dependencies** | None (AVFoundation only) | N/A | None | FFmpeg binary |
| **Learning curve** | Minutes | Hours | Hours | Moderate |
| **License** | Apache 2.0 | Proprietary | MIT | LGPL |

## Features

### v0.9 (current — `0.9.2`)

The "Advanced timing" cycle. Three additions that finish kadr's timing story before the v1.0 semver lock. Pure additive — every v0.8 composition compiles unchanged.

- **Speed curves on `VideoClip`** *(v0.9.0)*. `.speed(curve: Animation<Double>)` — non-linear playback rate over clip-relative time. Engine integrates the curve into a piecewise-linear time map (30 Hz sampling) and applies via repeated `scaleTimeRange` segments. Audio (when present) follows the same time map. The signature CapCut feature.
- **`AudioTrack.speed(_:algorithm:)`** *(v0.9.1)*. Pitch-preserving audio speed in `0.25...4.0`. New `AudioTimePitchAlgorithm` enum (`.spectral` / `.timeDomain` / `.varispeed`). Fades, ramps, ducking, crossfades all operate on the scaled (timeline) duration.
- **`Caption` value type + `Video.captions(_:)`** *(v0.9.2)*. The AVFoundation caption bridge. Engine bakes attached cues as `AVMetadataItem` group at export. SRT / VTT / iTT / ASS / SSA file parsing lives in [`kadr-captions`](https://github.com/SteliyanH/kadr-captions); core stays bridge-only.

> **Next:** v1.0.0 — semver lock, performance benchmarks, comprehensive DocC tutorials. The v0.9 surface is the last public-API expansion before the lock. See [ROADMAP.md](ROADMAP.md).

### v0.8 (`0.8.4`)

The "Animation & Transform" cycle. v0.8.0 shipped the foundational surface; v0.8.1–v0.8.4 layered on real-user wins. **110 new tests across the cycle** (357 → 467); v0.7 compositions compile unchanged.

- **Per-clip Transform.** `Transform(center:rotation:scale:anchor:)` on `VideoClip` / `ImageClip` / `TitleSequence`. Reuses `Position` + `Anchor` from v0.3 overlays so the coordinate space is one consumers already know. Picture-in-picture, scaled cutaways, rotated clips.
- **Keyframe animations.** `Animation<T>` generic + `Animatable` protocol on `Transform` / `Double` / `Position` / `Size`. `TimingFunction` covers linear / easeIn / easeOut / easeInOut / cubicBezier / custom-closure. **Clip-relative timing** (a `.at(0.0, ...)` keyframe maps to the clip's first frame, not composition t=0). Drives both export and `makePlayerItem()` preview.
- **Animated `TextOverlay`.** `TextAnimation` protocol + built-in recipes (`.fadeIn`, `.slideIn`, `.scaleUp`). CALayer-backed export render via `AVVideoCompositionCoreAnimationTool`.
- **Animated overlay layout** *(v0.8.1)*. `.position(_:animation:)` and `.size(_:animation:)` on `ImageOverlay` / `StickerOverlay` — sliding watermarks, drifting stickers, animated logo placements.
- **Filter intensity animation** *(v0.8.2)*. `VideoClip.filter(_:animation:)` drives the primary scalar of any animatable filter (brightness, contrast, saturation, exposure, sepia, gaussianBlur, vignette, sharpen, zoomBlur, glow). Animated blur sweeps, fade-to-sepia, intensity-ramped vignette. Inner-Track clip Transforms / animations now also work in the pure-media Track fast path.
- **`AudioTrack.volumeRamp(start:end:during:)`** *(v0.8.3)*. Granular volume automation between two points in track-relative time. Multiple ramps accumulate; engine drops any that overlap implicit `fadeIn` / `fadeOut` / `crossfade` / `ducking` ranges.
- **More `Filter` presets** *(v0.8.4)*. `.gaussianBlur`, `.vignette`, `.sharpen`, `.zoomBlur`, `.glow` — each animatable.
- **Audio cross-fades.** `AudioTrack.crossfade(_:)` with declaration-order pairing. Engine emits matching volume ramps when adjacent tracks overlap and overrides user fades at the boundary.

### v0.7.0 (`0.7.0`)

- **Track names.** Optional `name:` parameter on `Track(...)` for downstream tooling. kadr-ui's `TimelineView` consumes it for lane labels.
- **Transitions in the implicit chain alongside multi-track parallel clips** — closes the v0.6 deferral. The engine pre-renders the chain to a temp `.mp4` (mirroring v0.6's Tracks-with-transitions pattern), then inserts it as a single piece on the main video track. No more `KadrError.notYetImplemented` for that combination.
- **Time-windowed compositors.** `Video.compositor(_:during:)` — single global `MultiInputCompositor` active only during a `CMTimeRange` / `ClosedRange<TimeInterval>`. Outside the window the engine falls back to its built-in alpha-composite blender. Closure forms also available.
- **AudioTrack timing.** `AudioTrack.at(time:)` and `.duration(_:)` — pin a track to a composition time and cap its playback length. Sound effects and time-anchored music are first-class. All volume / fade / ducking automation re-anchored to absolute composition time so timing-aware tracks layer correctly with chain audio.

### v0.6.0 (`0.6.0`)

- **Multi-track timeline.** Hybrid DSL: top-level clips chain implicitly (v0.5 unchanged); `.at(time:)` pins a clip to an explicit composition time as a free-floating parallel track; `Track { ... }` groups clips into a parallel sub-timeline anchored at `Track(at:)`. Layer ordering is declaration order — later renders on top.
- **Multi-input compositors.** `MultiInputCompositor` protocol (separate from v0.5's single-input `Compositor`) — `func process(images: [CIImage], context:) -> CIImage`. Attach via `Video.compositor(_:)`. Default behavior is alpha-composite later-over-earlier; custom blends run via a `KadrVideoCompositor` (custom `AVVideoCompositing` implementation).
- **Transitions inside Tracks** and **nested Tracks** via recursive pre-render. Mirrors the `FilterProcessor` pattern — Tracks containing transitions or nested Tracks are pre-rendered to a temp `.mp4` then inserted as a single piece on the parent's parallel video track.

### v0.5.0 (`0.5.0`)

- **Time-ranged overlay visibility**: `.visible(during: CMTimeRange)` / `.visible(during: ClosedRange<TimeInterval>)` on every overlay type — overlays render only during a portion of the composition.
- **LUTs**: `Filter.lut(LUT)` and the throwing factory `Filter.lut(url:)` for `.cube` 3D color-grading files. Standalone `LUT` value type loads + parses once for reuse across clips.
- **Chroma key**: `Filter.chromaKey(color:threshold:)` and the standalone `ChromaKey` value type. ITU-R BT.601 chroma distance, programmatic `CIColorCube` cube.
- **Custom compositors** *(foundation)*: public `Compositor` protocol + closure form, plus `CompositorContext` carrying per-frame `time` + `renderSize`. Plugs into the engine's existing per-clip pre-render pass.
- **Per-clip crop**: `VideoClip.crop(at:size:anchor:)` mirroring the composition-wide `Video.crop`. Built as a thin `Compositor`.
- **Alpha-mask crop**: `VideoClip.mask(_: CIImage)` / `mask(_: PlatformImage)` for non-rectangular shapes via `CIBlendWithAlphaMask`. Built as a thin `Compositor`.

### v0.4.1 (`0.4.1`)

- **Clip identity**: `ClipID` (string-backed, mirrors `LayerID`). Assign with `.id(_:)` on `VideoClip`, `ImageClip`, `TitleSequence`. IDs survive the existing modifier chain (`.trimmed`, `.reversed`, `.speed`, `.filter`, etc.) so callers can address clips across reorders and trims — driven by [`kadr-ui`](https://github.com/SteliyanH/kadr-ui)'s timeline component.

### v0.4.0 (`0.4.0`)

- **Composition introspection**: `Video.clips`, `overlays`, `audioTracks`, `preset`, and `crop` are publicly readable so callers can build their own timeline / preview / hit-testing UI without re-deriving state. Per-clip storage on `VideoClip`, `ImageClip`, and `AudioTrack` is also publicly readable.
- **Preview**: `Video.makePlayerItem()` returns an `AVPlayerItem` with the composition's videoComposition (preset, crop, transitions) and audioMix (background music, fades, ducking) pre-attached, ready for `AVKit.VideoPlayer`. `Video.thumbnail(at:)` renders a single composition frame.
- **Layout helpers**: `Layout.resolveFrame(position:size:anchor:in:)` mirrors the engine's coordinate math so custom UI can hit-test overlays in pixel-exact alignment with what the engine renders.
- **Companion packages**: three adapter packages now consume Kadr's public surface — see the table at the top of this README. [`kadr-ui`](https://github.com/SteliyanH/kadr-ui) for SwiftUI views; [`kadr-captions`](https://github.com/SteliyanH/kadr-captions) for SRT / VTT / iTT / ASS / SSA file I/O + a styled-VTT bridge; [`kadr-photos`](https://github.com/SteliyanH/kadr-photos) for Photos library integration (PHAsset resolvers, Live Photo, PHPicker SwiftUI wrapper, metadata, overlay helpers).

### v0.3 (`0.3.0`)

- **Layout primitives**: `Position` (`.normalized` / `.pixels` / `.percent` plus 9 named anchors), `Size` (with `.aspectFit` / `.aspectFill`), `Anchor`, and `LayerID`
- **Overlays**: `ImageOverlay`, `TextOverlay` + `TextStyle`, `StickerOverlay` (with `.shadow` and `.rotation` modifiers), and `Video.watermark(...)` sugar
- **Filters**: `VideoClip.filter(_:)` with built-in `CIFilter` presets — `.brightness`, `.contrast`, `.saturation`, `.exposure`, `.sepia`, `.mono`. Variadic and chainable.
- **Crop**: `Video.crop(at:size:anchor:)` — composition-wide rectangular crop sharing the layout coordinate system
- **Sugar**: `BackgroundMusic` (defaults: volume 0.6, fades, ducking), `TitleSequence` (text title clip with cross-platform rendering), `Timecode` (SMPTE `HH:MM:SS:FF` format/parse)

### v0.2

- **Transitions**: `.fade` (through black), `.dissolve` (cross-blend), `.slide` (4 directions) — wired through the engine with audio crossfades
- **Speed control**: `VideoClip.speed(_:)` — `0.25...4.0`, pitch-preserving
- **Audio ducking**: `AudioTrack.ducking(_:)` — auto-lowers music while clip audio plays
- **Frame-accurate timing**: every time-related API accepts `CMTime` for frame-precise edits, with `TimeInterval` overloads for ergonomic call sites

### v0.1

- Result-builder DSL (`Video { ... }`)
- `ImageClip` and `VideoClip` primitives
- `AudioTrack` with `.volume(_:)`, `.fadeIn(_:)`, `.fadeOut(_:)`
- Clip modifiers: `.trimmed(to:)`, `.reversed()`, `.muted()`, `.withAudio(_:)`
- Export presets: `.reelsAndShorts`, `.tiktok`, `.square`, `.cinema`, `.custom(...)`
- H.264 and HEVC codec support
- Progress reporting via `AsyncThrowingStream` with time estimation
- Thumbnail extraction: `VideoClip.thumbnail(at:)`
- Video metadata: duration, resolution, frame rate
- Typed errors via `KadrError`
- Export cancellation support

### Roadmap

See [ROADMAP.md](ROADMAP.md) for the full version plan.

## Examples

```swift
// Slideshow with background music
let url = try await Video {
    ImageClip(photo1)
    ImageClip(photo2)
    ImageClip(photo3)
}
.audio(url: musicURL)
.export(to: outputURL)

// Merge and trim video clips for Reels
let url = try await Video {
    VideoClip(url: clip1URL).trimmed(to: 0...10)
    VideoClip(url: clip2URL).trimmed(to: 5...15)
}
.preset(.reelsAndShorts)
.export(to: outputURL)

// Replace audio on a video
let url = try await Video {
    VideoClip(url: originalURL).muted()
}
.audio(url: newSoundtrackURL)
.export(to: outputURL)

// Transitions, slow-mo, and ducking music (v0.2)
let url = try await Video {
    VideoClip(url: introURL).trimmed(to: 0...3)
    Transition.dissolve(duration: 0.5)
    VideoClip(url: actionURL).trimmed(to: 0...4).speed(0.5)  // half-speed slow-mo
    Transition.slide(direction: .fromRight, duration: 0.4)
    VideoClip(url: outroURL).trimmed(to: 0...3)
}
.audio { AudioTrack(url: musicURL).volume(0.8).ducking(0.2) }  // music dips when clips speak
.export(to: outputURL)

// Title card, color-graded clip, watermark, and music (v0.3)
let url = try await Video {
    TitleSequence("MY MOVIE",
                  duration: 2.0,
                  style: TextStyle(fontSize: 96, alignment: .center, weight: .bold))
    Transition.fade(duration: 0.5)
    VideoClip(url: clipURL).trimmed(to: 0...10)
        .filter(.brightness(0.05), .contrast(1.1), .saturation(1.2))
}
.overlay(
    TextOverlay("LOCATION: HQ", style: TextStyle(fontSize: 40, weight: .medium))
        .position(.bottom)
        .anchor(.bottom)
)
.watermark(logo, position: .topRight, opacity: 0.5)
.crop(at: .center, size: .normalized(width: 0.9, height: 0.9))
.backgroundMusic(url: musicURL)  // defaults: 60% volume, fades, ducking
.export(to: outputURL)

// Multi-track timeline with PiP and a parallel Track block (v0.6)
let url = try await Video {
    VideoClip(url: mainURL).trimmed(to: 0...10)
    VideoClip(url: pipURL).trimmed(to: 0...3).at(time: 2.0)
    Track(at: 5.0, name: "B-Roll") {
        VideoClip(url: rollA).trimmed(to: 0...2)
        Transition.dissolve(duration: 0.3)
        VideoClip(url: rollB).trimmed(to: 0...2)
    }
}
.export(to: outputURL)

// Time-pinned sound effects + windowed multi-input compositor (v0.7)
let url = try await Video {
    VideoClip(url: baseURL).trimmed(to: 0...8)
    VideoClip(url: overlayURL).trimmed(to: 0...8).at(time: 0)
}
.compositor(MultiplyBlend(), during: 2.0...5.0)   // custom blend in window
.audio {
    AudioTrack(url: musicURL).volume(0.6).ducking(0.2)
    AudioTrack(url: stingURL).at(time: 5.0).duration(0.5)  // SFX punches in
}
.export(to: outputURL)

// Animated filter sweep + animated text reveal + audio crossfade (v0.8)
let url = try await Video {
    VideoClip(url: clipURL).trimmed(to: 0...4)
        .filter(.gaussianBlur(radius: 0), animation: .keyframes([
            .at(0.0, value: 20),   // start blurred
            .at(2.0, value: 0),    // focus pulls in
        ], timing: .easeOut))
}
.overlay(
    TextOverlay("CHAPTER ONE", style: TextStyle(fontSize: 80, weight: .bold))
        .position(.center)
        .visible(during: 0.0...2.0)
        .animation(.scaleUp(duration: 0.5))
)
.audio {
    AudioTrack(url: musicAURL).at(time: 0).duration(3.0).crossfade(0.5)
    AudioTrack(url: musicBURL).at(time: 2.5)
}
.export(to: outputURL)

// Export with progress tracking
let exporter = Video {
    VideoClip(url: longVideoURL)
}
.preset(.cinema)
.exporter(to: outputURL)

for try await progress in exporter.run() {
    print("\(Int(progress.fractionCompleted * 100))%")
}
```

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/SteliyanH/kadr.git", from: "0.10.0")
]
```

`from: "0.10.0"` picks up every minor and patch up to v1.0; bump to `from: "1.0.0"` once that ships for semver lock.

Or in Xcode: File > Add Package Dependencies > enter the repository URL.

**Requires:** Xcode 16+ / Swift 6.0+

## Platform Support

| Platform | Minimum Version |
|---|---|
| iOS | 16.0 |
| macOS | 13.0 |
| tvOS | 16.0 |
| visionOS | 1.0 |

## Architecture

Kadr separates the public DSL from the internal engine:

- **DSL layer** *(public, semver-stable)* — `Video`, `Track`, `VideoClip`, `ImageClip`, `TitleSequence`, `Transition`, `AudioTrack`, `Preset`, `Exporter`, `Filter`, `Animation<T>`, `Transform`, plus the overlay / compositor / animation surfaces.
- **Engine layer** *(internal, uses AVFoundation)* — `CompositionBuilder` (timeline assembly + multi-track routing), `FilterProcessor` (per-frame `CIFilter` pre-render with intensity animation), `KadrVideoCompositor` (custom `AVVideoCompositing` for multi-input compositors), `OverlayRenderer` (CALayer tree for `AVVideoCompositionCoreAnimationTool`), `PlaybackComposer` (`AVPlayerItem` for previews), `ExportEngine` (`AVAssetExportSession` driver), `ImageEncoder` (still-image fast path), `ReverseProcessor`.

The DSL is the stable public API. The engine is the implementation detail that can be refactored without breaking semver.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.

Apache 2.0 was chosen over MIT for its explicit patent grant, which is relevant for video processing code that touches codec patents (H.264, HEVC).
