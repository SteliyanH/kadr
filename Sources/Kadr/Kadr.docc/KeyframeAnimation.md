# Keyframe Animation

Driving a property over a clip's lifetime.

## Overview

Most of Kadr's per-clip properties have an animated form: give the modifier a
base value and an ``Animation``, and the engine samples it per frame.

The shape is the same everywhere — build the keyframes, hand them to the
modifier — so learning it once covers transforms, opacity and filter intensity.

## Building an animation

``Animation/keyframes(_:timing:)`` takes values at times. Keyframes are sorted on
construction, so out-of-order input is safe:

```swift
let fade = Animation<Double>.keyframes([
    .at(0.0, value: 0.0),
    .at(1.0, value: 1.0),
    .at(4.0, value: 1.0),
    .at(5.0, value: 0.0),
], timing: .linear)
```

Times are **clip-relative**, not composition-relative. A keyframe at `0.0` is the
start of the clip it is attached to, wherever that clip sits in the timeline —
which is what lets the same animation be reused across clips.

## Applying it

```swift
VideoClip(url: url).opacity(1.0, animation: fade)
```

The first argument is the base: the value used outside the animation's range.
Inside the range the animation wins. A base of `1.0` with the fade above means
the clip is fully opaque before the first keyframe and after the last, which is
usually what you want for a fade that only covers part of a longer clip.

## Animating a transform

``Transform`` animates as a whole, so position, scale and rotation move together:

```swift
let drift = Animation<Transform>.keyframes([
    .at(0.0, value: Transform(scale: 1.0)),
    .at(4.0, value: Transform(scale: 1.15)),
])

ImageClip(photo, duration: 4.0)
    .transform(Transform(scale: 1.0), animation: drift)
```

## Animating a filter

Filters animate their primary scalar — brightness, contrast, saturation,
exposure, sepia intensity. Filters without one (`.mono`, `.lut`, `.chromaKey`)
ignore the animation rather than failing:

```swift
let ramp = Animation<Double>.keyframes([
    .at(0.0, value: 0.0),
    .at(2.0, value: 0.6),
])

VideoClip(url: url).filter(.brightness(0.0), animation: ramp)
```

### Prefer the keyed surface

When a clip carries several filters and you need to change one later, address it
by ``FilterID`` rather than by index:

```swift
let clip = VideoClip(url: url).filter(.brightness(0.2))
let id = clip.filterIDs[0]

let animated = clip.filterAnimation(for: id, ramp)
let brighter = animated.setFilter(for: id, .brightness(0.5))   // keeps the animation
```

Index-based access drifts as soon as a filter is added or removed. The keyed
surface exists because that drift is silent — and until v0.18 appending a filter
regenerated every id, orphaning exactly these bindings.

## Timing

``TimingFunction`` shapes interpolation between keyframes. `.linear` is the
default and is the right choice more often than it looks: eased motion on a
2-second clip is largely indistinguishable from linear, and easing is most
visible on long, slow moves.

## Topics

### Related

- ``Animation``
- ``TimingFunction``
- ``Transform``
- ``FilterID``
- <doc:Slideshows>
