# Migrating to 1.0

What changed across the `0.x` line, and which changes your compiler will not
catch.

## Overview

**There has been no breaking change since v0.14.0.** Releases since have added
API — per-clip volume in 0.18, waveform extraction moving into core in 0.18/0.19,
export quality and sample media in 0.20 — but nothing has been removed or had its
meaning changed. If you are on 0.14 or later, upgrading to 1.0 requires no source
changes at all, only a version-range edit.

If you are on an earlier version, this guide lists every breaking change in
order. Most are one-line mechanical edits that fail to compile until fixed.

**The ones worth your attention are at the end.** A change that stops your code
compiling announces itself. A change that alters what your code *does* while
still compiling does not, and there are three of those.

## First: fix your version range

This applies to every consumer regardless of version, and it is the change most
likely to bite silently.

```swift
// Wrong, and probably what you have
.package(url: "...kadr.git", from: "0.14.0")

// Right, until 1.0
.package(url: "...kadr.git", .upToNextMinor(from: "0.21.0"))
```

`from:` means `.upToNextMajor`, and **SwiftPM does not special-case `0.x`**. So
`from: "0.14.0"` accepts every later 0.x release — including the ones on this
page that removed API. A pre-1.0 dependency pinned with `from:` will eventually
break on an update you did not ask for.

At 1.0 this inverts: `from: "1.0.0"` becomes correct, because the major version
then means what semver says it means.

## v0.11.0 — `speed` became an enum

`VideoClip.speed` returned `Double`; it now returns ``Speed``, which makes flat
and curved speed mutually exclusive at the type level rather than by
documentation.

```swift
// Before
let rate = clip.speed            // Double

// After
switch clip.speed {
case .flat(let rate): ...
case .curved(let animation): ...
}
```

## v0.14.0 — three removals

All three were deprecated in v0.11 and are mechanical:

| Removed | Replacement |
|---|---|
| `VideoClip.speed(_ rate: Double)` | `speed(.flat(rate))` |
| `VideoClip.speed(curve: Animation<Double>)` | `speed(.curved(animation))` |
| `VideoClip.filterAnimation(at: Int, _:)` | ``VideoClip/filterAnimation(for:_:)`` |

The last one is not just a rename. Index-based access drifts the moment a filter
is added or removed; ``FilterID`` is stable across reordering, which is why the
index form was withdrawn rather than kept as a convenience.

`AudioTrack.speed(_:algorithm:)` is a different API and was never deprecated.

## v0.15.0 — platform floor

iOS 17 / macOS 14 / tvOS 17 / visionOS 1, up from iOS 16 / macOS 13 / tvOS 16.

No source change is required if you already target iOS 17. If you need the iOS
16 floor, stay on the `0.14.x` line — it is the last release before the lift.

## The three that compile fine and behave differently

These are the reason this guide exists. Nothing here fails to build.

### v0.16.0 — error text changed

``KadrError`` gained `LocalizedError`, so `error.localizedDescription` changed
observably — from `"The operation couldn't be completed. (Kadr.KadrError error
6.)"` to a sentence written for the person reading it.

**If you match on error strings, that matching breaks.** Switch on the case
instead, which was always the supported approach:

```swift
// Fragile before, broken now
if error.localizedDescription.contains("error 6") { ... }

// Correct
if case .invalidTransition = error as? KadrError { ... }
```

If you *display* `localizedDescription`, you get better text for free — and
should also surface `recoverySuggestion`, which `localizedDescription` does not
include and which carries the actionable half of most messages.

### v0.18.0 — filter identities survive appends

Before v0.18, `.filter(_:)` regenerated **every** ``FilterID`` on the clip each
time a filter was appended. An animation bound with `filterAnimation(for:)` was
silently orphaned by the next `.filter(_:)` call.

That is now fixed: appending extends the id array instead of rebuilding it.

**If you worked around the old behaviour** — re-reading ids after every append,
or re-binding animations defensively — that code is now unnecessary. It is not
harmful, but it is the kind of workaround worth deleting while you remember why
it existed.

### v0.20.0 — a bitrate on a single image clip now takes a different path

``Video/quality(_:)`` is new, so this affects nobody upgrading. It is listed
because the behaviour is surprising in isolation: a composition of one
``ImageClip`` normally takes a fast path straight to the image encoder, and
setting an explicit quality deliberately disqualifies that path so the bitrate
can be honoured. The export is slower and produces the file you asked for.

## What 1.0 promises

No breaking change without a major version bump. The surface frozen at v0.14 is
the surface 1.0 commits to.

Additions will continue as minors. A `1.x` release may add API; it will not
remove or change the meaning of what is here.

## Topics

### Related

- ``Speed``
- ``FilterID``
- ``KadrError``
- <doc:FrameAccuracy>
