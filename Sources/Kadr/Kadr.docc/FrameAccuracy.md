# Frame Accuracy

How Kadr represents time, and when to reach for `CMTime` over `TimeInterval`.

## Overview

Every time-related value in Kadr's API has two forms:

- **`CMTime`** — frame-accurate. Stores time as a rational `value / timescale` so values like
  *1 frame at 30 fps* are exact (`CMTime(value: 1, timescale: 30)`).
- **`TimeInterval`** — ergonomic. A plain `Double` measured in seconds. Convenient for
  literal call sites like `0.5` or `0...10`, but inherently lossy for sub-second precision
  (`1.0 / 30.0 = 0.03333…`, never exactly 1/30).

`CMTime` is the type stored internally and the type used by AVFoundation throughout. The
`TimeInterval` overloads exist as static factory methods that bridge to `CMTime` at
construction. Engine math operates entirely in `CMTime`.

## When to use which

Use `CMTime` when:

- You're targeting a specific frame rate and want trims, fades, or transitions aligned to
  frame boundaries.
- You're seeking to or extracting thumbnails at exact frame positions.
- You're composing values you've read from AVFoundation (asset durations, track frame rates).

Use `TimeInterval` for everything else — readable literals, prototyping, anywhere a
fractional second of slop is acceptable.

```swift
// Frame-accurate (CMTime):
clip.trimmed(to: CMTimeRange(
    start:    CMTime(value: 30, timescale: 30),    // exactly second 1
    duration: CMTime(value: 90, timescale: 30)     // exactly 3 seconds
))
Transition.fade(duration: CMTime(value: 1, timescale: 30))   // exactly 1 frame at 30fps

// Ergonomic (TimeInterval):
clip.trimmed(to: 0...3)                                       // close enough
Transition.fade(duration: 0.5)                                // close enough
```

## Wall-clock time vs media-timeline time

Not every duration is a media-timeline value. Kadr distinguishes:

- **Media-timeline time** — positions and durations within the composition. Frame-accurate.
  Always `CMTime`. (Examples: ``Transition`` durations, ``VideoClip/trimmed(to:)-(CMTimeRange)``,
  ``Video/duration``, ``Clip/duration``.)
- **Wall-clock time** — elapsed seconds in the real world. Frame accuracy doesn't apply.
  Always `TimeInterval`. (Example: ``ExportProgress/estimatedTimeRemaining`` — how long the
  user must wait for the export to finish.)

If you're holding a value, ask yourself: *does it move when the user pauses playback?*
If yes, it's media time → `CMTime`. If no, it's wall-clock time → `TimeInterval`.

## Engine guarantees

The composition engine performs all arithmetic in `CMTime`. Specifically:

- Fade halving uses `CMTimeMultiplyByRatio(d, multiplier: 1, divisor: 2)` — exact rational
  halving with no float drift.
- Validation comparisons use `CMTimeCompare` directly, not seconds-based `Double` comparisons.
- Trim ranges are stored and consumed as `CMTimeRange` — no round-tripping through `Double`.
- The single unavoidable `Double` touch is in ``VideoClip/speed(_:)`` (since the rate is a
  `Double` ratio); it uses `CMTimeMultiplyByFloat64` and is otherwise contained.

## Topics

### Time-related symbols

- ``Transition``
- ``VideoClip/trimmed(to:)-(CMTimeRange)``
- ``VideoClip/thumbnail(at:)-(CMTime)``
- ``ImageClip/init(_:duration:)-(_,CMTime)``
- ``AudioTrack/fadeIn(_:)-(CMTime)``
- ``AudioTrack/fadeOut(_:)-(CMTime)``
