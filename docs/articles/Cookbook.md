# Cookbook

Short answers to the common "how do I…" questions about video on Apple
platforms.

## Overview

Each recipe is a complete composition. Export any of them with
`try await video.export(to: outputURL)`, or preview one with
``Video/makePlayerItem()``. <doc:GettingStarted> covers both.

## Combining and cutting

### How do I merge several videos into one?

List the clips. They play in order, and each is scaled to fill the output frame
and centred, so their sizes need not match:

```swift
let video = Video {
    VideoClip(url: a)
    VideoClip(url: b)
    VideoClip(url: clipURL)
}
.preset(.cinema)       // 1920×1080
```

Set the preset to the shape you want. Without one the output is vertical,
1080×1920, and landscape clips lose their sides to fill it.

### How do I trim a video?

```swift
let video = Video {
    VideoClip(url: clipURL).trimmed(to: 2...8)    // keep seconds 2 to 8
}
```

For frame-exact cuts, pass a `CMTimeRange` instead. See <doc:FrameAccuracy>.

### How do I crossfade between two clips?

Put a ``Transition`` between them:

```swift
let video = Video {
    VideoClip(url: a)
    Transition.dissolve(duration: 0.75)
    VideoClip(url: b)
}
```

A dissolve overlaps the two clips, so the video is shorter than the clips laid
end to end by the dissolve's length. A transition must be shorter than both of
the clips it joins, and cannot come first or last.

### How do I make a slideshow from photos?

```swift
let video = Video {
    ImageClip(first, duration: 3)
    Transition.dissolve(duration: 0.5)
    ImageClip(second, duration: 3)
    Transition.dissolve(duration: 0.5)
    ImageClip(third, duration: 3)
}
.audio(url: musicURL)
```

<doc:Slideshows> adds slow zooms, title cards and fitting the music.

## Sound

### How do I add background music?

```swift
let video = Video {
    VideoClip(url: clipURL)
}
.audio {
    AudioTrack(url: musicURL)
        .volume(0.6)
        .fadeIn(1)
        .fadeOut(2)
        .ducking(0.25)     // quieter while the clip's own sound plays
}
```

### How do I mute a clip, or replace its sound?

```swift
let video = Video {
    VideoClip(url: a).muted()                    // silent
    VideoClip(url: b).withAudio(musicURL)        // this file's sound instead
}
```

`withAudio` is cut to the clip's length and does not loop.

## Speed

### How do I make slow motion or a time-lapse?

```swift
let video = Video {
    VideoClip(url: a).speed(0.5)      // half speed
    VideoClip(url: b).speed(4)        // four times as fast
}
```

The rate must be between 0.25 and 4. For a speed that changes during the clip,
pass a curve: `.speed(.curved(animation))`.

### How do I play a clip backwards?

```swift
let video = Video {
    VideoClip(url: clipURL).trimmed(to: 0...3).reversed()
}
```

kadr writes the reversed frames to a temporary file first, so keep reversed
clips short.

## Text and images on top

### How do I put text on a video?

```swift
let video = Video {
    VideoClip(url: clipURL)
}
.overlay(
    TextOverlay("Day one", style: TextStyle(fontSize: 96, weight: .bold, shadow: TextShadow()))
        .position(.normalized(x: 0.5, y: 0.85))
        .visible(during: 0.5...4)
        .animation(.fadeIn(duration: 0.4))
)
```

`fontSize` is in pixels of the exported video, so a size looks the same at
every preview size.

### How do I add a logo or watermark?

```swift
let video = Video {
    VideoClip(url: clipURL)
}
.overlay(
    ImageOverlay(logo)
        .size(.aspectFit(within: .normalized(width: 0.2, height: 0.1),
                         sourceAspect: logo.size.width / logo.size.height))
        .position(.normalized(x: 0.96, y: 0.96))
        .anchor(.bottomRight)
        .opacity(0.8)
)
```

`.anchor(.bottomRight)` puts the logo's corner, not its centre, at the
position, so it sits just inside the frame's corner.

### How do I show one video in a corner of another?

Give the second clip a start time with `.at(time:)`. It then plays on a layer
above the first instead of after it:

```swift
let video = Video {
    VideoClip(url: main)
    VideoClip(url: inset)
        .at(time: 1)
        .transform(Transform(center: .normalized(x: 0.96, y: 0.04), scale: 0.3, anchor: .topRight))
}
```

<doc:MultiTrackComposition> covers layers and tracks.

### How do I remove a green screen?

```swift
let video = Video {
    ImageClip(photo, duration: 5)                   // what shows through
    VideoClip(url: clipURL)                         // filmed on green
        .filter(.chromaKey(color: .green, threshold: 0.35))
        .at(time: 0)
}
```

## Look

### How do I apply a filter or a colour grade?

```swift
let grade = try LUT(url: lutURL)                              // a .cube file

let video = Video {
    VideoClip(url: a).filter(.saturation(0))                  // black and white
    VideoClip(url: b).filter(.contrast(1.1), .vignette())
    VideoClip(url: clipURL).filter(.lut(grade))
}
```

### How do I crop to a square?

Pick the shape with the output preset. Each clip is scaled to fill it and
centred:

```swift
let video = Video {
    VideoClip(url: clipURL)
}
.preset(.square)
```

For a vertical video, use `.reelsAndShorts`, which is 1080×1920. To choose
which part of the frame to keep, use ``Video/crop(at:size:anchor:)``.

## Export

### How do I keep the file under a size limit?

```swift
let video = Video {
    VideoClip(url: clipURL)
}
.quality(.fileSize(bytes: 8_000_000))     // aim for 8 MB
```

kadr picks the bitrate from the video's duration. The result lands close to the
target, but not exactly on it.

### How do I get a thumbnail?

```swift
let cover = try await Video {
    VideoClip(url: clipURL)
}
.thumbnail(at: 1.5)                       // the frame at 1.5 seconds
```

### How do I add subtitles?

```swift
let video = Video {
    VideoClip(url: clipURL)
}
.captions([
    Caption(text: "Hello", timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 2, timescale: 1))),
])
```

These are a subtitle track that players can turn on and off. To read `.srt`
or `.vtt` files, or to draw captions into the picture, use
[kadr-captions](https://github.com/SteliyanH/kadr-captions).
