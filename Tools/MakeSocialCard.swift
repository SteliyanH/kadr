import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// GitHub social preview card, 1280×640.
//
// Shown wherever the repo is linked — Slack, Discord, Twitter, Hacker News. The
// default is an auto-generated card of the owner's avatar and the repo name,
// which for a *video* library wastes the one impression that gets seen most.
//
// Same modernist vocabulary as the app icon: ink ground, one accent, flat
// geometry, and the timeline mark that says what this is at a glance.
//
// One card per repository in the family, so a link to any of them looks like
// it belongs to the same project:
//
//   swift Tools/MakeSocialCard.swift kadr-ui card.png
//
// Upload under the repository's Settings → General → Social preview; GitHub
// has no API for it. No card carries a version number: an uploaded card is
// never regenerated on release, so a version would go stale.

struct Card {
    let eyebrow: String
    let name: String
    let pitch: String
    let detail: String
    let snippet: [String]
    /// Lines containing any of these are drawn in the accent colour.
    let highlight: [String]
}

let cards: [String: Card] = [
    "kadr": Card(
        eyebrow: "SWIFT PACKAGE", name: "Kadr",
        pitch: "SwiftUI for video.", detail: "Compose, transform, export.",
        snippet: [
            "let url = try await Video {",
            "    VideoClip(url: clip).trimmed(to: 0...5)",
            "    Transition.fade(duration: 0.5)",
            "}",
            ".preset(.reelsAndShorts)",
            ".export(to: out)",
        ],
        highlight: ["Video {", "Transition"]
    ),
    "kadr-ui": Card(
        eyebrow: "SWIFT PACKAGE · FOR KADR", name: "KadrUI",
        pitch: "SwiftUI components for kadr.", detail: "Preview, timeline, inspectors.",
        snippet: [
            "ZStack {",
            "    VideoPreview(video)",
            "    OverlayHost(video)",
            "}",
            "TimelineView(video,",
            "    selectedClipID: $clipID)",
        ],
        highlight: ["VideoPreview", "TimelineView"]
    ),
    "kadr-captions": Card(
        eyebrow: "SWIFT PACKAGE · FOR KADR", name: "KadrCaptions",
        pitch: "Captions for kadr.", detail: "SRT, WebVTT, iTT and ASS, both ways.",
        snippet: [
            "let cues = try await Caption.load(url)",
            "",
            "Video {",
            "    VideoClip(url: footage)",
            "}",
            ".captions(cues)",
        ],
        highlight: ["Caption.load", ".captions"]
    ),
    "kadr-photos": Card(
        eyebrow: "SWIFT PACKAGE · FOR KADR", name: "KadrPhotos",
        pitch: "The Photos library, as clips.", detail: "Videos, stills, Live Photos, iCloud.",
        snippet: [
            "let clip = try await PhotosClipResolver",
            "    .video(asset: phAsset)",
            "",
            "Video {",
            "    clip",
            "}",
        ],
        highlight: ["PhotosClipResolver", "Video {"]
    ),
    "kadr-audio": Card(
        eyebrow: "SWIFT PACKAGE · FOR KADR", name: "KadrAudio",
        pitch: "Your music library, as audio.", detail: "With the DRM cases handled.",
        snippet: [
            "let songs = try MusicLibrary.usableSongs()",
            "let track = try MusicLibrary",
            "    .audioTrack(for: songs[0])",
            "video.audio {",
            "    track.volume(0.4).ducking(0.2)",
            "}",
        ],
        highlight: ["usableSongs", "ducking"]
    ),
    "kadr-persistence": Card(
        eyebrow: "SWIFT PACKAGE · FOR KADR", name: "KadrPersistence",
        pitch: "Save a composition. Open it again.", detail: "Nothing lost without telling you.",
        snippet: [
            "// save",
            "let data = try KadrCoding.data(for: video)",
            "",
            "// open",
            "let video = try KadrCoding.video(from: data)",
        ],
        highlight: ["KadrCoding"]
    ),
    "kadr-reels-studio": Card(
        eyebrow: "IOS APP · BUILT ON KADR", name: "Kadr Studio",
        pitch: "A short-form video editor.", detail: "The reference app for kadr.",
        snippet: [
            "Photos import · multi-lane timeline",
            "overlays · filters · animated text",
            "music with ducking · voiceover",
            "captions · projects that reopen",
        ],
        highlight: []
    ),
]

let usage = "usage: swift Tools/MakeSocialCard.swift <\(cards.keys.sorted().joined(separator: "|"))> <out.png>"
guard CommandLine.arguments.count == 3, let card = cards[CommandLine.arguments[1]] else {
    fatalError(usage)
}

