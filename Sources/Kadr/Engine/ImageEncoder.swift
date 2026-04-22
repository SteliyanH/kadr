import AVFoundation
import CoreMedia
import CoreVideo
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

internal enum ImageEncoder {

    static func encode(
        image: PlatformImage,
        duration: CMTime,
        preset: Preset,
        audioURL: URL?,
        to outputURL: URL
    ) async throws -> URL {
        let resolution = preset.resolution
        let frameRate = preset.frameRate
        let width = Int(resolution.width)
        let height = Int(resolution.height)

        // If audio is needed, encode silent video to temp then merge
        let videoURL: URL
        if audioURL != nil {
            videoURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        } else {
            videoURL = outputURL
        }

        // Remove existing file if present
        try? FileManager.default.removeItem(at: videoURL)

        try await encodeImageToVideo(
            image: image,
            duration: duration,
            width: width,
            height: height,
            frameRate: frameRate,
            codec: preset.codec,
            to: videoURL
        )

        guard let audioURL else {
            return videoURL
        }

        // Merge silent video with audio
        let mergedURL = outputURL
        try? FileManager.default.removeItem(at: mergedURL)
        try await mergeVideoWithAudio(videoURL: videoURL, audioURL: audioURL, duration: duration, to: mergedURL)

        // Clean up temp silent video
        try? FileManager.default.removeItem(at: videoURL)

        return mergedURL
    }

    private static func encodeImageToVideo(
        image: PlatformImage,
        duration: CMTime,
        width: Int,
        height: Int,
        frameRate: Int,
        codec: Codec,
        to outputURL: URL
    ) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoCodec: AVVideoCodecType = codec == .hevc ? .hevc : .h264
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: videoCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(CMTimeGetSeconds(duration) * Double(frameRate))
        guard totalFrames > 0 else {
            throw KadrError.noClipsProvided
        }

        let pixelBuffer = try createPixelBuffer(from: image, width: width, height: height)

        for frameIndex in 0..<totalFrames {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(frameRate))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw KadrError.exportFailed(underlying: writer.error ?? NSError(domain: "Kadr", code: -1))
            }
        }

        videoInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw KadrError.exportFailed(underlying: writer.error ?? NSError(domain: "Kadr", code: -1))
        }
    }

    private static func createPixelBuffer(from image: PlatformImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"]))
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get pixel buffer base address"]))
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"]))
        }

        guard let cgImage = platformImageToCGImage(image) else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to CGImage"]))
        }

        // Draw scaled to fill
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    private static func platformImageToCGImage(_ image: PlatformImage) -> CGImage? {
        #if canImport(UIKit)
        return image.cgImage
        #elseif canImport(AppKit)
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    private static func mergeVideoWithAudio(
        videoURL: URL,
        audioURL: URL,
        duration: CMTime,
        to outputURL: URL
    ) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        // Add video track
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track in encoded file"]))
        }
        let videoDuration = try await videoAsset.load(.duration)
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to add video track"]))
        }
        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideoTrack, at: .zero)

        // Add audio track
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        if let sourceAudioTrack = audioTracks.first {
            guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to add audio track"]))
            }
            let audioDuration = try await audioAsset.load(.duration)
            let insertDuration = CMTimeMinimum(audioDuration, videoDuration)
            try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: insertDuration), of: sourceAudioTrack, at: .zero)
        }

        // Export
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]))
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        await exportSession.export()

        if exportSession.status == .failed {
            throw KadrError.exportFailed(underlying: exportSession.error ?? NSError(domain: "Kadr", code: -1))
        }
    }
}
