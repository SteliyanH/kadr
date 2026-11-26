# Getting Started

Add kadr to an app, build a video, preview it, and export it.

## Overview

A kadr video is a value. You describe it with ``Video`` and a result builder,
the way you describe a SwiftUI view, and nothing is read or rendered until you
preview or export it. This article goes from an empty project to an exported
file in five steps.

## Add the package

In Xcode, choose **File › Add Package Dependencies…** and enter
`https://github.com/SteliyanH/kadr.git`. In a `Package.swift`:

<!-- readme-snippets: skip -->
```swift
dependencies: [
    .package(url: "https://github.com/SteliyanH/kadr.git", from: "1.3.0")
]
```

kadr needs Xcode 26 (Swift 6.2) and runs on iOS 17, macOS 14, tvOS 17 and
visionOS 1 or later.

## Make a first video

This needs no media files: ``SampleMedia`` draws its own frames.

```swift
let output = FileManager.default.temporaryDirectory.appendingPathComponent("first.mp4")

let url = try await Video {
    ImageClip(SampleMedia.image(index: 0), duration: 2)
    Transition.dissolve(duration: 0.5)
    ImageClip(SampleMedia.image(index: 1), duration: 2)
}
.preset(.reelsAndShorts)          // 1080×1920, 30 fps
.export(to: output)
```

``Video/export(to:)`` is `async` and throws, so call it from a SwiftUI `.task`,
a `Task`, or an `async` test. It returns the URL of the finished file.

## Use your own media

``VideoClip`` takes a file URL and ``ImageClip`` takes an image and a duration.
Clips play one after another, and a ``Transition`` between two clips blends
them:

```swift
let video = Video {
    VideoClip(url: clipURL).trimmed(to: 2...8)    // seconds 2 to 8 of the file
    Transition.dissolve(duration: 0.5)
    ImageClip(photo, duration: 3)
}
.audio(url: musicURL)
.preset(.cinema)
```

Reading from the Photos library or a picker? The
[kadr-photos](https://github.com/SteliyanH/kadr-photos) package turns a
`PHAsset` or a picker result into these clips.

## Preview before you export

``Video/makePlayerItem()`` builds an `AVPlayerItem` that plays the
composition live, without writing a file:

```swift
struct PreviewView: View {
    let video: Video
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .task {
                if let item = try? await video.makePlayerItem() {
                    player = AVPlayer(playerItem: item)
                }
            }
    }
}
```

For a timeline, trim handles and overlays you can drag, use
[kadr-ui](https://github.com/SteliyanH/kadr-ui).

## Show progress, and let people cancel

``Video/export(to:)`` waits for the whole file. For a progress bar, ask for an
``Exporter`` and read its updates:

```swift
let exporter = video.exporter(to: outputURL)

do {
    for try await progress in exporter.run() {
        print("\(Int(progress.fractionCompleted * 100))%")
    }
} catch KadrError.cancelled {
    // exporter.cancel() was called, from a Cancel button for example.
}
```

## Handle errors

Every error kadr throws is a ``KadrError``. Its `localizedDescription` is
written for the person using your app, and `recoverySuggestion` says what to do
about it:

```swift
do {
    let file = try await video.export(to: outputURL)
    print(file)
} catch let error as KadrError {
    print(error.localizedDescription, error.recoverySuggestion ?? "")
}
```

Exports with overlays fail on the iOS Simulator. They work on devices and on
macOS. See <doc:KnownPlatformIssues>.

## Next steps

- <doc:Cookbook> answers the common "how do I…" questions in a few lines each.
- <doc:Slideshows>, <doc:MultiTrackComposition> and <doc:KeyframeAnimation>
  go deeper into one topic each.
