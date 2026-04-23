import AVFoundation
import CoreMedia

internal enum CompositionBuilder {

    struct CompositionResult: @unchecked Sendable {
        let composition: AVMutableComposition
        let audioMix: AVMutableAudioMix?
    }

    static func build(
        from clips: [any Clip],
        audioTracks: [AudioTrack],
        preset: Preset
    ) async throws -> CompositionResult {
        let composition = AVMutableComposition()
        var insertionPoint: CMTime = .zero

        // Create reusable composition tracks
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create video track"]))
        }

        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        for clip in clips {
            if clip is Transition {
                throw KadrError.notYetImplemented("Transitions arrive in v0.2")
            }

            if let videoClip = clip as? VideoClip {
                try await insertVideoClip(
                    videoClip,
                    into: composition,
                    videoTrack: compositionVideoTrack,
                    audioTrack: compositionAudioTrack,
                    at: &insertionPoint,
                    preset: preset
                )
            } else if let imageClip = clip as? ImageClip {
                try await insertImageClip(
                    imageClip,
                    into: composition,
                    videoTrack: compositionVideoTrack,
                    audioTrack: compositionAudioTrack,
                    at: &insertionPoint,
                    preset: preset
                )
            }
        }

        // Add video-level audio tracks
        var audioMixParameters: [AVMutableAudioMixInputParameters] = []

        for audioTrack in audioTracks {
            let audioAsset = AVURLAsset(url: audioTrack.url)
            let sourceTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            guard let sourceAudioTrack = sourceTracks.first else { continue }

            guard let bgAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            let audioDuration = try await audioAsset.load(.duration)
            let compositionDuration = insertionPoint
            let insertDuration = CMTimeMinimum(audioDuration, compositionDuration)

            try bgAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: sourceAudioTrack,
                at: .zero
            )

            // Apply audio modifiers
            let params = AVMutableAudioMixInputParameters(track: bgAudioTrack)

            if audioTrack.volumeLevel != 1.0 {
                params.setVolume(Float(audioTrack.volumeLevel), at: .zero)
            }

            if audioTrack.fadeInDuration > 0 {
                params.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: Float(audioTrack.volumeLevel),
                    timeRange: CMTimeRange(
                        start: .zero,
                        duration: CMTime(seconds: audioTrack.fadeInDuration, preferredTimescale: 600)
                    )
                )
            }

            if audioTrack.fadeOutDuration > 0 {
                let fadeStart = CMTimeSubtract(insertDuration, CMTime(seconds: audioTrack.fadeOutDuration, preferredTimescale: 600))
                params.setVolumeRamp(
                    fromStartVolume: Float(audioTrack.volumeLevel),
                    toEndVolume: 0,
                    timeRange: CMTimeRange(
                        start: fadeStart,
                        duration: CMTime(seconds: audioTrack.fadeOutDuration, preferredTimescale: 600)
                    )
                )
            }

            audioMixParameters.append(params)
        }

        var audioMix: AVMutableAudioMix?
        if !audioMixParameters.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioMixParameters
            audioMix = mix
        }

        return CompositionResult(composition: composition, audioMix: audioMix)
    }

    // MARK: - VideoClip insertion

    private static func insertVideoClip(
        _ clip: VideoClip,
        into composition: AVMutableComposition,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack?,
        at insertionPoint: inout CMTime,
        preset: Preset
    ) async throws {
        var assetURL = clip.url

        // Handle reversal by pre-processing
        if clip.isReversed {
            assetURL = try await ReverseProcessor.reverse(videoAt: assetURL)
        }

        let asset = AVURLAsset(url: assetURL)
        let assetDuration = try await asset.load(.duration)

        // Determine source time range
        let sourceRange: CMTimeRange
        if let trimRange = clip.trimRange {
            let start = CMTime(seconds: trimRange.lowerBound, preferredTimescale: 600)
            let end = CMTime(seconds: trimRange.upperBound, preferredTimescale: 600)
            sourceRange = CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
        } else {
            sourceRange = CMTimeRange(start: .zero, duration: assetDuration)
        }

        // Insert video track
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let sourceVideoTrack = videoTracks.first {
            try videoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: insertionPoint)
        }

        // Insert audio track (unless muted)
        if !clip.isMuted, let audioTrack {
            let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = sourceAudioTracks.first {
                try audioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: insertionPoint)
            }
        }

        // Insert replacement audio if present
        if let replacementAudioURL = clip.replacementAudioURL, let audioTrack {
            let audioAsset = AVURLAsset(url: replacementAudioURL)
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = audioTracks.first {
                let audioDuration = try await audioAsset.load(.duration)
                let clipDuration = sourceRange.duration
                let insertDuration = CMTimeMinimum(audioDuration, clipDuration)
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: insertDuration),
                    of: sourceAudioTrack,
                    at: insertionPoint
                )
            }
        }

        insertionPoint = CMTimeAdd(insertionPoint, sourceRange.duration)
    }

    // MARK: - ImageClip insertion (multi-clip context)

    private static func insertImageClip(
        _ clip: ImageClip,
        into composition: AVMutableComposition,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack?,
        at insertionPoint: inout CMTime,
        preset: Preset
    ) async throws {
        // Encode image to temporary video file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        _ = try await ImageEncoder.encode(
            image: clip.image,
            duration: clip.duration,
            preset: preset,
            audioURL: nil,
            to: tempURL
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let tempAsset = AVURLAsset(url: tempURL)
        let tempDuration = try await tempAsset.load(.duration)
        let tempVideoTracks = try await tempAsset.loadTracks(withMediaType: .video)

        if let sourceTempTrack = tempVideoTracks.first {
            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: tempDuration),
                of: sourceTempTrack,
                at: insertionPoint
            )
        }

        // Handle per-clip audio
        if let clipAudioURL = clip.audioURL, let audioTrack {
            let audioAsset = AVURLAsset(url: clipAudioURL)
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = audioTracks.first {
                let audioDuration = try await audioAsset.load(.duration)
                let insertDuration = CMTimeMinimum(audioDuration, tempDuration)
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: insertDuration),
                    of: sourceAudioTrack,
                    at: insertionPoint
                )
            }
        }

        insertionPoint = CMTimeAdd(insertionPoint, tempDuration)
    }
}
