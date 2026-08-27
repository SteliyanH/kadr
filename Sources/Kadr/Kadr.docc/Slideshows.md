# Building a Slideshow

Turning still images into a video, and the two things that make one watchable.

## Overview

A slideshow is the shortest path from nothing to an exported video: no source
footage, no trimming, no format questions. It is also the composition most likely
to look mechanical, because stills do not move and cuts between them are abrupt.

Two modifiers fix that, and they are the reason this article exists rather than a
one-line snippet.

## The minimum

``ImageClip`` takes an image and a duration. Anything in a ``Video`` builder
chains in declaration order.

```swift
let slideshow = Video {
    ImageClip(first, duration: 3.0)
    ImageClip(second, duration: 3.0)
    ImageClip(third, duration: 3.0)
}
.preset(.reelsAndShorts)

try await slideshow.export(to: outputURL)
```

If you have no images to hand, ``SampleMedia`` generates them:

```swift
Video {
    for index in 0..<4 {
        ImageClip(SampleMedia.image(index: index), duration: 2.0)
    }
}
```

## Making the cuts soft

A hard cut between two stills reads as a glitch rather than an edit. Place a
``Transition`` between clips — it is a clip in the builder, not a modifier on one:

```swift
Video {
    ImageClip(first, duration: 3.0)
    Transition.dissolve(duration: 0.5)
    ImageClip(second, duration: 3.0)
}
```

A transition cannot start or end a composition, and two cannot sit adjacent —
both throw ``KadrError/invalidTransition(_:)`` with an explanation rather than
failing at export time.

Note that a transition *overlaps* the clips it joins, so the finished video is
shorter than the sum of the durations. Budget for it when the total length
matters.

## Making the stills move

The other half of a watchable slideshow is motion. A slow push or drift — the Ken
Burns effect — is a ``Transform`` animated across the clip's lifetime:

```swift
let push = Animation<Transform>.keyframes([
    .at(0.0, value: Transform(scale: 1.0)),
    .at(3.0, value: Transform(scale: 1.12)),
])

ImageClip(photo, duration: 3.0)
    .transform(Transform(scale: 1.0), animation: push)
```

Keep the range small. A 12% push over three seconds reads as intent; 50% reads as
a zoom, and on a still image that mostly reveals compression artefacts.

Alternate the direction between slides — push on one, pull on the next — or the
whole sequence acquires a rhythm that draws attention to the technique.

See <doc:KeyframeAnimation> for what else can be driven this way.

## Titles

``TitleSequence`` renders text on a solid background and behaves like any other
clip, so it takes transitions and transforms on the same terms:

```swift
Video {
    TitleSequence("Summer", duration: 2.0)
    Transition.fade(duration: 0.5)
    ImageClip(beach, duration: 3.0)
}
```

## Audio

Background music attaches to the composition rather than to a clip:

```swift
slideshow.audio {
    AudioTrack(url: musicURL)
        .volume(0.6)
        .fadeIn(1.0)
        .fadeOut(1.5)
}
```

A fade out matters more than it sounds: music that stops dead at the last frame
is the most common way an otherwise finished slideshow feels unfinished.

## Topics

### Related

- ``ImageClip``
- ``TitleSequence``
- ``Transition``
- ``SampleMedia``
- <doc:KeyframeAnimation>
