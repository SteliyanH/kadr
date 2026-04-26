# Changelog

All notable changes to Kadr will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