let W: CGFloat = 1280, H: CGFloat = 640
let ink    = CGColor(red: 0x14/255, green: 0x16/255, blue: 0x1A/255, alpha: 1)
let paper  = CGColor(red: 0xF1/255, green: 0xF2/255, blue: 0xF4/255, alpha: 1)
let accent = CGColor(red: 0xFF/255, green: 0x56/255, blue: 0x3C/255, alpha: 1)
let muted  = CGColor(red: 0x9B/255, green: 0xA3/255, blue: 0xAD/255, alpha: 1)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("context") }

ctx.setFillColor(ink)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

let left: CGFloat = 84
// Text stops short of the timeline mark on the right.
let textWidth: CGFloat = (W - 400) - left - 48

func line(_ text: String, _ font: CTFont, _ color: CGColor, tracking: CGFloat) -> CTLine {
    // CoreText keys directly: NSAttributedString.Key lives in Foundation's
    // UIKit/AppKit overlays, which a plain CoreGraphics tool does not link.
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
        kCTKernAttributeName: tracking,
    ]
    return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!)
}

func fitted(_ text: String, _ font: CTFont, tracking: CGFloat = 0) -> CTFont {
    var size = CTFontGetSize(font)
    var candidate = font
    while CGFloat(CTLineGetTypographicBounds(line(text, candidate, paper, tracking: tracking), nil, nil, nil)) > textWidth,
          size > 8 {
        size -= 1
        candidate = CTFontCreateCopyWithAttributes(font, size, nil, nil)
    }
    return candidate
}

func draw(_ text: String, _ font: CTFont, _ color: CGColor, x: CGFloat, y: CGFloat, tracking: CGFloat = 0) {
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line(text, font, color, tracking: tracking), ctx)
}

let display = CTFontCreateWithName("Helvetica-Bold" as CFString, 96, nil)
let body    = CTFontCreateWithName("Helvetica" as CFString, 34, nil)
let mono    = CTFontCreateWithName("Menlo-Regular" as CFString, 25, nil)
let label   = CTFontCreateWithName("Helvetica-Bold" as CFString, 20, nil)

// Eyebrow.
draw(card.eyebrow, label, accent, x: left, y: H - 128, tracking: 3.2)

// Wordmark and pitch.
draw(card.name, fitted(card.name, display, tracking: -2), paper, x: left, y: H - 236, tracking: -2)
draw(card.pitch, fitted(card.pitch, body), paper, x: left, y: H - 300)
draw(card.detail, fitted(card.detail, body), muted, x: left, y: H - 348)

// Code, because showing the API says more than describing it. One size for
// every line, fitted to the longest, so the block stays aligned.
let code = card.snippet.max { $0.count < $1.count }.map { fitted($0, mono) } ?? mono
for (i, line) in card.snippet.enumerated() {
    let colour: CGColor = card.highlight.contains { line.contains($0) } ? accent : muted
    // Baseline high enough that the last line's descenders clear the
    // bottom edge — GitHub also crops these slightly.
    draw(line, code, colour, x: left, y: 218 - CGFloat(i) * 33)
}

// The timeline mark, right-hand side — the same one as the app icon.
let barH: CGFloat = 34, gap: CGFloat = 18, radius: CGFloat = 9
let markLeft = W - 400, fullW: CGFloat = 300
let stackH = barH * 3 + gap * 2
let firstY = (H - stackH) / 2

func bar(_ r: CGRect, _ c: CGColor) {
    ctx.setFillColor(c)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}
bar(CGRect(x: markLeft, y: firstY, width: fullW, height: barH), paper)
bar(CGRect(x: markLeft, y: firstY + barH + gap, width: fullW * 0.55, height: barH), accent)
let cut: CGFloat = 14, leftPiece = fullW * 0.42
let topY = firstY + (barH + gap) * 2
bar(CGRect(x: markLeft, y: topY, width: leftPiece, height: barH), accent)
bar(CGRect(x: markLeft + leftPiece + cut, y: topY, width: fullW - leftPiece - cut, height: barH), accent)
ctx.setFillColor(paper)
ctx.fill(CGRect(x: markLeft + leftPiece + (cut - 5) / 2, y: firstY - 26, width: 5, height: stackH + 52))

guard let image = ctx.makeImage() else { fatalError("image") }
let out = URL(fileURLWithPath: CommandLine.arguments[2])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("destination") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write") }
print("wrote \(out.path)")
