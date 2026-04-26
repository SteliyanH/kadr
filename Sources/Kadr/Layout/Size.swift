import Foundation
import CoreGraphics

/// A size in render space. Like ``Position``, defaults to a resolution-independent form
/// so overlays you size at one preset render correctly at others.
///
/// ```swift
/// .size(.normalized(width: 0.4, height: 0.1))   // 40% wide, 10% tall
/// .size(.percent(width: 40, height: 10))        // same, percent-flavored
/// .size(.pixels(width: 480, height: 100))       // exact pixels
/// .size(.aspectFit(.normalized(width: 0.4, height: 0.4)))
///                                               // largest size that fits in 40%×40%
///                                               // while preserving the source aspect
/// ```
public indirect enum Size: Sendable, Equatable {
    /// Resolution-independent size. `0...1` in each axis (width / render width, height / render height).
    case normalized(width: Double, height: Double)

    /// Size in render-space pixels.
    case pixels(width: Double, height: Double)

    /// Resolution-independent size in `0...100`.
    case percent(width: Double, height: Double)

    /// Largest size that fits inside the given bounding ``Size`` while preserving the
    /// source's natural aspect ratio. The source's aspect ratio is supplied by the caller
    /// (e.g. an overlay image's pixel dimensions).
    case aspectFit(within: Size, sourceAspect: CGFloat)

    /// Smallest size that fully covers the given bounding ``Size`` while preserving the
    /// source's natural aspect ratio.
    case aspectFill(covering: Size, sourceAspect: CGFloat)

    // MARK: - Resolution

    /// Resolve to a render-space pixel size given the export's render size.
    internal func resolved(in renderSize: CGSize) -> CGSize {
        switch self {
        case .normalized(let w, let h):
            return CGSize(width: w * renderSize.width, height: h * renderSize.height)
        case .pixels(let w, let h):
            return CGSize(width: w, height: h)
        case .percent(let w, let h):
            return CGSize(width: (w / 100.0) * renderSize.width, height: (h / 100.0) * renderSize.height)
        case .aspectFit(let bounds, let sourceAspect):
            let b = bounds.resolved(in: renderSize)
            let boundsAspect = b.width / b.height
            if sourceAspect > boundsAspect {
                // Source is wider than bounds — fit to bounds width
                return CGSize(width: b.width, height: b.width / sourceAspect)
            } else {
                // Source is taller — fit to bounds height
                return CGSize(width: b.height * sourceAspect, height: b.height)
            }
        case .aspectFill(let bounds, let sourceAspect):
            let b = bounds.resolved(in: renderSize)
            let boundsAspect = b.width / b.height
            if sourceAspect > boundsAspect {
                // Source is wider — fill to bounds height
                return CGSize(width: b.height * sourceAspect, height: b.height)
            } else {
                return CGSize(width: b.width, height: b.width / sourceAspect)
            }
        }
    }
}
