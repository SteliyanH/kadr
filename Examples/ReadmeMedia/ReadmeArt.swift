import AVFoundation
import CoreGraphics
import Foundation
import Kadr
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Media for the README recipes, drawn in code.
///
/// The README's GIFs are rendered by running its own snippets (see
/// `ReadmeMediaRenderer`), so those snippets need real pictures, clips and
/// music. Drawing them keeps the repository free of stock media and its
/// licences, and anyone can re-render the GIFs from a clean checkout.
/// Everything is deterministic: the same code draws the same frames.
enum ReadmeArt {

    /// Where the generated clips and music are written.
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kadr-readme", isDirectory: true)

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    // MARK: - Scenes

    private struct Palette {
        let skyTop: CGColor, skyBottom: CGColor, sun: CGColor
        let ridges: [CGColor]          // far to near
        let stars: Bool
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static let palettes: [Palette] = [
        // 0: dawn coast
        Palette(skyTop: rgb(0.99, 0.60, 0.42), skyBottom: rgb(1.00, 0.87, 0.68), sun: rgb(1, 0.97, 0.86),
                ridges: [rgb(0.93, 0.56, 0.50), rgb(0.71, 0.38, 0.45), rgb(0.40, 0.22, 0.36)], stars: false),
        // 1: alpine noon
        Palette(skyTop: rgb(0.33, 0.60, 0.92), skyBottom: rgb(0.80, 0.91, 0.98), sun: rgb(1, 1, 0.93),
                ridges: [rgb(0.58, 0.70, 0.84), rgb(0.31, 0.51, 0.63), rgb(0.13, 0.31, 0.38)], stars: false),
        // 2: dusk
        Palette(skyTop: rgb(0.20, 0.16, 0.42), skyBottom: rgb(0.94, 0.51, 0.47), sun: rgb(1, 0.82, 0.56),
                ridges: [rgb(0.56, 0.33, 0.51), rgb(0.34, 0.20, 0.41), rgb(0.15, 0.10, 0.25)], stars: false),
        // 3: night lake
        Palette(skyTop: rgb(0.04, 0.07, 0.20), skyBottom: rgb(0.17, 0.28, 0.47), sun: rgb(0.95, 0.95, 0.88),
                ridges: [rgb(0.15, 0.23, 0.37), rgb(0.09, 0.15, 0.27), rgb(0.04, 0.08, 0.16)], stars: true),
    ]

    /// Height of ridge `layer` at horizontal position `u` (0...1 of the width),
    /// as a fraction of the frame height. Three sines make it read as hills.
    private static func ridge(_ layer: Int, _ u: CGFloat) -> CGFloat {
        let base: [CGFloat] = [0.46, 0.33, 0.19]
        let amp: [CGFloat] = [0.10, 0.08, 0.06]
        let phase = CGFloat(layer) * 1.9 + 0.4
        let wave = 0.55 * sin(2 * .pi * u * 1.3 + phase)
            + 0.30 * sin(2 * .pi * u * 3.1 + phase * 1.7)
            + 0.15 * sin(2 * .pi * u * 7.0 + phase * 2.3)
        return base[layer] + amp[layer] * wave
    }

    /// Draws scene `index` into `context`, which is `size` with a y-up origin.
    /// `pan` slides the ridges sideways, nearer ridges further, for parallax.
    private static func drawScene(_ context: CGContext, size: CGSize, index: Int, pan: CGFloat = 0, clouds: CGFloat = 0) {
        let palette = palettes[((index % palettes.count) + palettes.count) % palettes.count]
        let w = size.width, h = size.height

        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [palette.skyBottom, palette.skyTop] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h * 0.2), end: CGPoint(x: 0, y: h), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        if palette.stars {
            var seed: UInt64 = 7
            for _ in 0..<90 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat(seed >> 33 % 10_000) / 10_000 * w
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let y = h * (0.45 + 0.55 * CGFloat(seed >> 33 % 10_000) / 10_000)
                context.setFillColor(rgb(1, 1, 1, 0.75))
                context.fillEllipse(in: CGRect(x: x, y: y, width: h * 0.004, height: h * 0.004))
            }
        }

        let sunRadius = min(w, h) * 0.09
        context.setFillColor(palette.sun)
        context.fillEllipse(in: CGRect(x: w * 0.68 - sunRadius, y: h * 0.62 - sunRadius,
                                       width: sunRadius * 2, height: sunRadius * 2))

        for cloud in 0..<3 {
            let speed = 0.03 + CGFloat(cloud) * 0.015
            var x = (CGFloat(cloud) * 0.37 + clouds * speed).truncatingRemainder(dividingBy: 1.3) - 0.15
            if x < -0.15 { x += 1.3 }
            let y = 0.78 + CGFloat(cloud % 2) * 0.07
            context.setFillColor(rgb(1, 1, 1, palette.stars ? 0.10 : 0.55))
            for (dx, r) in [(0.0, 0.05), (0.045, 0.065), (0.095, 0.045)] as [(CGFloat, CGFloat)] {
                context.fillEllipse(in: CGRect(x: (x + dx) * w, y: y * h - r * h * 0.5, width: r * h * 1.6, height: r * h))
            }
        }

