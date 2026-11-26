import Testing
import Foundation
@testable import Kadr
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import VideoToolbox

/// Sources a phone actually records: 60 fps, variable frame rate, sound that has
/// to stay with the picture, and HDR.
///
/// The bundled `sample.mov` is constant 30 fps SDR with no audio, so none of this
/// was exercised. Every fixture here is generated: each frame draws a bar whose
/// position encodes that frame's own timestamp, so reading a frame of the export
/// says which source frame it came from, and whether it came from the right time.
struct SourceFormatTests {

    private static let width = 320, height = 96
    private static let barWidth = 8

    private func preset(fps: Int) -> Preset {
        .custom(width: Self.width, height: Self.height, frameRate: fps, codec: .h264)
    }

    // MARK: - Fixtures

    /// A clip whose frame at each of `times` draws the bar for that time, and
    /// whose last frame lasts until `duration`. With `clickAt`, it also has a
    /// silent mono audio track with one short click at that time.
    private func makeClip(times: [Double], duration: Double, clickAt click: Double? = nil) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_format_\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Self.width,
            AVVideoHeightKey: Self.height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
        ])
        writer.add(input)
        var audio: (input: AVAssetWriterInput, chunks: [CMSampleBuffer])?
        if let click {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            audio = (audioInput, try audioChunks(duration: duration, clickAt: click))
        }
        guard writer.startWriting() else { throw writer.error ?? KadrError.unsupportedFormat("Could not write the fixture") }
        writer.startSession(atSourceTime: .zero)

        // Feed both inputs as each becomes ready. Writing one to the end first can
        // stall: the writer interleaves, and waits for the input that is behind.
        var nextFrame = 0, nextChunk = 0
        while nextFrame < times.count || nextChunk < (audio?.chunks.count ?? 0) {
            var progressed = false
            if nextFrame < times.count, input.isReadyForMoreMediaData {
                let time = times[nextFrame]
                let buffer = try frame(showing: time, duration: duration, pool: adaptor.pixelBufferPool)
                guard adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 6000)) else {
                    throw writer.error ?? KadrError.unsupportedFormat("Could not write the fixture")
                }
                nextFrame += 1
                if nextFrame == times.count { input.markAsFinished() }
                progressed = true
            }
            if let audio, nextChunk < audio.chunks.count, audio.input.isReadyForMoreMediaData {
                guard audio.input.append(audio.chunks[nextChunk]) else {
                    throw writer.error ?? KadrError.unsupportedFormat("Could not write the fixture")
                }
                nextChunk += 1
                if nextChunk == audio.chunks.count { audio.input.markAsFinished() }
                progressed = true
            }
            if !progressed { try await Task.sleep(nanoseconds: 1_000_000) }
        }
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 6000))
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
    }

    /// Black, with a white bar whose left edge sits at `time / duration` of the way across.
    private func frame(showing time: Double, duration: Double, pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
        if buffer == nil {
            CVPixelBufferCreate(nil, Self.width, Self.height, kCVPixelFormatType_32BGRA, nil, &buffer)
        }
        guard let buffer else { throw KadrError.unsupportedFormat("Could not create a pixel buffer") }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw KadrError.unsupportedFormat("Pixel buffer has no memory")
        }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let barX = Int((time / duration * Double(Self.width - Self.barWidth)).rounded())
        for y in 0..<Self.height {
            let row = pixels + y * rowBytes
            for x in 0..<Self.width {
                let value: UInt8 = (barX..<(barX + Self.barWidth)).contains(x) ? 255 : 0
                row[x * 4] = value; row[x * 4 + 1] = value; row[x * 4 + 2] = value; row[x * 4 + 3] = 255
            }
        }
        return buffer
    }

    private static let sampleRate = 44_100.0

    /// Silence with a 2 ms full-scale burst at `click`, as 0.1 s sample buffers.
    private func audioChunks(duration: Double, clickAt click: Double) throws -> [CMSampleBuffer] {
        let total = Int(duration * Self.sampleRate)
        let clickStart = Int(click * Self.sampleRate)
        let clickRange = clickStart..<(clickStart + Int(0.002 * Self.sampleRate))
        var samples = [Int16](repeating: 0, count: total)
        for i in clickRange where i < total { samples[i] = i % 2 == 0 ? .max : .min }

        var description = AudioStreamBasicDescription(
            mSampleRate: Self.sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        guard let format else { throw KadrError.unsupportedFormat("Could not describe the audio") }

        let chunk = Int(Self.sampleRate / 10)
        return try stride(from: 0, to: total, by: chunk).map { start in
            let count = min(chunk, total - start)
            let bytes = count * 2
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
            )
            guard let block else { throw KadrError.unsupportedFormat("Could not allocate audio") }
            samples[start..<(start + count)].withUnsafeBytes { raw in
                _ = CMBlockBufferReplaceDataBytes(
                    with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes
                )
            }
            var buffer: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
                presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(Self.sampleRate)),
                packetDescriptions: nil, sampleBufferOut: &buffer
            )
            guard let buffer else { throw KadrError.unsupportedFormat("Could not build an audio buffer") }
            return buffer
        }
    }

    /// When the loudest moment in `url`'s audio is: the click, wherever the
    /// export put it.
    private func clickTime(in url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? KadrError.unsupportedFormat("Could not read audio") }

        var index = 0, loudest = 0, loudestIndex = 0
        var start: CMTime?
        while let buffer = output.copyNextSampleBuffer() {
            if start == nil { start = CMSampleBufferGetPresentationTimeStamp(buffer) }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Int16](repeating: 0, count: length / 2)
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            for sample in samples {
                let magnitude = abs(Int(sample))
                if magnitude > loudest { loudest = magnitude; loudestIndex = index }
                index += 1
            }
        }
        #expect(loudest > Int(Int16.max) / 4, "the click is missing from the export")
        return (start?.seconds ?? 0) + Double(loudestIndex) / Self.sampleRate
    }

    // MARK: - Reading frames back

    /// The source time the frame at `seconds` of `url` was drawn for, read from
    /// where its bar sits.
    private func sourceTime(in url: URL, at seconds: Double, duration: Double) async throws -> Double {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 6000))

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw KadrError.unsupportedFormat("Could not read the frame") }

        // Brightness-weighted centre of the columns, so compression blur around the
        // bar's edges moves the estimate by a fraction of a pixel, not a whole one.
        var weighted = 0.0, total = 0.0
        for x in 0..<width {
            var column = 0.0
            for y in 0..<height { column += Double(pixels[(y * width + x) * 4 + 1]) }
            let brightness = max(0, column / Double(height) - 32)
            weighted += brightness * Double(x)
            total += brightness
        }
        guard total > 0 else { throw KadrError.unsupportedFormat("No bar in the frame at \(seconds)s") }
        let centre = weighted / total
        let left = centre - Double(Self.barWidth - 1) / 2
        return left / Double(Self.width - Self.barWidth) * duration
    }

    /// The source frame a correct export shows at `seconds`: the latest source
    /// frame at or before the output frame that covers `seconds`.
    ///
    /// `trimStart` is where the clip's trim begins in source time.
    private func expectedSourceTime(at seconds: Double, fps: Int, times: [Double], trimStart: Double = 0) -> Double {
        let outputFrame = (seconds * Double(fps) + 1e-6).rounded(.down) / Double(fps)
        return times.last { $0 <= trimStart + outputFrame + 1e-6 } ?? times[0]
    }

    /// How far one pixel of bar movement is, in seconds of source time.
    private func secondsPerPixel(duration: Double) -> Double {
        duration / Double(Self.width - Self.barWidth)
    }

    private func export(_ video: Video) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_format_out_\(UUID().uuidString).mp4")
        return try await video.export(to: url)
    }

    private func frameRate(of url: URL) async throws -> Float {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        return try await track.load(.nominalFrameRate)
    }

    // MARK: - 60 fps

    /// A 60 fps source exported at 30 fps: every output frame shows the source
    /// frame for its own time, not a neighbour's, and the length is unchanged.
    @Test func sixtyFPSSourceAtThirtyFPS() async throws {
        let duration = 2.0
        let times = stride(from: 0.0, to: duration, by: 1.0 / 60).map { $0 }
        let source = try await makeClip(times: times, duration: duration)
        #expect(abs(try await frameRate(of: source) - 60) < 1)

        let out = try await export(Video { VideoClip(url: source) }.preset(preset(fps: 30)))
        #expect(abs(try await frameRate(of: out) - 30) < 1)
        let length = try await AVURLAsset(url: out).load(.duration).seconds
        #expect(abs(length - duration) < 1.0 / 30 + 0.001)

        for seconds in [0.0, 0.5, 1.0, 1.5, 1.9] {
            let measured = try await sourceTime(in: out, at: seconds, duration: duration)
            let expected = expectedSourceTime(at: seconds, fps: 30, times: times)
            #expect(abs(measured - expected) < secondsPerPixel(duration: duration),
                    "at \(seconds)s the export shows the frame for \(measured)s, not \(expected)s")
        }
    }

    /// A 60 fps source exported at 60 fps keeps every frame.
    @Test func sixtyFPSSourceAtSixtyFPS() async throws {
        let duration = 1.0
        let times = stride(from: 0.0, to: duration, by: 1.0 / 60).map { $0 }
        let source = try await makeClip(times: times, duration: duration)

        let out = try await export(Video { VideoClip(url: source) }.preset(preset(fps: 60)))
        #expect(abs(try await frameRate(of: out) - 60) < 1)

        // Consecutive frames, so a dropped or doubled frame cannot hide.
        for index in 28..<34 {
            let seconds = Double(index) / 60
            let measured = try await sourceTime(in: out, at: seconds, duration: duration)
            #expect(abs(measured - seconds) < secondsPerPixel(duration: duration),
                    "frame \(index) shows the source frame for \(measured)s")
        }
    }

    // MARK: - Variable frame rate

    /// Phones drop to a variable rate in low light: frame gaps of 1/60, 1/30 and
    /// 1/20 s in one clip. A constant-rate export must still show, at each moment,
    /// the frame that was on screen at that moment in the source.
    @Test func variableFrameRateSourceKeepsItsTiming() async throws {
        let duration = 2.0
        let gaps = [1.0 / 60, 1.0 / 60, 1.0 / 30, 1.0 / 20, 1.0 / 60, 1.0 / 30]
        var times: [Double] = [], t = 0.0, i = 0
        while t < duration - 1e-9 {
            times.append(t)
            t += gaps[i % gaps.count]; i += 1
        }
        let source = try await makeClip(times: times, duration: duration)

        let out = try await export(Video { VideoClip(url: source) }.preset(preset(fps: 30)))
        let length = try await AVURLAsset(url: out).load(.duration).seconds
        #expect(abs(length - duration) < 1.0 / 30 + 0.001)

        for seconds in stride(from: 0.1, to: duration, by: 0.23) {
            let measured = try await sourceTime(in: out, at: seconds, duration: duration)
            let expected = expectedSourceTime(at: seconds, fps: 30, times: times)
            #expect(abs(measured - expected) < secondsPerPixel(duration: duration),
                    "at \(seconds)s the export shows the frame for \(measured)s, not \(expected)s")
        }
    }

    // MARK: - Sound stays with the picture

    /// A trimmed variable-rate clip with its own sound: a click recorded at 1.5 s
    /// must come out at 1.0 s after trimming the first half second, and the frame
    /// on screen at that moment must be the one recorded with the click.
    @Test func variableFrameRateSourceStaysInSyncWithItsAudio() async throws {
        let duration = 3.0, click = 1.5, trimStart = 0.5
        let gaps = [1.0 / 60, 1.0 / 20, 1.0 / 30, 1.0 / 60, 1.0 / 60]
        var times: [Double] = [], t = 0.0, i = 0
        while t < duration - 1e-9 {
            times.append(t)
            t += gaps[i % gaps.count]; i += 1
        }
        let source = try await makeClip(times: times, duration: duration, clickAt: click)
        #expect(abs(try await clickTime(in: source) - click) < 0.002)

        let out = try await export(
            Video { VideoClip(url: source).trimmed(to: trimStart...(trimStart + 2)) }.preset(preset(fps: 30))
        )

        // Half a 30 fps frame: as much drift as a viewer could ever be shown.
        let heard = try await clickTime(in: out)
        #expect(abs(heard - (click - trimStart)) < 1.0 / 60,
                "the click is at \(heard)s, not \(click - trimStart)s")

        let seen = try await sourceTime(in: out, at: click - trimStart, duration: duration)
        let expected = expectedSourceTime(at: click - trimStart, fps: 30, times: times, trimStart: trimStart)
        #expect(abs(seen - expected) < secondsPerPixel(duration: duration),
                "with the click, the export shows the frame for \(seen)s, not \(expected)s")
    }

    // MARK: - HDR

    /// HLG signal levels for four vertical bands: dark, mid, reference white, peak.
    private static let hlgBands: [Double] = [0.25, 0.5, 0.75, 1.0]

    /// One second of 10-bit HEVC tagged BT.2020 / HLG, as an iPhone records HDR,
    /// showing ``hlgBands`` left to right.
    private func makeHLGClip() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_format_hlg_\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Self.width,
            AVVideoHeightKey: Self.height,
            AVVideoCompressionPropertiesKey: [
                kVTCompressionPropertyKey_ProfileLevel as String: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
            ],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? KadrError.unsupportedFormat("Could not write the fixture") }
        writer.startSession(atSourceTime: .zero)

        for index in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var made: CVPixelBuffer?
            if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) }
            guard let buffer = made else { throw KadrError.unsupportedFormat("Could not create a pixel buffer") }
            CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_2100_HLG, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)

            CVPixelBufferLockBaseAddress(buffer, [])
            // 10-bit video range, stored in the top bits of 16: luma 64...940,
            // chroma at its neutral 512, so every band is a grey.
            let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt16.self)
            let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) / 2
            for y in 0..<Self.height {
                for x in 0..<Self.width {
                    let signal = Self.hlgBands[x * Self.hlgBands.count / Self.width]
                    luma[y * lumaStride + x] = UInt16(64 + signal * (940 - 64)) << 6
                }
            }
            let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt16.self)
            let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) / 2
            for y in 0..<(Self.height / 2) {
                for x in 0..<Self.width { chroma[y * chromaStride + x] = 512 << 6 }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30)) else {
                throw writer.error ?? KadrError.unsupportedFormat("Could not write the fixture")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
    }

    /// The green channel at the centre of each band, in sRGB, at 0.5 s.
    private func bandLevels(of url: URL) async throws -> [Int] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(value: 15, timescale: 30))
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw KadrError.unsupportedFormat("Could not read the frame") }
        let bands = Self.hlgBands.count
        return (0..<bands).map { band in
            let x = band * width / bands + width / (2 * bands)
            return Int(pixels[((height / 2) * width + x) * 4 + 1])
        }
    }

    /// An iPhone HDR clip exports as SDR that says it is SDR, on every route a
    /// clip can take through the engine, and looks the way AVFoundation shows the
    /// source: tone mapped, not washed out, and not clipped to white.
    ///
    /// The failure this guards against is the silent one: BT.2020 / HLG tags
    /// carried onto 8-bit output, which players then render grey and flat.
    @Test(arguments: ["plain", "multiTrack", "filtered"])
    func hdrSourceExportsAsTaggedSDR(_ route: String) async throws {
        let source = try await makeHLGClip()
        let video: Video = switch route {
        case "plain": Video { VideoClip(url: source) }
        // A second track routes every frame through kadr's own compositor.
        case "multiTrack": Video {
            VideoClip(url: source)
            Track(at: .zero) { VideoClip(url: source).opacity(0) }
        }
        // A filter pre-renders the clip through Core Image first.
        default: Video { VideoClip(url: source).filter(.brightness(0)) }
        }
        let out = try await export(video.preset(preset(fps: 30)))

        let track = try #require(try await AVURLAsset(url: out).loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let tags = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        #expect(tags[kCVImageBufferColorPrimariesKey as String] as? String == kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
        #expect(tags[kCVImageBufferTransferFunctionKey as String] as? String == kCVImageBufferTransferFunction_ITU_R_709_2 as String)
        #expect(tags[kCVImageBufferYCbCrMatrixKey as String] as? String == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String)

        let reference = try await bandLevels(of: source)
        let exported = try await bandLevels(of: out)
        #expect(exported == exported.sorted() && Set(exported).count == exported.count,
                "bands must stay distinct and in order: \(exported)")
        for (got, want) in zip(exported, reference) {
            #expect(abs(got - want) <= 16, "exported \(exported), AVFoundation shows the source as \(reference)")
        }
    }
}
