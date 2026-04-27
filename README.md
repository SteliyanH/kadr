# Kadr

[![CI](https://github.com/SteliyanH/kadr/actions/workflows/ci.yml/badge.svg)](https://github.com/SteliyanH/kadr/actions/workflows/ci.yml)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2016+%20|%20macOS%2013+%20|%20tvOS%2016+%20|%20visionOS%201+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

**SwiftUI for video. Compose, transform, export — in Swift you actually want to write.**

A modern, declarative Swift library for video composition on Apple platforms. Build videos using a result-builder DSL with async/await throughout.

## Quick Start

```swift
import Kadr

let url = try await Video {
    ImageClip(heroImage, duration: 5.0)
}
.audio(url: musicURL)
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

### v0.5.0 (current — `0.5.0`)

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
- **Companion package**: [`kadr-ui`](https://github.com/SteliyanH/kadr-ui) is a separate SwiftUI components package (`VideoPreview`, `TimelineView`, `ThumbnailStrip`, gesture handlers) consuming these primitives.

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
    .package(url: "https://github.com/SteliyanH/kadr.git", from: "0.1.0")
]
```

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

- **DSL layer** — `Video`, `ImageClip`, `VideoClip`, `AudioTrack`, `Preset`, `Exporter` (public)
- **Engine layer** — `ImageEncoder`, `CompositionBuilder`, `ExportEngine` (internal, uses AVFoundation)

The DSL is the stable public API. The engine is the implementation detail that can be refactored without breaking semver.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.

Apache 2.0 was chosen over MIT for its explicit patent grant, which is relevant for video processing code that touches codec patents (H.264, HEVC).
