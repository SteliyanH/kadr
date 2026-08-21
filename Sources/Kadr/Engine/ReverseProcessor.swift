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
        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
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

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
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
