import Foundation
import CoreGraphics

/// The reference point on an overlay used when positioning it.
///
/// `.center` (default) means a `Position` refers to where the overlay's center lands.
/// `.topLeft` means the same `Position` refers to where the overlay's top-left corner lands.
///
/// ```swift
/// // Place the top-left of the overlay at (10px, 10px):
/// .position(.pixels(x: 10, y: 10))
/// .anchor(.topLeft)
///
/// // Place the bottom-right of the overlay at the bottom-right of the render area:
/// .position(.bottomRight)
/// .anchor(.bottomRight)
/// ```
public enum Anchor: Sendable, Equatable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    /// Anchor as a normalized offset from the overlay's top-left corner. Multiplied by
    /// the overlay's resolved size to produce the pixel offset.
    internal var normalizedOffset: CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: 0,   y: 0)
        case .top:         return CGPoint(x: 0.5, y: 0)
        case .topRight:    return CGPoint(x: 1,   y: 0)
        case .left:        return CGPoint(x: 0,   y: 0.5)
        case .center:      return CGPoint(x: 0.5, y: 0.5)
        case .right:       return CGPoint(x: 1,   y: 0.5)
        case .bottomLeft:  return CGPoint(x: 0,   y: 1)
        case .bottom:      return CGPoint(x: 0.5, y: 1)
        case .bottomRight: return CGPoint(x: 1,   y: 1)
        }
    }
}
