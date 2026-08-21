import AVFoundation
import CoreMedia

internal enum ReverseProcessor {

    static func reverse(videoAt url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = videoTracks.first else {
            throw KadrError.invalidURL(url)
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        // Read all video frames
        let reader = try AVAssetReader(asset: asset)
        // 32BGRA rather than 32ARGB.
        //
        // Both are 32-bit RGB, but BGRA is the format Apple's decoders and
        // encoders actually prefer — ARGB asks for a channel order that some
        // environments will not produce, and the failure surfaces late and
        // opaquely as a decode error rather than as "unsupported format".
        // Every filter and reverse test was skipped on CI because of failures
        // in this shape.
        //
        // Safe to change: these buffers are never interpreted here. They are
        // decoded, held, reversed, and handed back to the writer, so as long as
        // the reader and the adaptor below agree on the format, no channel
        // swap is possible.
        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
        reader.add(readerOutput)
        reader.startReading()

        // Collect sample buffers in batches
        var sampleBuffers: [CMSampleBuffer] = []
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            sampleBuffers.append(sampleBuffer)
        }

        guard reader.status == .completed else {
            throw KadrError.exportFailed(underlying: reader.error ?? NSError(domain: "Kadr", code: -1))
        }

        // Write frames in reverse order
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(naturalSize.width),
            AVVideoHeightKey: Int(naturalSize.height)
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        // Must match the reader's format above, or the round trip swaps channels.
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(naturalSize.width),
            kCVPixelBufferHeightKey as String: Int(naturalSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(nominalFrameRate))
        let reversedBuffers = sampleBuffers.reversed()

        for (index, sampleBuffer) in reversedBuffers.enumerated() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(index))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw KadrError.exportFailed(underlying: writer.error ?? NSError(domain: "Kadr", code: -1))
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw KadrError.exportFailed(underlying: writer.error ?? NSError(domain: "Kadr", code: -1))
        }

        return outputURL
    }
}