        for layer in 0..<palette.ridges.count {
            let shift = pan * CGFloat(layer + 1) * 0.12
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            let steps = 160
            for step in 0...steps {
                let u = CGFloat(step) / CGFloat(steps)
                path.addLine(to: CGPoint(x: u * w, y: ridge(layer, u + shift) * h))
            }
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(palette.ridges[layer])
            context.fillPath()
        }
    }

    private static func render(size: CGSize, _ draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context)
        return context.makeImage()!
    }

    private static func platformImage(_ image: CGImage) -> PlatformImage {
        #if canImport(UIKit)
        return UIImage(cgImage: image)
        #else
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        #endif
    }

    /// A still landscape: 0 dawn coast, 1 alpine noon, 2 dusk, 3 night lake.
    static func scene(_ index: Int, size: CGSize = CGSize(width: 1920, height: 1080)) -> PlatformImage {
        platformImage(render(size: size) { drawScene($0, size: size, index: index) })
    }

    // MARK: - Clips

    /// Writes an H.264 `.mov` whose frames `draw` paints, given the time in seconds.
    static func writeMovie(
        to url: URL,
        size: CGSize = CGSize(width: 1280, height: 720),
        seconds: Double,
        fps: Int = 30,
        draw: (CGContext, CGSize, Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = Int(size.width), height = Int(size.height)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting(), let pool = adaptor.pixelBufferPool else {
            throw KadrError.unsupportedFormat("Could not start writing \(url.lastPathComponent)")
        }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { throw KadrError.unsupportedFormat("No pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )!
            draw(context, size, Double(frame) / Double(fps))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    /// Slow sideways flight over the alpine scene, clouds drifting.
    static func drawDrone(_ context: CGContext, _ size: CGSize, _ t: Double) {
        drawScene(context, size: size, index: 1, pan: CGFloat(t) * 0.35, clouds: CGFloat(t) * 2)
    }

    /// A cartoon face talking into the camera: blinks, eyebrows, moving mouth.
    static func drawReaction(_ context: CGContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [rgb(0.42, 0.33, 0.85), rgb(0.95, 0.47, 0.66)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])

        let r = h * 0.34
        let center = CGPoint(x: w / 2, y: h * 0.47 + CGFloat(sin(t * 2.2)) * h * 0.012)
        context.setFillColor(rgb(1.0, 0.83, 0.33))
        context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))

        // Blink for 0.12 s every 2.3 s.
        let blinking = t.truncatingRemainder(dividingBy: 2.3) < 0.12
        let eyeHeight = blinking ? r * 0.03 : r * 0.2
        context.setFillColor(rgb(0.18, 0.14, 0.22))
        for side in [-1.0, 1.0] as [CGFloat] {
            let eye = CGPoint(x: center.x + side * r * 0.36, y: center.y + r * 0.22)
            context.fillEllipse(in: CGRect(x: eye.x - r * 0.08, y: eye.y - eyeHeight / 2, width: r * 0.16, height: eyeHeight))
            // Eyebrows lift on the "wow" beats.
            let lift = CGFloat(max(0, sin(t * 1.4))) * r * 0.08
            context.setLineWidth(r * 0.05)
            context.setLineCap(.round)
            context.setStrokeColor(rgb(0.18, 0.14, 0.22))
            context.move(to: CGPoint(x: eye.x - r * 0.12, y: eye.y + r * 0.2 + lift))
            context.addLine(to: CGPoint(x: eye.x + r * 0.12, y: eye.y + r * 0.24 + lift))
            context.strokePath()
        }

        let open = CGFloat(abs(sin(t * 8.5))) * 0.6 + 0.15
        let mouth = CGRect(x: center.x - r * 0.22, y: center.y - r * 0.42 - r * 0.12 * open,
                           width: r * 0.44, height: r * 0.24 * open)
        context.setFillColor(rgb(0.55, 0.13, 0.20))
        context.fillEllipse(in: mouth)
    }

    /// A presenter on a pure green backdrop, waving. Nothing in the figure is green.
    static func drawPresenter(_ context: CGContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        context.setFillColor(rgb(0, 1, 0))
        context.fill(CGRect(origin: .zero, size: size))

        let bob = CGFloat(sin(t * 3)) * h * 0.01
        let cx = w * 0.5
        // Legs and body.
        context.setFillColor(rgb(0.20, 0.24, 0.45))
        context.fill(CGRect(x: cx - h * 0.09, y: 0, width: h * 0.07, height: h * 0.26))
        context.fill(CGRect(x: cx + h * 0.02, y: 0, width: h * 0.07, height: h * 0.26))
        context.setFillColor(rgb(0.95, 0.42, 0.30))
        context.addPath(CGPath(roundedRect: CGRect(x: cx - h * 0.13, y: h * 0.24 + bob, width: h * 0.26, height: h * 0.32),
                               cornerWidth: h * 0.06, cornerHeight: h * 0.06, transform: nil))
        context.fillPath()

        // Waving arm from the right shoulder.
        let shoulder = CGPoint(x: cx + h * 0.11, y: h * 0.50 + bob)
        let angle = CGFloat(.pi / 3 + sin(t * 6) * 0.45)
        context.setStrokeColor(rgb(0.95, 0.42, 0.30))
        context.setLineWidth(h * 0.055)
        context.setLineCap(.round)
        context.move(to: shoulder)
        let hand = CGPoint(x: shoulder.x + cos(angle) * h * 0.2, y: shoulder.y + sin(angle) * h * 0.2)
        context.addLine(to: hand)
        context.strokePath()
        context.setFillColor(rgb(0.99, 0.80, 0.62))
        context.fillEllipse(in: CGRect(x: hand.x - h * 0.035, y: hand.y - h * 0.035, width: h * 0.07, height: h * 0.07))

        // Head with a smile.
        let head = CGPoint(x: cx, y: h * 0.66 + bob)
        let r = h * 0.1
        context.fillEllipse(in: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r))
        context.setFillColor(rgb(0.18, 0.14, 0.22))
        for side in [-1.0, 1.0] as [CGFloat] {
            context.fillEllipse(in: CGRect(x: head.x + side * r * 0.38 - r * 0.08, y: head.y + r * 0.15, width: r * 0.16, height: r * 0.2))
        }
        context.setStrokeColor(rgb(0.18, 0.14, 0.22))
        context.setLineWidth(r * 0.08)
        context.addArc(center: CGPoint(x: head.x, y: head.y - r * 0.05), radius: r * 0.45,
                       startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        context.strokePath()
    }

    /// A ball rolling steadily across a field with fence posts, so a change of
    /// playback speed is easy to see.
    static func drawRoll(_ context: CGContext, _ size: CGSize, _ t: Double, duration: Double) {
        let w = size.width, h = size.height
        drawScene(context, size: size, index: 0)
        context.setFillColor(rgb(0.36, 0.20, 0.33))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.16))
        context.setFillColor(rgb(0.98, 0.93, 0.85))
        for post in stride(from: 0.05, to: 1.0, by: 0.1) {
            context.fill(CGRect(x: CGFloat(post) * w, y: h * 0.16, width: w * 0.008, height: h * 0.07))
        }

        let r = h * 0.07
        let progress = CGFloat(t / duration)
        let x = w * 0.08 + progress * w * 0.84
        let center = CGPoint(x: x, y: h * 0.16 + r)
        context.setFillColor(rgb(0.13, 0.55, 0.85))
        context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        // A stripe that turns with the roll.
        let turn = -(x - w * 0.08) / r
        context.setStrokeColor(rgb(1, 1, 1))
        context.setLineWidth(r * 0.22)
        context.move(to: CGPoint(x: center.x - cos(turn) * r * 0.8, y: center.y - sin(turn) * r * 0.8))
        context.addLine(to: CGPoint(x: center.x + cos(turn) * r * 0.8, y: center.y + sin(turn) * r * 0.8))
        context.strokePath()
    }

    // MARK: - Music

    /// A soft arpeggio, as 16-bit stereo WAV.
    static func writeMusic(to url: URL, seconds: Double) throws {
        let rate = 44_100
        let notes: [Double] = [261.63, 329.63, 392.00, 493.88, 392.00, 329.63]   // C E G B G E
        let noteLength = 0.25
        var samples = [Int16]()
        samples.reserveCapacity(Int(seconds * Double(rate)) * 2)
        for i in 0..<Int(seconds * Double(rate)) {
            let time = Double(i) / Double(rate)
            let note = notes[Int(time / noteLength) % notes.count]
            let within = time.truncatingRemainder(dividingBy: noteLength)
            let envelope = exp(-within * 9)
            let pad = 0.12 * sin(2 * .pi * 130.81 * time)          // low C underneath
            let value = 0.35 * envelope * sin(2 * .pi * note * time) + pad
            let sample = Int16(max(-1, min(1, value)) * Double(Int16.max))
            samples.append(sample)
            samples.append(sample)
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let payload = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + payload))
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(2)); append(UInt32(rate))
        append(UInt32(rate * 4)); append(UInt16(4)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(payload))
        for sample in samples { append(sample) }
        try data.write(to: url)
    }

    // MARK: - Everything

    /// Writes every clip and the music the README snippets refer to.
    static func prepare() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeMusic(to: url("music.wav"), seconds: 14)
        try await writeMovie(to: url("drone.mov"), seconds: 8, draw: drawDrone)
        try await writeMovie(to: url("reaction.mov"), seconds: 6, draw: drawReaction)
        try await writeMovie(to: url("presenter.mov"), seconds: 5, draw: drawPresenter)
        try await writeMovie(to: url("roll.mov"), seconds: 4) { context, size, t in
            drawRoll(context, size, t, duration: 4)
        }
    }
}
