import AVFoundation
import CoreGraphics
import CoreMedia

/// How one source video track is meant to be shown.
///
/// Cameras store a portrait recording as landscape pixels plus a `preferredTransform`
/// that rotates it upright (and the front camera may add a mirror). A layer instruction's
/// transform replaces that `preferredTransform`, so the engine has to apply it itself.
struct SourceOrientation: Equatable, Sendable {
    /// Maps the stored frame (origin zero, `naturalSize`) to the upright frame, also
    /// with its origin at zero.
    let transform: CGAffineTransform
    /// The upright frame's size: `naturalSize` with width and height swapped for a
    /// quarter turn.
    let displaySize: CGSize

    init(preferredTransform: CGAffineTransform, naturalSize: CGSize) {
        // `preferredTransform` rotates about the origin, which moves the frame into
        // negative coordinates; the translation brings it back. Some writers bake that
        // translation in already, in which case `rect` starts at zero and this is a no-op.
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        self.transform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
        )
        self.displaySize = CGSize(width: rect.width, height: rect.height)
    }

    /// The transform placing this source in a `renderSize` frame: upright first, then
    /// scaled to fill and centered. `nil` for a degenerate size.
    func fill(_ renderSize: CGSize) -> CGAffineTransform? {
        guard let fill = OrientationSchedule.aspectFill(displaySize, into: renderSize) else { return nil }
        return transform.concatenating(fill)
    }
}

/// Which source orientation is on screen on each composition video track, over time.
///
/// Built from the composition's own segments after every clip has been inserted, so
/// every build path gets it the same way: each segment records the file and track it
/// came from. Clips on one composition track can disagree (a portrait clip followed by
/// a landscape one), so lookups are by time, not by track.
struct OrientationSchedule: Sendable {
    struct Entry: Sendable {
        let range: CMTimeRange
        let orientation: SourceOrientation
    }

    static let empty = OrientationSchedule(entries: [:])

    private let entriesByTrack: [CMPersistentTrackID: [Entry]]

    private init(entries: [CMPersistentTrackID: [Entry]]) {
        self.entriesByTrack = entries
    }

    /// Entries for one composition track, in time order.
    func entries(for trackID: CMPersistentTrackID) -> [Entry] {
        entriesByTrack[trackID] ?? []
    }

    /// True when every source is stored upright, which is what the engine assumed
    /// before orientation was read.
    var isAllUpright: Bool {
        entriesByTrack.values.allSatisfy { entries in
            entries.allSatisfy { $0.orientation.transform == .identity }
        }
    }

    /// The orientation showing at `time`: the segment containing it, else the last one
    /// that started before it, else the first.
    func orientation(for trackID: CMPersistentTrackID, at time: CMTime) -> SourceOrientation? {
        let entries = entries(for: trackID)
        if let hit = entries.first(where: { $0.range.containsTime(time) }) {
            return hit.orientation
        }
        let before = entries.last { CMTimeCompare($0.range.start, time) <= 0 }
        return (before ?? entries.first)?.orientation
    }

    /// Reads the orientation of every source behind `composition`'s video tracks.
    ///
    /// A source that can't be read (a file that has gone away) is treated as upright,
    /// which matches the engine's behaviour before orientation existed.
    static func load(for composition: AVComposition) async -> OrientationSchedule {
        struct Source: Hashable, Sendable {
            let url: URL
            let trackID: CMPersistentTrackID
        }
        struct Placed: Sendable {
            let compositionTrack: CMPersistentTrackID
            let range: CMTimeRange
            let source: Source
        }

        var placed: [Placed] = []
        for track in composition.tracks(withMediaType: .video) {
            for segment in track.segments where !segment.isEmpty {
                guard let url = segment.sourceURL else { continue }
                placed.append(Placed(
                    compositionTrack: track.trackID,
                    range: segment.timeMapping.target,
                    source: Source(url: url, trackID: segment.sourceTrackID)
                ))
            }
        }

        var cache: [Source: SourceOrientation] = [:]
        var entries: [CMPersistentTrackID: [Entry]] = [:]
        for item in placed {
            let orientation: SourceOrientation
            if let cached = cache[item.source] {
                orientation = cached
            } else {
                orientation = await read(item.source.url, trackID: item.source.trackID)
                cache[item.source] = orientation
            }
            entries[item.compositionTrack, default: []].append(Entry(range: item.range, orientation: orientation))
        }
        for key in entries.keys {
            entries[key]?.sort { CMTimeCompare($0.range.start, $1.range.start) < 0 }
        }
        return OrientationSchedule(entries: entries)
    }

    private static func read(_ url: URL, trackID: CMPersistentTrackID) async -> SourceOrientation {
        let asset = AVURLAsset(url: url)
        guard
            let track = try? await asset.loadTrack(withTrackID: trackID),
            let (transform, size) = try? await track.load(.preferredTransform, .naturalSize)
        else {
            return SourceOrientation(preferredTransform: .identity, naturalSize: .zero)
        }
        return SourceOrientation(preferredTransform: transform, naturalSize: size)
    }

    /// Scale `size` to fill `renderSize` and center it. `nil` for a degenerate size.
    static func aspectFill(_ size: CGSize, into renderSize: CGSize) -> CGAffineTransform? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = max(renderSize.width / size.width, renderSize.height / size.height)
        let tx = (renderSize.width - size.width * scale) / 2
        let ty = (renderSize.height - size.height * scale) / 2
        return CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: tx / scale, y: ty / scale)
    }
}

/// Transforms for one layer instruction, collected first and emitted in time order.
///
/// Two sources set transforms on the same layer: the base layout of each piece of
/// media, and per-clip transforms and keyframes. Setting both at the same instant would
/// leave the result up to call order, so a later `set` at an equal time replaces an
/// earlier one.
struct LayerTransformTimeline {
    private var points: [(time: CMTime, transform: CGAffineTransform)] = []

    mutating func set(_ transform: CGAffineTransform, at time: CMTime) {
        if let index = points.firstIndex(where: { CMTimeCompare($0.time, time) == 0 }) {
            points[index].transform = transform
        } else {
            points.append((time, transform))
        }
    }

    func apply(to layer: AVMutableVideoCompositionLayerInstruction) {
        for point in points.sorted(by: { CMTimeCompare($0.time, $1.time) < 0 }) {
            layer.setTransform(point.transform, at: point.time)
        }
    }
}
