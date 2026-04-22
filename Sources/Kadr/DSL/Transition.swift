import Foundation
import CoreMedia

public enum SlideDirection: Sendable {
    case fromLeft, fromRight, fromTop, fromBottom
}

public enum Transition: Clip, Sendable {
    case fade(duration: TimeInterval)
    case slide(direction: SlideDirection, duration: TimeInterval)
    case dissolve(duration: TimeInterval)

    public var duration: CMTime {
        switch self {
        case .fade(let duration):
            return CMTime(seconds: duration, preferredTimescale: 600)
        case .slide(_, let duration):
            return CMTime(seconds: duration, preferredTimescale: 600)
        case .dissolve(let duration):
            return CMTime(seconds: duration, preferredTimescale: 600)
        }
    }
}
