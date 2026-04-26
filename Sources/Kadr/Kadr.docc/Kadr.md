# ``Kadr``

A modern, declarative Swift library for video composition on Apple platforms.

## Overview

Kadr lets you compose videos using a SwiftUI-style result-builder DSL with async/await throughout. Build slideshows from images, merge video clips, trim, reverse, replace audio, and export to social media formats — all in a few lines of Swift.

```swift
import Kadr

let url = try await Video {
    ImageClip(heroImage, duration: 5.0)
}
.audio(url: musicURL)
.preset(.reelsAndShorts)
.export(to: outputURL)
```

## Topics

### Essentials

- <doc:FrameAccuracy>

### Composing Videos

- ``Video``
- ``VideoBuilder``
- ``AudioBuilder``

### Clip Types

- ``Clip``
- ``VideoClip``
- ``ImageClip``
- ``VideoClipMetadata``

### Audio

- ``AudioTrack``

### Transitions

- ``Transition``
- ``SlideDirection``

### Layout (v0.3+)

- ``Position``
- ``Size``
- ``Anchor``
- ``LayerID``

### Overlays (v0.3+)

- ``Overlay``
- ``ImageOverlay``
- ``TextOverlay``
- ``TextStyle``
- ``StickerOverlay``

### Filters (v0.3+)

- ``Filter``

### Cropping (v0.3+)

- ``Video/crop(at:size:anchor:)``

### Export

- ``Exporter``
- ``ExportProgress``
- ``Preset``
- ``Codec``

### Platform Support

- ``PlatformImage``
- ``PlatformColor``

### Errors

- ``KadrError``
