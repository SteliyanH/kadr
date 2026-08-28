# Multi-Track Composition

Putting clips beside each other in time rather than after each other.

## Overview

By default, clips in a ``Video`` builder chain: each starts where the previous one
ended. That is the right model for a cut sequence and the wrong one for anything
layered — a picture-in-picture, a watermark clip, a reaction inset.

Two constructs break the chain, and which one to reach for depends on whether you
are placing *one* clip or *several*.

## One clip, placed by time

``Clip/at(time:)`` pins a clip to an absolute composition time. It leaves the
chain — the clips around it behave as though it were not there:

```swift
Video {
    VideoClip(url: main).trimmed(to: 0...10)     // the spine
    VideoClip(url: inset).trimmed(to: 0...3)
        .at(time: 2.0)                            // floats above it
        .transform(Transform(center: .topRight, scale: 0.3, anchor: .topRight))
}
```

Later clips draw above earlier ones, so declaration order is layer order. Without
a ``Transform`` the inset covers the spine completely, which is almost never what
was wanted — placement and scale usually travel together.

## Several clips, as a group

``Track`` is a parallel sub-timeline. Clips inside it chain among themselves,
while the track as a whole sits at one point in the parent:

```swift
Video {
    VideoClip(url: main).trimmed(to: 0...20)

    Track(at: 2.0) {
        VideoClip(url: a).trimmed(to: 0...3)
        VideoClip(url: b).trimmed(to: 0...3)     // starts when `a` ends
    }
    .opacity(0.8)
}
```

Reach for `Track` when the layered content has its own internal sequence. Reach
for `at(time:)` when it is a single element. Using `at(time:)` on each clip of a
sequence works, but it makes every duration a hand-computed offset — and the
arithmetic breaks the moment one clip's length changes.

## What multi-track costs

A composition with any clip carrying an explicit start time, a `Track`, or a
per-clip transform routes through the multi-track builder, which produces a
video composition with per-clip layer instructions.

That path is measurably more expensive than the simple one — roughly three times
the export time for a four-clip composition in this project's own benchmarks. It
is not a reason to avoid layering, but it is a reason not to reach for
`at(time:)` when a plain chain would do.

## Naming tracks

``Track/init(name:_:)`` takes an optional label. It does not affect rendering; it
exists so a consuming editor can show something meaningful in a timeline UI
instead of *Track 2*.

## Topics

### Related

- ``Track``
- ``Transform``
- ``Clip/startTime``
- <doc:CustomCompositors>
