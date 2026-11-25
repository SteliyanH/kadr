import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia

/// A layer instruction's transform and opacity over time, read back so a custom
/// compositor can draw a source the way AVFoundation's built-in compositor would.
///
/// `AVVideoCompositing` hands a custom compositor raw source frames: stored pixels, at
/// their stored size, before any layer instruction has been applied. Everything the
/// engine puts in a layer instruction — the source's orientation, the fill into the
/// render frame, the crop, per-clip transforms and keyframes, opacity and fades — is the
/// custom compositor's job to apply. ``KadrVideoCompositor`` does it with this, before
/// the frames reach a ``MultiInputCompositor``, so a compositor that passes an input
/// straight through draws exactly what the default compositor draws.
///
/// Built once per layer instruction: an animated clip can carry a transform per frame,
/// and walking them again for every frame would be quadratic.
struct LayerGeometry {
    struct Ramp<Value> {
        let start: Value
        let end: Value
        let range: CMTimeRange
    }

    let transforms: [Ramp<CGAffineTransform>]
    let opacities: [Ramp<Float>]

    init(transforms: [Ramp<CGAffineTransform>], opacities: [Ramp<Float>]) {
        self.transforms = transforms
        self.opacities = opacities
    }

    init(_ layer: AVVideoCompositionLayerInstruction) {
        transforms = Self.walk { time in
            var start = CGAffineTransform.identity, end = CGAffineTransform.identity
            var range = CMTimeRange.invalid
            guard layer.getTransformRamp(for: time, start: &start, end: &end, timeRange: &range) else { return nil }
            return Ramp(start: start, end: end, range: range)
        }
        opacities = Self.walk { time in
            var start: Float = 1, end: Float = 1
            var range = CMTimeRange.invalid
            guard layer.getOpacityRamp(for: time, startOpacity: &start, endOpacity: &end, timeRange: &range) else { return nil }
            return Ramp(start: start, end: end, range: range)
        }
    }

    /// Collects every ramp in time order. A query returns the ramp at or after `time`,
    /// and the last one is usually open-ended.
    private static func walk<Value>(_ query: (CMTime) -> Ramp<Value>?) -> [Ramp<Value>] {
        var ramps: [Ramp<Value>] = []
        var time = CMTime.zero
        while ramps.count < 100_000, let ramp = query(time), ramp.range.isValid {
            ramps.append(ramp)
            guard ramp.range.end.isNumeric, CMTimeCompare(ramp.range.end, time) > 0 else { break }
            time = ramp.range.end
        }
        return ramps
    }

    /// The transform at `time`: identity before the first ramp, interpolated inside one,
    /// and the last value held after it.
    func transform(at time: CMTime) -> CGAffineTransform {
        guard let (ramp, fraction) = Self.ramp(in: transforms, at: time) else { return .identity }
        guard fraction > 0 else { return ramp.start }
        guard fraction < 1 else { return ramp.end }
        let (a, b) = (ramp.start, ramp.end)
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * CGFloat(fraction) }
        return CGAffineTransform(
            a: mix(a.a, b.a), b: mix(a.b, b.b), c: mix(a.c, b.c), d: mix(a.d, b.d),
            tx: mix(a.tx, b.tx), ty: mix(a.ty, b.ty)
        )
    }

    /// The opacity at `time`, with the same rules as ``transform(at:)``; fully opaque
    /// before the first ramp.
    func opacity(at time: CMTime) -> Float {
        guard let (ramp, fraction) = Self.ramp(in: opacities, at: time) else { return 1 }
        return ramp.start + (ramp.end - ramp.start) * Float(min(max(fraction, 0), 1))
    }

    /// The last ramp starting at or before `time`, and how far through it `time` is.
    private static func ramp<Value>(in ramps: [Ramp<Value>], at time: CMTime) -> (Ramp<Value>, Double)? {
        // Binary search: ramps are sorted and don't overlap.
        var low = 0, high = ramps.count
        while low < high {
            let mid = (low + high) / 2
            if CMTimeCompare(ramps[mid].range.start, time) <= 0 { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        let ramp = ramps[low - 1]
        let duration = ramp.range.duration
        guard duration.isNumeric, duration.seconds > 0 else { return (ramp, 0) }
        let elapsed = CMTimeSubtract(time, ramp.range.start).seconds
        return (ramp, elapsed / duration.seconds)
    }

    /// `image`, a raw source frame, drawn into a `renderSize` frame at `time`: placed by
    /// the layer's transform, cropped to the frame, faded by its opacity.
    ///
    /// Layer transforms work in top-left-origin coordinates and Core Image in
    /// bottom-left-origin ones, so the transform is conjugated by a flip on each side.
    func place(_ image: CIImage, at time: CMTime, renderSize: CGSize) -> CIImage {
        let sourceHeight = image.extent.maxY
        let toTopDown = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
        let toBottomUp = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderSize.height)
        let transform = toTopDown.concatenating(transform(at: time)).concatenating(toBottomUp)

        var placed = image
            .transformed(by: transform, highQualityDownsample: true)
            .cropped(to: CGRect(origin: .zero, size: renderSize))

        let opacity = opacity(at: time)
        if opacity < 1 {
            placed = placed.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(opacity, 0))),
            ])
        }
        return placed
    }
}
