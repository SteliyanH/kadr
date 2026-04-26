import AVFoundation
import CoreMedia

internal enum CompositionBuilder {

    struct CompositionResult: @unchecked Sendable {
        let composition: AVMutableComposition
        let audioMix: AVMutableAudioMix?
        let videoComposition: AVMutableVideoComposition?
    }

    static func build(
        from clips: [any Clip],
        audioTracks: [AudioTrack],
        preset: Preset
    ) async throws -> CompositionResult {
        if clips.contains(where: { $0 is Transition }) {
            return try await buildWithTransitions(clips: clips, audioTracks: audioTracks, preset: preset)
        }
        return try await buildSimple(clips: clips, audioTracks: audioTracks, preset: preset)
    }

    // MARK: - No-transition path (single video track)

    private static func buildSimple(
        clips: [any Clip],
        audioTracks: [AudioTrack],
        preset: Preset
    ) async throws -> CompositionResult {
        let composition = AVMutableComposition()
        var insertionPoint: CMTime = .zero

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
            if let videoClip = clip as? VideoClip {
                try await insertVideoClip(
                    videoClip,
                    videoTrack: compositionVideoTrack,
                    audioTrack: compositionAudioTrack,
                    at: &insertionPoint,
                    preset: preset
                )
            } else if let imageClip = clip as? ImageClip {
                try await insertImageClip(
                    imageClip,
                    videoTrack: compositionVideoTrack,
                    audioTrack: compositionAudioTrack,
                    at: &insertionPoint,
                    preset: preset
                )
            }
        }

        let audioMix = try await buildBackgroundAudioMix(
            composition: composition,
            audioTracks: audioTracks,
            totalDuration: insertionPoint
        )

