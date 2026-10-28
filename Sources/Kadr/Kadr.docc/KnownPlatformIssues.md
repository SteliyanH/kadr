# Known Platform Issues

Apple platform bugs that affect Kadr compositions, what they look like, and how to work
around them.

## Overview

These are bugs in AVFoundation or Core Animation, not in Kadr. Each one reproduces with
plain AVFoundation code. Kadr works around the ones it can; the ones listed here it
currently can't, so they're documented with a workaround instead.

Both issues below affect the **iOS Simulator only**. Real devices and macOS are not
affected.

## Overlay exports fail on the iOS Simulator

**Affects:** exports with any overlay (``TextOverlay``, ``ImageOverlay``,
``StickerOverlay``, ``Video/watermark(_:position:size:opacity:)``) on the iOS 26.5 and 27.0
Simulators. Previews are not affected: they don't use the export overlay path.

**What Kadr does:** on the iOS Simulator, ``Video/export(to:)`` with overlays throws
``KadrError/exportFailed(underlying:)``, with a message pointing here. It refuses before
rendering anything, because the underlying failure kills the app and can't be caught.

**The underlying bug:** without that check, the app crashes during export with
`EXC_BREAKPOINT` and the crash report signature *API Misuse*. The crashing thread is on
the `com.apple.coremedia.basicvideocompositor.output` queue:

```
_xpc_api_misuse
_xpc_shmem_create_with_prot
_ioSurfaceClientCreate
IOSurfaceCreate
CA::Render::Image::retain_iosurface() const
CA::OGL::GLESContext::retain_image(...)
...
-[CARenderer render]
FigCoreAnimationRendererCopyPixelBufferAtTime
```

This reproduces with plain AVFoundation, in an app as well as in tests.

**Cause:** overlays are drawn by `AVVideoCompositionCoreAnimationTool`, which renders
each video frame through Core Animation. On the Simulator, AVFoundation's video frames
are ordinary `malloc` memory rather than IOSurfaces. Core Animation tries to wrap that
memory in an IOSurface, and libxpc rejects it with *"Attempt to pass a malloc(3)ed region
to xpc_shmem_create()"*, which is a deliberate trap rather than an error. The same export
completes when the frames are IOSurface-backed.

**Workaround:** export compositions with overlays on a device or on macOS. If your app
must export on the Simulator during development, leave the overlays out of
Simulator builds:

```swift
var video = Video { ... }
#if !targetEnvironment(simulator)
video = video.overlay(TextOverlay("Title"))
#endif
```

## Transition previews stall on the iOS Simulator

**Affects:** preview playback (``Video/makePlayerItem()``) of a composition with a
transition, on the iOS 26 Simulator, when the source clips' resolution exactly equals the
preset's render size. Export is not affected.
([#203](https://github.com/SteliyanH/kadr/issues/203))

**Symptom:** playback stops at the first transition. The player item posts
`AVPlayerItemFailedToPlayToEndTime` with error `-11800`, underlying `-19230`
("CoreAnimation image queue does not support this pixel format").

**Cause:** when the decoded frame already matches the render size, the Simulator's
display pipeline passes it straight to Core Animation's image queue, which supports
fewer pixel formats on the Simulator than on a device.

**Workaround:** for Simulator builds only, nudge the render size by half a point after
building the player item. `AVPlayerItem.videoComposition` is copied on set, so mutate a
copy and assign it back:

```swift
let item = try await video.makePlayerItem()
#if targetEnvironment(simulator)
if let composition = item.videoComposition?.mutableCopy() as? AVMutableVideoComposition {
    composition.renderSize.width += 0.5
    item.videoComposition = composition
}
#endif
```
