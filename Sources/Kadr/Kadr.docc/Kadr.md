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

### Start Here

- <doc:GettingStarted>
- <doc:Cookbook>

### Guides

- <doc:Slideshows>
- <doc:MultiTrackComposition>
- <doc:KeyframeAnimation>
- <doc:CustomCompositors>

### Essentials

- <doc:FrameAccuracy>
- <doc:MigrationGuide>
- <doc:KnownPlatformIssues>

### Composing Videos

- ``Video``
- ``VideoBuilder``
- ``AudioBuilder``

### Clip Types

- ``Clip``
- ``VideoClip``
- ``ImageClip``
- ``VideoClipMetadata``
- ``ClipID``
- ``Speed``

### Multi-track Timeline

- ``Track``
- ``VideoClip/at(time:)-(CMTime)``
- ``VideoClip/at(time:)-(TimeInterval)``
- ``MultiInputCompositor``
- ``Video/compositor(_:)-(MultiInputCompositor)``
- ``Video/compositor(_:)-(([CIImage],CompositorContext)->CIImage)``

### Audio

- ``AudioTrack``
- ``AudioTimePitchAlgorithm``

### Captions

- ``Caption``

### Transitions

- ``Transition``
- ``SlideDirection``

### Layout

- ``Position``
- ``Size``
- ``Anchor``
- ``Transform``
- ``LayerID``

### Overlays

- ``Overlay``
- ``ImageOverlay``
- ``TextOverlay``
- ``TextStyle``
- ``TextStroke``
- ``TextShadow``
- ``StickerOverlay``

### Text Animation

- ``TextAnimation``
- ``FadeIn``
- ``SlideIn``
- ``ScaleUp``

### Keyframe Animation

- ``Animation``
- ``Animatable``
- ``TimingFunction``

### Filters

- ``Filter``
- ``FilterID``
- ``FilterKind``
- ``LUT``
- ``ChromaKey``
- ``ColorComponents``

### Cropping

- ``Video/crop(at:size:anchor:)``
- ``VideoClip/crop(at:size:anchor:)``
- ``VideoClip/mask(_:)-(CIImage)``
- ``VideoClip/mask(_:)-(PlatformImage)``
- ``CropRegion``

### Custom Processing

- ``Compositor``
- ``CompositorContext``
- ``VideoClip/compositor(_:)-(Compositor)``
- ``VideoClip/compositor(_:)-((CIImage,CompositorContext)->CIImage)``

### Preview & Introspection

- ``Video/makePlayerItem()``
- ``Video/thumbnail(at:)-(CMTime)``
- ``Video/thumbnail(at:)-(TimeInterval)``
- ``Video/thumbnailGenerator()``
- ``ThumbnailGenerator``
- ``SampleMedia``
- ``AudioWaveform``
- ``AudioWaveform/resampled(to:)``
- ``AudioWaveformLoader``
- ``Layout``
- ``Layout/resolveFrame(position:size:anchor:in:)``

### Sugar

- ``BackgroundMusic``
- ``TitleSequence``
- ``Timecode``

### Export

- ``Exporter``
- ``ExportProgress``
- ``Preset``
- ``ExportQuality``
- ``Codec``

### Platform Support

- ``PlatformImage``
- ``PlatformColor``

### Errors

- ``KadrError``
