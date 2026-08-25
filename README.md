# Kadr

[![CI](https://github.com/SteliyanH/kadr/actions/workflows/ci.yml/badge.svg)](https://github.com/SteliyanH/kadr/actions/workflows/ci.yml)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSteliyanH%2Fkadr%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SteliyanH/kadr)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSteliyanH%2Fkadr%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SteliyanH/kadr)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/steliyanh)

**SwiftUI for video. Compose, transform, export — in Swift you actually want to write.**

A modern, declarative Swift library for video composition on Apple platforms. Build videos using a result-builder DSL with async/await throughout. Multi-track timelines, transitions, overlays, filters with keyframe animation, custom per-frame compositors, time-anchored audio with crossfades — all on top of AVFoundation, no third-party dependencies.

**[API documentation →](https://swiftpackageindex.com/SteliyanH/kadr/documentation/kadr)**  ·  built and hosted by the Swift Package Index for every release.

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

Everything below is in the shipping public API. For what changed in which
release, see [CHANGELOG.md](CHANGELOG.md) — it is not duplicated here, so it
cannot drift out of date here either.

**Composition**
- Result-builder DSL over `Video`, `Track`, `VideoClip`, `ImageClip` and `TitleSequence`, `async`/`await` throughout, no third-party dependencies.
- Multi-track timelines with named lanes and per-track opacity; time-anchored audio tracks.
- `KadrVideoCompositor` for custom per-frame compositing, and `makePlayerItem()` so a composition previews before it exports.

**Transform and animation**
- `Transform(center:rotation:scale:anchor:)` on every clip type — picture-in-picture, scaled cutaways, rotated clips.
- `Animation<T>` with `Animatable` conformances for `Transform`, `Double`, `Position` and `Size`. `TimingFunction` covers linear, ease-in/out, cubic Bézier and custom closures.
- **Keyframes are clip-relative**: a keyframe at `0.0` maps to the clip's first frame, not composition zero. The same animations drive export and live preview.

**Filters**
- Animatable presets including brightness, contrast, saturation, exposure, sepia, gaussian blur, vignette, sharpen, zoom blur and glow.
- Keyed by `FilterID`, so animations bound to a filter survive reordering instead of drifting onto their neighbours.

**Overlays and text**
- `TextOverlay` with built-in animation recipes (`.fadeIn`, `.slideIn`, `.scaleUp`), plus `ImageOverlay` and `StickerOverlay` with animatable position and size.
- `TextStyle` carries `TextStroke` and `TextShadow` — legible copy over busy footage.

**Audio**
- Per-track volume, fades, ducking, `volumeRamp(start:end:during:)` and declaration-ordered `crossfade(_:)`.
- Pitch-preserving speed from 0.25× to 4× via `AudioTimePitchAlgorithm` (`.spectral`, `.timeDomain`, `.varispeed`).

**Timing**
- `Speed` is `.flat(Double)` or `.curved(Animation<Double>)` — compile-time exclusivity, with non-linear playback rates integrated into a piecewise-linear time map that audio follows.

**Captions**
- `Caption` value type and `Video.captions(_:)` bake cues as an `AVMetadataItem` group at export. File parsing for SRT, VTT, iTT, ASS and SSA lives in [`kadr-captions`](https://github.com/SteliyanH/kadr-captions); the core stays a bridge.

**Export**
- `ThumbnailGenerator` reuses one `AVAssetImageGenerator` across many frame requests, with a batch `AsyncThrowingStream` for filmstrips and cooperative `cancel()`.
- `CancellationToken` backed by real synchronisation, not an unchecked claim.

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
    .package(url: "https://github.com/SteliyanH/kadr.git", .upToNextMinor(from: "0.15.0"))
]
```

**Pin to the next minor while kadr is pre-1.0.** SwiftPM's `from:` means
`.upToNextMajor`, and it does not special-case `0.x` — so `from: "0.15.0"`
would resolve as `>=0.15.0, <1.0.0` and accept every 0.x release, including
breaking ones. Minors here do break: v0.15.0 raised the platform floor to
iOS 17. `.upToNextMinor` resolves `>=0.15.0, <0.16.0`, so a breaking minor
becomes a deliberate bump you review. Once v1.0 ships, `from: "1.0.0"` is the
correct and safe form.

Or in Xcode: File > Add Package Dependencies > enter the repository URL.

**Requires:** Xcode 16+ / Swift 6.0+

## Platform Support

| Platform | Minimum Version |
|---|---|
| iOS | 17.0 |
| macOS | 14.0 |
| tvOS | 17.0 |
| visionOS | 1.0 |

> **Platform floor raised in v0.15.0** (was iOS 16 / macOS 13 / tvOS 16). Aligns the ecosystem on the iOS 17 baseline for the `@Observable` migration in `kadr-reels-studio`. Stay on `0.14.x` if you need the iOS 16 floor.

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
