# Kadr Roadmap

This document outlines the planned feature releases for Kadr. Versions and timelines are subject to change based on community feedback.

## v0.1.0 — Stable Release

Post-alpha stabilization based on community feedback.

- Bug fixes reported during alpha
- Documentation improvements
- Performance profiling of ImageEncoder and CompositionBuilder
- Edge case handling (very long videos, large images, corrupted input files)

## v0.2.0 — Transitions & Speed ✓ shipped

Implemented the transition engine and speed control. See [CHANGELOG.md](CHANGELOG.md#020---2026-04-26).

- ✓ Transition engine: `.fade` (fade-through-black), `.dissolve` (cross-blend), `.slide` (4 directions)
- ✓ Speed control: `.speed(_:)` modifier on `VideoClip` (0.25x to 4x), pitch-preserving
- ✓ Audio ducking: `.ducking(_:)` on `AudioTrack` — auto-lowers music when clip audio plays

## v0.3.0 — Overlays & Filters

Visual composition — layers on top of video.

- **Text overlays:** `.overlay(text:position:style:)` via `CATextLayer`
- **Image/sticker overlays:** `.overlay(image:position:size:)` via `CALayer`
- **Watermarking:** `.watermark(image:position:opacity:)` built on overlay infrastructure
- **Filters:** `.filter(_:)` with built-in presets (brightness, contrast, saturation, etc.)

## v0.4.0 — KadrUI

Separate SwiftUI package for video editing components.

- `VideoPreview` — preview a `Video` composition before export
- `TimelineView` — visual timeline showing clips, transitions, audio
- `ThumbnailStrip` — scrubbing strip generated from video thumbnails
- Ships as a separate `kadr-ui` package depending on `Kadr`

## v0.5.0 — Advanced Composition

Multi-track and precision composition features.

- **Timeline API:** Multi-track composition with explicit time placement
- **Chroma key:** `.chromaKey(color:threshold:)`
- **Color grading / LUTs:** `.lut(url:)` for loading `.cube` LUT files
- **Custom compositors:** Public protocol for user-defined per-frame processing

## v1.0.0 — Production Ready

Semver stability guarantee.

- API stability commitment — no breaking changes without major version bump
- Comprehensive documentation with tutorials
- Performance benchmarks
- CocoaPods support (if community demand warrants it)

---

## Kadr Pro

Premium features under a commercial license in the separate `kadr-pro` repository.

- HDR10 / Dolby Vision / ProRes export
- AI features: auto-captions, smart crop, background removal
- Custom Metal shader effects
- Priority support

---

## Contributing

Want to help build the next version? Check [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. If a feature you want isn't on this roadmap, open an issue to discuss it.
