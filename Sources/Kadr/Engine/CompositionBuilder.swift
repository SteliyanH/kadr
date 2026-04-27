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
        preset: Preset,
        cropRect: CGRect? = nil
    ) async throws -> CompositionResult {
        // Multi-track path engages whenever any clip has an explicit startTime or is a Track —
        // both shapes of the v0.6 hybrid DSL produce parallel sub-timelines.
        let isMultiTrack = clips.contains { $0.startTime != nil || $0 is Track }
        if isMultiTrack {
            return try await buildMultiTrack(clips: clips, audioTracks: audioTracks, preset: preset, cropRect: cropRect)
        }
        if clips.contains(where: { $0 is Transition }) {
            return try await buildWithTransitions(clips: clips, audioTracks: audioTracks, preset: preset, cropRect: cropRect)
        }
        return try await buildSimple(clips: clips, audioTracks: audioTracks, preset: preset)
    }

    // MARK: - Multi-track path (v0.6 Tier 4a)
    //
    // Lays out parallel video tracks for free-floating clips and Track {} blocks
    // alongside the implicit-chain main track. AVFoundation's default compositor handles
    // alpha-composite later-over-earlier — the v0.5 Compositor protocol's multi-input
    // counterpart (Video.multiInputCompositor) is not yet engaged in 4a; that requires
    // a custom AVVideoCompositing implementation and ships in Tier 4b.
    //
    // Restrictions surfaced as KadrError.notYetImplemented so users see a clear error
    // instead of silently-wrong output:
    //   - Transitions in the implicit chain when multi-track is active (the chain
    //     would need the alternating-tracks transition machinery, which is non-trivial
    //     to merge with multi-track parallel tracks).
    //   - Transitions inside a Track { } block.
    //   - Nested Track { }.

    private static func buildMultiTrack(
        clips: [any Clip],
        audioTracks: [AudioTrack],
        preset: Preset,
        cropRect: CGRect? = nil
    ) async throws -> CompositionResult {
        let composition = AVMutableComposition()
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        // Per-piece video tracks, in declaration order. Used for layer instructions
        // below — earlier layer instruction = lower (background); later = on top.
        var videoTracks: [AVMutableCompositionTrack] = []
        var clipAudioRanges: [CMTimeRange] = []
        var totalDuration: CMTime = .zero

        // 1. Implicit-chain clips → main video track at t=0
        let chained = clips.filter { $0.startTime == nil && !($0 is Track) }
        if !chained.isEmpty {
            // 4a restriction: no transitions in the chain alongside multi-track
            if chained.contains(where: { $0 is Transition }) {
                throw KadrError.notYetImplemented(
                    "Transitions in the implicit chain alongside multi-track parallel clips. " +
                    "Workaround: place the chain inside a Track {} block, or land Tier 4b which adds support."
                )
            }
            guard let mainTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create main video track"]))
            }
            videoTracks.append(mainTrack)
            var insertion: CMTime = .zero
            for clip in chained {
                let beforeIP = insertion
                let contributesAudio = try await insertChainClip(
                    clip,
                    videoTrack: mainTrack,
                    audioTrack: compositionAudioTrack,
                    at: &insertion,
                    preset: preset
                )
                if contributesAudio {
                    clipAudioRanges.append(CMTimeRange(start: beforeIP, duration: CMTimeSubtract(insertion, beforeIP)))
                }
            }
            totalDuration = CMTimeMaximum(totalDuration, insertion)
        }

        // 2. Free-floating clips and Tracks → each gets its own parallel video track
        for clip in clips where clip.startTime != nil || clip is Track {
            guard let parallelTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw KadrError.exportFailed(underlying: NSError(domain: "Kadr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create parallel video track"]))
            }
            videoTracks.append(parallelTrack)

            // Track {}'s startTime is always non-nil (the type's invariant). Free-floating
            // single clips also have non-nil startTime here (filtered by the where clause).
            var insertion = clip.startTime ?? .zero

            if let track = clip as? Track {
                for innerClip in track.clips {
                    if innerClip is Transition {
                        throw KadrError.notYetImplemented(
                            "Transitions inside a Track {} block (v0.6 Tier 4a). Tier 4b adds support."
                        )
                    }
                    if innerClip is Track {
                        throw KadrError.notYetImplemented(
                            "Nested Track {} blocks (v0.6 Tier 4a). Tier 4b adds support."
                        )
                    }
                    let beforeIP = insertion
                    let contributesAudio = try await insertChainClip(
                        innerClip,
                        videoTrack: parallelTrack,
                        audioTrack: compositionAudioTrack,
                        at: &insertion,
                        preset: preset
                    )
                    if contributesAudio {
                        clipAudioRanges.append(CMTimeRange(start: beforeIP, duration: CMTimeSubtract(insertion, beforeIP)))
                    }
                }
            } else {
                let beforeIP = insertion
                let contributesAudio = try await insertChainClip(
                    clip,
                    videoTrack: parallelTrack,
                    audioTrack: compositionAudioTrack,
                    at: &insertion,
                    preset: preset
                )
                if contributesAudio {
                    clipAudioRanges.append(CMTimeRange(start: beforeIP, duration: CMTimeSubtract(insertion, beforeIP)))
                }
            }

            totalDuration = CMTimeMaximum(totalDuration, insertion)
        }

        // 3. Build the videoComposition with layer instructions for every track. One
        // instruction spans 0..totalDuration; layer instructions in declaration order so
        // AVFoundation's default compositor renders later tracks over earlier ones.
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = cropRect?.size ?? preset.resolution
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))

        let cropOffset = cropRect?.origin ?? .zero
        let cropTransform = CGAffineTransform(translationX: -cropOffset.x, y: -cropOffset.y)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        instruction.layerInstructions = videoTracks.map { track in
            makeLayerInstruction(for: track, preset: preset, cropTransform: cropTransform)
        }
        videoComposition.instructions = [instruction]

        // 4. Audio mix from background music — same pipeline as buildSimple/Transitions.
        let audioMix = try await buildBackgroundAudioMix(
            composition: composition,
            audioTracks: audioTracks,
            totalDuration: totalDuration,
            clipAudioRanges: clipAudioRanges
        )

        return CompositionResult(composition: composition, audioMix: audioMix, videoComposition: videoComposition)
    }

    /// Insert a single non-transition clip on the given video / audio tracks. Wraps
    /// the per-type ``insertVideoClip`` / ``insertImageClip`` / TitleSequence rendering
    /// in a single uniform call. Returns whether the clip contributes any clip audio.
    private static func insertChainClip(
        _ clip: any Clip,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack?,
        at insertionPoint: inout CMTime,
        preset: Preset
    ) async throws -> Bool {
        if let videoClip = clip as? VideoClip {
            try await insertVideoClip(videoClip, videoTrack: videoTrack, audioTrack: audioTrack, at: &insertionPoint, preset: preset)
            return !videoClip.isMuted || videoClip.replacementAudioURL != nil
        }
        if let imageClip = clip as? ImageClip {
            try await insertImageClip(imageClip, videoTrack: videoTrack, audioTrack: audioTrack, at: &insertionPoint, preset: preset)
            return imageClip.audioURL != nil
        }
        if let title = clip as? TitleSequence {
            let titleImage = title.render(at: preset.resolution)
            let imageClip = ImageClip(titleImage, duration: title.duration)
            try await insertImageClip(imageClip, videoTrack: videoTrack, audioTrack: audioTrack, at: &insertionPoint, preset: preset)
            return false
        }
        return false
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

        var clipAudioRanges: [CMTimeRange] = []

        for clip in clips {
            let beforeIP = insertionPoint
            if let videoClip = clip as? VideoClip {
                try await insertVideoClip(
                    videoClip,
                    videoTrack: compositionVideoTrack,
                    audioTrack: compositionAudioTrack,
                    at: &insertionPoint,
                    preset: preset
                )
                if !videoClip.isMuted || videoClip.replacementAudioURL != nil {
                    clipAudioRanges.append(CMTimeRange(start: beforeIP, duration: CMTimeSubtract(insertionPoint, beforeIP)))
                }
            } else if let imageClip = clip as? ImageClip {
                try await insertImageClip(
                    imageClip,
                    videoTrack: compositionVideoTrack,
                    audioTrack: compositionAudioTrack,
                    at: &insertionPoint,
                    preset: preset
                )
                if imageClip.audioURL != nil {
                    clipAudioRanges.append(CMTimeRange(start: beforeIP, duration: CMTimeSubtract(insertionPoint, beforeIP)))
                }
            } else if let title = clip as? TitleSequence {
                // Render the title to a PlatformImage at the export's render size, then
                // dispatch via the existing ImageClip insertion path.
                let titleImage = title.render(at: preset.resolution)
                let imageClip = ImageClip(titleImage, duration: title.duration)
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
            totalDuration: insertionPoint,
            clipAudioRanges: clipAudioRanges
        )

        return CompositionResult(composition: composition, audioMix: audioMix, videoComposition: nil)
    }

    // MARK: - Transition path (alternating tracks + custom videoComposition)

    private static func buildWithTransitions(
        clips: [any Clip],
        audioTracks: [AudioTrack],
        preset: Preset,
        cropRect: CGRect? = nil
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

        var clipAudioRanges: [CMTimeRange] = []

        for (index, item) in plan.items.enumerated() {
            let trackIndex = index % 2
            let videoTrack = videoTracks[trackIndex]
            let audioTrack = audioTracksAB[trackIndex]

            let startTime = cursor
            var insertionPoint = startTime

            let durationBefore = insertionPoint
            var contributesAudio = false
            if let videoClip = item.clip as? VideoClip {
                try await insertVideoClip(videoClip, videoTrack: videoTrack, audioTrack: audioTrack, at: &insertionPoint, preset: preset)
                contributesAudio = !videoClip.isMuted || videoClip.replacementAudioURL != nil
            } else if let imageClip = item.clip as? ImageClip {
                try await insertImageClip(imageClip, videoTrack: videoTrack, audioTrack: audioTrack, at: &insertionPoint, preset: preset)
                contributesAudio = imageClip.audioURL != nil
            } else if let title = item.clip as? TitleSequence {
                let titleImage = title.render(at: preset.resolution)
                let imageClip = ImageClip(titleImage, duration: title.duration)
                try await insertImageClip(imageClip, videoTrack: videoTrack, audioTrack: audioTrack, at: &insertionPoint, preset: preset)
            }
            let placedDuration = CMTimeSubtract(insertionPoint, durationBefore)
            let timeRange = CMTimeRange(start: startTime, duration: placedDuration)
            placements.append(Placement(trackIndex: trackIndex, timeRange: timeRange, transitionAfter: item.transitionAfter))
            if contributesAudio {
                clipAudioRanges.append(timeRange)
            }

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
            totalDuration: totalDuration,
            cropRect: cropRect
        )

        // 5. Audio crossfade ramps for clip audio on alternating tracks
        var audioMixParameters = buildClipAudioCrossfadeParams(placements: placements, audioTracks: audioTracksAB)

        // 6. Background audio tracks (same as simple path)
        let bgParams = try await buildBackgroundAudioMixParameters(
            composition: composition,
            audioTracks: audioTracks,
            totalDuration: totalDuration,
            clipAudioRanges: clipAudioRanges
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
        case .dissolve(let d): return d
        case .fade:            return .zero
        case .slide(_, let d): return d
        }
    }

    private static func outgoingTail(of transition: Transition) -> CMTime {
        switch transition {
        case .dissolve(let d): return d
        case .fade(let d):     return CMTimeMultiplyByRatio(d, multiplier: 1, divisor: 2)
        case .slide(_, let d): return d
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
                if CMTimeCompare(transition.duration, .zero) <= 0 {
                    throw KadrError.invalidTransition("Transition duration must be positive")
                }
                // VideoClip without a trim has duration .zero synchronously (the asset isn't
                // loaded yet) — give a specific error explaining the fix.
                if CMTimeCompare(current.duration, .zero) <= 0 || CMTimeCompare(following.duration, .zero) <= 0 {
                    throw KadrError.invalidTransition(
                        "Transition placement requires both adjacent clips to have a known duration. " +
                        "VideoClip without a trim reports duration .zero synchronously — call .trimmed(to:) to set one."
                    )
                }

                // Each side of the transition must fit within its adjacent clip:
                // - dissolve: full duration overlaps both clips (constraint = duration)
                // - fade: each half (duration/2) sits within its clip's tail/head (constraint = duration/2)
                let perSide = outgoingTail(of: transition)
                if CMTimeCompare(perSide, current.duration) > 0 || CMTimeCompare(perSide, following.duration) > 0 {
                    let tSec = CMTimeGetSeconds(transition.duration)
                    throw KadrError.invalidTransition("Transition (\(tSec)s) does not fit within adjacent clip durations")
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
        totalDuration: CMTime,
        cropRect: CGRect? = nil
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = cropRect?.size ?? preset.resolution
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))
        let cropOffset = cropRect?.origin ?? .zero
        let cropTransform = CGAffineTransform(translationX: -cropOffset.x, y: -cropOffset.y)

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
                inst.layerInstructions = [makeLayerInstruction(for: track, preset: preset, cropTransform: cropTransform)]
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
                    let outLayer = makeLayerInstruction(for: track, preset: preset, cropTransform: cropTransform)
                    outLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: xRange)
                    let inLayer = makeLayerInstruction(for: incomingTrack, preset: preset, cropTransform: cropTransform)
                    inLayer.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: xRange)
                    inst.layerInstructions = [outLayer, inLayer]
                    instructions.append(inst)

                case .fade:
                    // Two non-overlapping segments through black: tail-out, then head-in
                    let halfDur = outgoingTailDur
                    let outRange = CMTimeRange(start: soloEnd, duration: halfDur)
                    let outInst = AVMutableVideoCompositionInstruction()
                    outInst.timeRange = outRange
                    let outLayer = makeLayerInstruction(for: track, preset: preset, cropTransform: cropTransform)
                    outLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: outRange)
                    outInst.layerInstructions = [outLayer]
                    instructions.append(outInst)

                    let inStart = outRange.end  // = next clip's start (no overlap for fade)
                    let inRange = CMTimeRange(start: inStart, duration: halfDur)
                    let inInst = AVMutableVideoCompositionInstruction()
                    inInst.timeRange = inRange
                    let inLayer = makeLayerInstruction(for: incomingTrack, preset: preset, cropTransform: cropTransform)
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
                    outLayer.setTransformRamp(
                        fromStart: outBase.concatenating(cropTransform),
                        toEnd:     outEnd.concatenating(cropTransform),
                        timeRange: xRange
                    )

                    let inBase = baseTransform(for: incomingTrack, preset: preset) ?? .identity
                    let inStart = inBase.concatenating(CGAffineTransform(translationX: -offset.x, y: -offset.y))
                    let inLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: incomingTrack)
                    inLayer.setTransformRamp(
                        fromStart: inStart.concatenating(cropTransform),
                        toEnd:     inBase.concatenating(cropTransform),
                        timeRange: xRange
                    )

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
        preset: Preset,
        cropTransform: CGAffineTransform = .identity
    ) -> AVMutableVideoCompositionLayerInstruction {
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        if let base = baseTransform(for: track, preset: preset) {
            layer.setTransform(base.concatenating(cropTransform), at: .zero)
        } else if cropTransform != .identity {
            // No base transform but we still need to apply the crop offset
            layer.setTransform(cropTransform, at: .zero)
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
        totalDuration: CMTime,
        clipAudioRanges: [CMTimeRange] = []
    ) async throws -> AVMutableAudioMix? {
        let params = try await buildBackgroundAudioMixParameters(
            composition: composition,
            audioTracks: audioTracks,
            totalDuration: totalDuration,
            clipAudioRanges: clipAudioRanges
        )
        guard !params.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        return mix
    }

    private static func buildBackgroundAudioMixParameters(
        composition: AVMutableComposition,
        audioTracks: [AudioTrack],
        totalDuration: CMTime,
        clipAudioRanges: [CMTimeRange] = []
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

            if CMTimeCompare(audioTrack.fadeInDuration, .zero) > 0 {
                params.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: Float(audioTrack.volumeLevel),
                    timeRange: CMTimeRange(start: .zero, duration: audioTrack.fadeInDuration)
                )
            }

            if CMTimeCompare(audioTrack.fadeOutDuration, .zero) > 0 {
                let fadeStart = CMTimeSubtract(insertDuration, audioTrack.fadeOutDuration)
                params.setVolumeRamp(
                    fromStartVolume: Float(audioTrack.volumeLevel),
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: fadeStart, duration: audioTrack.fadeOutDuration)
                )
            }

            if let duckLevel = audioTrack.duckingLevel {
                guard duckLevel >= 0 && duckLevel <= 1 else {
                    throw KadrError.invalidDuckingLevel(duckLevel)
                }
                // Compute the time ranges already occupied by fade ramps so we can skip
                // overlapping ducking ramps. AVMutableScheduledAudioParameters throws
                // an exception if two ramps overlap, so explicit avoidance is required.
                var fadeRanges: [CMTimeRange] = []
                if CMTimeCompare(audioTrack.fadeInDuration, .zero) > 0 {
                    fadeRanges.append(CMTimeRange(start: .zero, duration: audioTrack.fadeInDuration))
                }
                if CMTimeCompare(audioTrack.fadeOutDuration, .zero) > 0 {
                    let fadeStart = CMTimeSubtract(insertDuration, audioTrack.fadeOutDuration)
                    fadeRanges.append(CMTimeRange(start: fadeStart, duration: audioTrack.fadeOutDuration))
                }
                applyDucking(
                    on: params,
                    baseVolume: audioTrack.volumeLevel,
                    duckLevel: duckLevel,
                    over: clipAudioRanges,
                    excluding: fadeRanges
                )
            }

            audioMixParameters.append(params)
        }

        return audioMixParameters
    }

    /// Apply per-range ducking ramps on a music track's audio mix parameters.
    /// At each clip-audio range, fades the music down from `baseVolume` to `baseVolume * duckLevel`
    /// over a short window at the start, then back up at the end.
    ///
    /// Ducking ramps that overlap any range in `excluding` (typically the fade-in/fade-out
    /// ranges) are skipped — AVFoundation's audio mix parameters reject overlapping ramps.
    private static func applyDucking(
        on params: AVMutableAudioMixInputParameters,
        baseVolume: Double,
        duckLevel: Double,
        over ranges: [CMTimeRange],
        excluding excludedRanges: [CMTimeRange] = []
    ) {
        let rampDuration = CMTime(seconds: 0.1, preferredTimescale: 600)
        let baseFloat = Float(baseVolume)
        let duckedFloat = Float(baseVolume * duckLevel)

        func overlapsAnyExcluded(_ range: CMTimeRange) -> Bool {
            for excluded in excludedRanges {
                if CMTimeRangeGetIntersection(range, otherRange: excluded).duration > .zero {
                    return true
                }
            }
            return false
        }

        for range in ranges {
            // Skip ranges shorter than 2× ramp (no useful duck window)
            if CMTimeCompare(range.duration, CMTimeMultiplyByFloat64(rampDuration, multiplier: 2.0)) <= 0 {
                continue
            }
            // Ramp down at the start
            let downRange = CMTimeRange(start: range.start, duration: rampDuration)
            if !overlapsAnyExcluded(downRange) {
                params.setVolumeRamp(
                    fromStartVolume: baseFloat,
                    toEndVolume: duckedFloat,
                    timeRange: downRange
                )
            }
            // Ramp up at the end
            let upStart = CMTimeSubtract(range.end, rampDuration)
            let upRange = CMTimeRange(start: upStart, duration: rampDuration)
            if !overlapsAnyExcluded(upRange) {
                params.setVolumeRamp(
                    fromStartVolume: duckedFloat,
                    toEndVolume: baseFloat,
                    timeRange: upRange
                )
            }
        }
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

        // Filters and compositors pre-render to a temporary file before composition.
        // Order: reverse first (so filters/compositors operate on the reversed frames),
        // then filters, then compositors. Filters and compositors run in the same
        // applyingCIFiltersWithHandler pass — one extra encode/decode total.
        if !clip.filters.isEmpty || !clip.compositors.isEmpty {
            assetURL = try await FilterProcessor.apply(
                filters: clip.filters,
                compositors: clip.compositors,
                to: assetURL
            )
        }

        let asset = AVURLAsset(url: assetURL)
        let assetDuration = try await asset.load(.duration)

        let sourceRange: CMTimeRange
        if let trimRange = clip.trimRange {
            sourceRange = trimRange
        } else {
            sourceRange = CMTimeRange(start: .zero, duration: assetDuration)
        }

        if clip.speedRate != 1.0 && (clip.speedRate < 0.25 || clip.speedRate > 4.0) {
            throw KadrError.invalidSpeed(clip.speedRate)
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

        // Apply speed: scale the just-inserted segment to its target duration.
        // scaleTimeRange on a track preserves the inserted media but changes its playback rate.
        let advance: CMTime
        if clip.speedRate != 1.0 {
            // Scale by 1/rate. Speed is a Double ratio so this single CMTime → Float64 multiply
            // is unavoidable; everything around it stays exact.
            let targetDuration = CMTimeMultiplyByFloat64(sourceRange.duration, multiplier: 1.0 / clip.speedRate)
            let insertedRange = CMTimeRange(start: insertionPoint, duration: sourceRange.duration)
            videoTrack.scaleTimeRange(insertedRange, toDuration: targetDuration)
            audioTrack?.scaleTimeRange(insertedRange, toDuration: targetDuration)
            advance = targetDuration
        } else {
            advance = sourceRange.duration
        }

        insertionPoint = CMTimeAdd(insertionPoint, advance)
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
