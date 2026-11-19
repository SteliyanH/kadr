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
let blurred = VideoClip(url: url).compositor { image, context in
    image.applyingFilter("CIGaussianBlur", parameters: [
        kCIInputRadiusKey: 8.0
    ])
}
```

``CompositorContext`` carries the frame's composition ``CompositorContext/time``
and the engine's ``CompositorContext/renderSize`` in pixels, post-crop and
post-preset. Time is what makes an effect animate:

```swift
let focusPull = VideoClip(url: url).compositor { image, context in
    let radius = min(20.0, context.time.seconds * 4.0)
    return image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
}
```

## The protocol form

When the effect needs setup, conform a type instead. Anything expensive belongs
in the initialiser, not in `process`. Here the expensive part is a 32×32×32
colour table, built once and then applied to every frame:

```swift
struct WarmGrade: Compositor {
    private let cube: Data          // built once, read by every frame

    init(warmth: Float) {
        let size = 32, top = Float(size - 1)
        var table: [Float] = []
        table.reserveCapacity(size * size * size * 4)
        for blue in 0..<size {
            for green in 0..<size {
                for red in 0..<size {
                    table += [
                        min(1, Float(red) / top + warmth),
                        Float(green) / top,
                        max(0, Float(blue) / top - warmth),
                        1,
                    ]
                }
            }
        }
        cube = table.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func process(image: CIImage, context: CompositorContext) -> CIImage {
        image.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": 32,
            "inputCubeData": cube,
        ])
    }
}

let graded = VideoClip(url: url).compositor(WarmGrade(warmth: 0.08))
```

Keep what you store immutable. A `CIFilter` is a mutable object, so a stored
one that `process` configures per frame is shared state, and Swift 6 rejects it
in a `Sendable` type. Store the inputs (numbers, `Data`, a `CIImage`) and call
`applyingFilter` in `process`; creating the filter there is cheap.

## The three constraints

**`process` is synchronous.** The engine wraps the call in
`applyingCIFiltersWithHandler`, which expects a non-`async` handler. There is no
place to await, and that is deliberate: per-frame `async` multiplies with frame
rate and duration, so a 5-second clip at 30 fps would suspend 150 times.

**It must be `Sendable`.** The engine crosses actor boundaries while running
compositors. Capture value types; do not reach for a shared mutable cache.

**Cost multiplies by frame count.** A 10 ms operation is invisible in isolation,
yet adds 1.5 seconds to a 5-second export at 30 fps and 18 seconds to a
one-minute one. Build tables and images once at construction, and prefer
`applyingFilter` chains over building images by hand.

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

## See Also

- ``Compositor``
- ``CompositorContext``
- ``MultiInputCompositor``
- ``Filter``
- <doc:MultiTrackComposition>
