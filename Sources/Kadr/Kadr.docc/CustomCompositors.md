# Custom Compositors

Running your own per-frame code, and the three constraints that shape it.

## Overview

``Compositor`` is the escape hatch. Filters cover the common adjustments; a
compositor runs arbitrary Core Image work on every frame of a clip, which is what
you need for effects the filter set does not name.

It is also the easiest place in this API to write something that works and is
unusably slow, so the constraints are worth understanding before the syntax.

## The closure form

For anything stateless, pass a closure:

```swift
VideoClip(url: url).compositor { image, context in
    image.applyingFilter("CIGaussianBlur", parameters: [
        kCIInputRadiusKey: 8.0
    ])
}
```

``CompositorContext`` carries the frame's composition ``CompositorContext/time``
and the engine's ``CompositorContext/renderSize`` in pixels, post-crop and
post-preset. Time is what makes an effect animate:

```swift
VideoClip(url: url).compositor { image, context in
    let radius = min(20.0, context.time.seconds * 4.0)
    return image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
}
```

## The protocol form

When the effect needs setup, conform a type instead. Anything expensive belongs
in the initialiser, not in `process`:

```swift
struct Vignette: Compositor {
    let filter: CIFilter          // built once

    init(intensity: Double) {
        filter = CIFilter(name: "CIVignette")!
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
    }

    func process(image: CIImage, context: CompositorContext) -> CIImage {
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }
}

VideoClip(url: url).compositor(Vignette(intensity: 1.4))
```

## The three constraints

**`process` is synchronous.** The engine wraps the call in
`applyingCIFiltersWithHandler`, which expects a non-`async` handler. There is no
place to await, and that is deliberate: per-frame `async` multiplies with frame
rate and duration, so a 5-second clip at 30 fps would suspend 150 times.

**It must be `Sendable`.** The engine crosses actor boundaries while running
compositors. Capture value types; do not reach for a shared mutable cache.

**Cost multiplies by frame count.** A 10 ms operation is invisible in isolation
and adds 45 seconds to a 5-second export at 30 fps. Preload at construction,
reuse `CIFilter` instances, and prefer `applyingFilter` chains over building
images by hand.

## Order

Filters run first, then compositors, in declaration order. Both happen in the
same `applyingCIFiltersWithHandler` pass, so adding a compositor to a clip that
already has filters costs no extra encode.

Reversal, if present, happens before either — so a compositor sees frames in
their final playback order, not the source's.

## Multi-input work

``Compositor`` is single-input: one image in, one image out. Blending two
sources — a custom transition, a chroma composite over a second clip — needs
``MultiInputCompositor``, which is a separate protocol on the lower-level
`AVVideoCompositing` path and is applied to the composition rather than to a
clip.

## Topics

### Related

- ``Compositor``
- ``CompositorContext``
- ``MultiInputCompositor``
- ``Filter``
- <doc:MultiTrackComposition>
