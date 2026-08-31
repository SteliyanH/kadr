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

func draw(_ text: String, _ font: CTFont, _ color: CGColor, x: CGFloat, y: CGFloat, tracking: CGFloat = 0) {
    // CoreText keys directly: NSAttributedString.Key lives in Foundation's
    // UIKit/AppKit overlays, which a plain CoreGraphics tool does not link.
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
        kCTKernAttributeName: tracking,
    ]
    let attributed = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

let display = CTFontCreateWithName("Helvetica-Bold" as CFString, 96, nil)
let body    = CTFontCreateWithName("Helvetica" as CFString, 34, nil)
let mono    = CTFontCreateWithName("Menlo-Regular" as CFString, 25, nil)
let label   = CTFontCreateWithName("Helvetica-Bold" as CFString, 20, nil)

let left: CGFloat = 84

// Eyebrow.
draw("SWIFT PACKAGE · v1.0", label, accent, x: left, y: H - 128, tracking: 3.2)

// Wordmark and pitch.
draw("Kadr", display, paper, x: left, y: H - 236, tracking: -2)
draw("SwiftUI for video.", body, paper, x: left, y: H - 300)
draw("Compose, transform, export.", body, muted, x: left, y: H - 348)

// A composition, because showing the DSL says more than describing it.
let snippet = [
    "let url = try await Video {",
    "    VideoClip(url: clip).trimmed(to: 0...5)",
    "    Transition.fade(duration: 0.5)",
    "}",
    ".preset(.reelsAndShorts)",
    ".export(to: out)",
]
for (i, line) in snippet.enumerated() {
    let colour: CGColor = line.contains("Video {") || line.contains("Transition") ? accent : muted
    // Baseline high enough that the last line's descenders clear the
    // bottom edge — GitHub also crops these slightly.
    draw(line, mono, colour, x: left, y: 218 - CGFloat(i) * 33)
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
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("destination") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write") }
print("wrote \(out.path)")