        return CompositionResult(composition: composition, audioMix: audioMix, videoComposition: nil)
    }

    // MARK: - Transition path (alternating tracks + custom videoComposition)

    private static func buildWithTransitions(
        clips: [any Clip],
        audioTracks: [AudioTrack],
        preset: Preset
    ) async throws -> CompositionResult {
        // 1. Plan: walk clips, validate, produce media items + transition-after links
        let plan = try planTransitions(clips: clips)

        // 2. Build composition with two alternating video + audio tracks
        let composition = AVMutableComposition()

        guard
            let videoTrackA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let videoTrackB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create video tracks"]))
        }
        let audioTrackA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrackB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let videoTracks = [videoTrackA, videoTrackB]
        let audioTracksAB = [audioTrackA, audioTrackB]

        // 3. Place each media item; track its actual time range on its assigned track
        var placements: [Placement] = []
        var cursor: CMTime = .zero

        for (index, item) in plan.items.enumerated() {
            let trackIndex = index % 2
            let videoTrack = videoTracks[trackIndex]
            let audioTrack = audioTracksAB[trackIndex]

            let startTime = cursor
            var insertionPoint = startTime

            let durationBefore = insertionPoint
            if let videoClip = item.clip as? VideoClip {
                try await insertVideoClip(videoClip, videoTrack: videoTrack, audioTrack: audioTrack, at: &insertionPoint, preset: preset)
            } else if let imageClip = item.clip as? ImageClip {
                try await insertImageClip(imageClip, videoTrack: videoTrack, audioTrack: audioTrack, at: &insertionPoint, preset: preset)
            }
            let placedDuration = CMTimeSubtract(insertionPoint, durationBefore)
            let timeRange = CMTimeRange(start: startTime, duration: placedDuration)
            placements.append(Placement(trackIndex: trackIndex, timeRange: timeRange, transitionAfter: item.transitionAfter))

            // Advance cursor: dissolve overlaps with the next clip; fade does not
            cursor = CMTimeAdd(startTime, placedDuration)
            if let outgoing = item.transitionAfter {
                cursor = CMTimeSubtract(cursor, overlap(during: outgoing))
            }
        }

        let totalDuration = placements.last.map { $0.timeRange.end } ?? .zero

        // 4. Build the videoComposition with per-segment instructions
        let videoComposition = buildVideoComposition(
            placements: placements,
            videoTracks: videoTracks,
            preset: preset,
            totalDuration: totalDuration
        )

        // 5. Audio crossfade ramps for clip audio on alternating tracks
        var audioMixParameters = buildClipAudioCrossfadeParams(placements: placements, audioTracks: audioTracksAB)

        // 6. Background audio tracks (same as simple path)
        let bgParams = try await buildBackgroundAudioMixParameters(
            composition: composition,
            audioTracks: audioTracks,
            totalDuration: totalDuration
        )
        audioMixParameters.append(contentsOf: bgParams)

        var audioMix: AVMutableAudioMix?
        if !audioMixParameters.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioMixParameters
            audioMix = mix
        }

        return CompositionResult(composition: composition, audioMix: audioMix, videoComposition: videoComposition)
    }

    // MARK: - Per-transition geometry
    //
    // Each transition contributes three quantities:
    //   - overlap:       how much the next clip is pulled back to overlap with this one
    //   - outgoingTail:  how long the outgoing-side effect lasts (within this clip)
    //   - incomingHead:  how long the incoming-side effect lasts (within the next clip)
    //
    // dissolve: clips overlap by `duration`; outgoingTail == incomingHead == overlap == duration
    // fade:     no overlap; each side gets duration/2 within its own clip; tail/head don't share time

    private static func overlap(during transition: Transition) -> CMTime {
        switch transition {
        case .dissolve(let d):
            return CMTime(seconds: d, preferredTimescale: 600)
        case .fade:
            return .zero
        case .slide(_, let d):
            return CMTime(seconds: d, preferredTimescale: 600)
        }
    }

    private static func outgoingTail(of transition: Transition) -> CMTime {
        switch transition {
        case .dissolve(let d):
            return CMTime(seconds: d, preferredTimescale: 600)
        case .fade(let d):
            return CMTime(seconds: d / 2, preferredTimescale: 600)
        case .slide(_, let d):
            return CMTime(seconds: d, preferredTimescale: 600)
        }
    }

    private static func incomingHead(of transition: Transition) -> CMTime {
        outgoingTail(of: transition)
    }

    // MARK: - Transition planning

    private struct PlannedItem {
        let clip: any Clip
        let transitionAfter: Transition?
    }

    private struct Plan {
        let items: [PlannedItem]
    }

    private struct Placement {
        let trackIndex: Int
        let timeRange: CMTimeRange
        let transitionAfter: Transition?
    }

    private static func planTransitions(clips: [any Clip]) throws -> Plan {
        // Validate: cannot start or end with a transition; cannot have two adjacent transitions
        if clips.first is Transition {
            throw KadrError.invalidTransition("Composition cannot begin with a transition")
        }
        if clips.last is Transition {
            throw KadrError.invalidTransition("Composition cannot end with a transition")
        }

        var items: [PlannedItem] = []
        var i = 0
        while i < clips.count {
            let current = clips[i]
            if current is Transition {
                throw KadrError.invalidTransition("Two transitions cannot be adjacent")
            }

            let next = i + 1 < clips.count ? clips[i + 1] : nil
            if let transition = next as? Transition {
                // All three transition kinds are now implemented.

                guard let following = i + 2 < clips.count ? clips[i + 2] : nil, !(following is Transition) else {
                    throw KadrError.invalidTransition("Transition must sit between two media clips")
                }
                let tDur = CMTimeGetSeconds(transition.duration)
                let curDur = CMTimeGetSeconds(current.duration)
                let nextDur = CMTimeGetSeconds(following.duration)
                if tDur <= 0 {
                    throw KadrError.invalidTransition("Transition duration must be positive")
                }
                // Each side of the transition must fit within its adjacent clip:
                // - dissolve: full duration overlaps both clips (constraint = duration)
                // - fade: each half (duration/2) sits within its clip's tail/head (constraint = duration/2)
                let perSide = CMTimeGetSeconds(outgoingTail(of: transition))
                if perSide > curDur || perSide > nextDur {
                    throw KadrError.invalidTransition("Transition (\(tDur)s) does not fit within adjacent clip durations")
                }

                items.append(PlannedItem(clip: current, transitionAfter: transition))
                i += 2
            } else {
                items.append(PlannedItem(clip: current, transitionAfter: nil))
                i += 1
            }
        }
        return Plan(items: items)
    }

    // MARK: - VideoComposition builder for the transition path

    private static func buildVideoComposition(
        placements: [Placement],
        videoTracks: [AVMutableCompositionTrack],
        preset: Preset,
        totalDuration: CMTime
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = preset.resolution
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))

        var instructions: [AVMutableVideoCompositionInstruction] = []

        for (idx, placement) in placements.enumerated() {
            let track = videoTracks[placement.trackIndex]
            let nextPlacement = idx + 1 < placements.count ? placements[idx + 1] : nil

            // Solo segment: from clip start (+incoming head) to clip end (-outgoing tail)
            let incomingHeadDur: CMTime = {
                guard idx > 0, let incoming = placements[idx - 1].transitionAfter else { return .zero }
                return incomingHead(of: incoming)
            }()
            let outgoingTailDur: CMTime = {
                guard let outgoing = placement.transitionAfter else { return .zero }
                return outgoingTail(of: outgoing)
            }()

            let soloStart = CMTimeAdd(placement.timeRange.start, incomingHeadDur)
            let soloEnd = CMTimeSubtract(placement.timeRange.end, outgoingTailDur)

            if CMTimeCompare(soloEnd, soloStart) > 0 {
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = CMTimeRange(start: soloStart, duration: CMTimeSubtract(soloEnd, soloStart))
                inst.layerInstructions = [makeLayerInstruction(for: track, preset: preset)]
                instructions.append(inst)
            }

            // Outgoing transition segment(s)
            if let outgoing = placement.transitionAfter, let next = nextPlacement {
                let incomingTrack = videoTracks[next.trackIndex]

                switch outgoing {
                case .dissolve:
                    // Single overlapping cross-fade segment
                    let xRange = CMTimeRange(start: soloEnd, duration: outgoing.duration)
                    let inst = AVMutableVideoCompositionInstruction()
                    inst.timeRange = xRange
                    let outLayer = makeLayerInstruction(for: track, preset: preset)
                    outLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: xRange)
                    let inLayer = makeLayerInstruction(for: incomingTrack, preset: preset)
                    inLayer.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: xRange)
                    inst.layerInstructions = [outLayer, inLayer]
                    instructions.append(inst)

                case .fade:
                    // Two non-overlapping segments through black: tail-out, then head-in
                    let halfDur = outgoingTailDur
                    let outRange = CMTimeRange(start: soloEnd, duration: halfDur)
                    let outInst = AVMutableVideoCompositionInstruction()
                    outInst.timeRange = outRange
                    let outLayer = makeLayerInstruction(for: track, preset: preset)
                    outLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: outRange)
                    outInst.layerInstructions = [outLayer]
                    instructions.append(outInst)

                    let inStart = outRange.end  // = next clip's start (no overlap for fade)
                    let inRange = CMTimeRange(start: inStart, duration: halfDur)
                    let inInst = AVMutableVideoCompositionInstruction()
                    inInst.timeRange = inRange
                    let inLayer = makeLayerInstruction(for: incomingTrack, preset: preset)
                    inLayer.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: inRange)
                    inInst.layerInstructions = [inLayer]
                    instructions.append(inInst)

                case .slide(let direction, _):
                    // Single overlapping segment with translation ramps on both layers
                    let xRange = CMTimeRange(start: soloEnd, duration: outgoing.duration)
                    let inst = AVMutableVideoCompositionInstruction()
                    inst.timeRange = xRange

                    let offset = slideOffset(direction: direction, renderSize: preset.resolution)

                    let outBase = baseTransform(for: track, preset: preset) ?? .identity
                    let outEnd = outBase.concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
                    let outLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                    outLayer.setTransformRamp(fromStart: outBase, toEnd: outEnd, timeRange: xRange)

                    let inBase = baseTransform(for: incomingTrack, preset: preset) ?? .identity
                    let inStart = inBase.concatenating(CGAffineTransform(translationX: -offset.x, y: -offset.y))
                    let inLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: incomingTrack)
                    inLayer.setTransformRamp(fromStart: inStart, toEnd: inBase, timeRange: xRange)

                    inst.layerInstructions = [outLayer, inLayer]
                    instructions.append(inst)
                }
            }
        }

        videoComposition.instructions = instructions
        return videoComposition
    }

    private static func makeLayerInstruction(
        for track: AVMutableCompositionTrack,
        preset: Preset
    ) -> AVMutableVideoCompositionLayerInstruction {
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        if let base = baseTransform(for: track, preset: preset) {
            layer.setTransform(base, at: .zero)
        }
        return layer
    }

    /// The aspect-fill scale + center transform applied to every layer before any slide offset.
    private static func baseTransform(
        for track: AVMutableCompositionTrack,
        preset: Preset
    ) -> CGAffineTransform? {
        let trackSize = track.naturalSize
        guard trackSize.width > 0, trackSize.height > 0 else { return nil }
        let scaleX = preset.resolution.width / trackSize.width
        let scaleY = preset.resolution.height / trackSize.height
        let scale = max(scaleX, scaleY)
        let scaledWidth = trackSize.width * scale
        let scaledHeight = trackSize.height * scale
        let tx = (preset.resolution.width - scaledWidth) / 2
        let ty = (preset.resolution.height - scaledHeight) / 2
        return CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: tx / scale, y: ty / scale)
    }

    /// Translation offset (in render space) for the outgoing clip during a slide.
    /// The incoming clip uses the negation of this offset as its starting position.
    private static func slideOffset(
        direction: SlideDirection,
        renderSize: CGSize
    ) -> CGPoint {
        switch direction {
        case .fromLeft:   return CGPoint(x:  renderSize.width, y: 0)   // outgoing exits right
        case .fromRight:  return CGPoint(x: -renderSize.width, y: 0)   // outgoing exits left
        case .fromTop:    return CGPoint(x: 0, y:  renderSize.height)  // outgoing exits down
        case .fromBottom: return CGPoint(x: 0, y: -renderSize.height)  // outgoing exits up
        }
    }

    // MARK: - Audio crossfade for clip audio during transitions

    private static func buildClipAudioCrossfadeParams(
        placements: [Placement],
        audioTracks: [AVMutableCompositionTrack?]
    ) -> [AVMutableAudioMixInputParameters] {
        var params: [AVMutableAudioMixInputParameters] = []
        for (idx, placement) in placements.enumerated() {
            guard let track = audioTracks[placement.trackIndex] else { continue }
            let p = AVMutableAudioMixInputParameters(track: track)

            // Fade in over this clip's head if the previous clip had an outgoing transition
            if idx > 0, let incoming = placements[idx - 1].transitionAfter {
                let inDur = incomingHead(of: incoming)
                let inRange = CMTimeRange(start: placement.timeRange.start, duration: inDur)
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: inRange)
            }

            // Fade out over this clip's tail if it has an outgoing transition
            if let outgoing = placement.transitionAfter {
                let outDur = outgoingTail(of: outgoing)
                let outStart = CMTimeSubtract(placement.timeRange.end, outDur)
                let outRange = CMTimeRange(start: outStart, duration: outDur)
                p.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: outRange)
            }

            params.append(p)
        }
        return params
    }

    // MARK: - Background audio (shared between simple and transition paths)

    private static func buildBackgroundAudioMix(
        composition: AVMutableComposition,
        audioTracks: [AudioTrack],
        totalDuration: CMTime
    ) async throws -> AVMutableAudioMix? {
        let params = try await buildBackgroundAudioMixParameters(
            composition: composition,
            audioTracks: audioTracks,
            totalDuration: totalDuration
        )
        guard !params.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        return mix
    }

    private static func buildBackgroundAudioMixParameters(
        composition: AVMutableComposition,
        audioTracks: [AudioTrack],
        totalDuration: CMTime
    ) async throws -> [AVMutableAudioMixInputParameters] {
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
            let insertDuration = CMTimeMinimum(audioDuration, totalDuration)

            try bgAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: sourceAudioTrack,
                at: .zero
            )

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

        return audioMixParameters
    }

    // MARK: - VideoClip insertion

    private static func insertVideoClip(
        _ clip: VideoClip,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack?,
        at insertionPoint: inout CMTime,
        preset: Preset
    ) async throws {
        var assetURL = clip.url

        if clip.isReversed {
            assetURL = try await ReverseProcessor.reverse(videoAt: assetURL)
        }

        let asset = AVURLAsset(url: assetURL)
        let assetDuration = try await asset.load(.duration)

        let sourceRange: CMTimeRange
        if let trimRange = clip.trimRange {
            let start = CMTime(seconds: trimRange.lowerBound, preferredTimescale: 600)
            let end = CMTime(seconds: trimRange.upperBound, preferredTimescale: 600)
            sourceRange = CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
        } else {
            sourceRange = CMTimeRange(start: .zero, duration: assetDuration)
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let sourceVideoTrack = videoTracks.first {
            try videoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: insertionPoint)
        }

        if !clip.isMuted, let audioTrack {
            let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = sourceAudioTracks.first {
                try audioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: insertionPoint)
            }
        }

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
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack?,
        at insertionPoint: inout CMTime,
        preset: Preset
    ) async throws {
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
