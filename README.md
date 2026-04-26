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

### v0.2 (current)

- **Transitions**: `.fade` (through black), `.dissolve` (cross-blend), `.slide` (4 directions) — wired through the engine with audio crossfades
- **Speed control**: `VideoClip.speed(_:)` — `0.25...4.0`, pitch-preserving
- **Audio ducking**: `AudioTrack.ducking(_:)` — auto-lowers music while clip audio plays

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
