import Foundation
import Kadr

// Placeholder values for the README snippets in ReadmeSnippets.swift. The
// snippets only need to compile, so nothing here points at a real file.
//
// Images are computed rather than stored: `PlatformImage` is not Sendable,
// and Swift 6 rejects a stored global of a non-Sendable type.

private func placeholder(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/kadr-readme/\(name)")
}

var heroImage: PlatformImage { PlatformImage() }
var heroPhoto: PlatformImage { PlatformImage() }
var photo1: PlatformImage { PlatformImage() }
var photo2: PlatformImage { PlatformImage() }
var photo3: PlatformImage { PlatformImage() }
var logo: PlatformImage { PlatformImage() }

let outputURL = placeholder("out.mp4")
let musicURL = placeholder("music.m4a")
let musicAURL = placeholder("music-a.m4a")
let musicBURL = placeholder("music-b.m4a")
let newSoundtrackURL = placeholder("soundtrack.m4a")
let stingURL = placeholder("sting.m4a")
let clipURL = placeholder("clip.mov")
let clip1URL = placeholder("clip1.mov")
let clip2URL = placeholder("clip2.mov")
let cutawayURL = placeholder("cutaway.mov")
let originalURL = placeholder("original.mov")
let introURL = placeholder("intro.mov")
let actionURL = placeholder("action.mov")
let outroURL = placeholder("outro.mov")
let mainURL = placeholder("main.mov")
let pipURL = placeholder("pip.mov")
let rollA = placeholder("roll-a.mov")
let rollB = placeholder("roll-b.mov")
let baseURL = placeholder("base.mov")
let overlayURL = placeholder("overlay.mov")
let longVideoURL = placeholder("long.mov")
let urls = [clip1URL, clip2URL]

// The README's "Before (imperative) / After (Kadr)" table is inline code the
// generator does not see, so its rows are checked here by hand.
func readmeComparisonTable() async throws {
    let clipURL = clip1URL
    _ = try await Video { ImageClip(heroImage) }.audio(url: musicURL).export(to: outputURL)
    _ = try await Video { urls.map { VideoClip(url: $0) } }.export(to: outputURL)
    _ = try await Video { VideoClip(url: clipURL).reversed() }.export(to: outputURL)
    _ = try await Video { VideoClip(url: clipURL).trimmed(to: 5...20) }.export(to: outputURL)
    _ = try await Video { VideoClip(url: clipURL).muted() }.audio(url: musicURL).export(to: outputURL)
}
