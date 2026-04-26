import Foundation
import CoreMedia

/// SMPTE-style timecode formatter (`HH:MM:SS:FF`) for converting between `CMTime` and
/// human-readable time strings at a given frame rate.
///
/// ```swift
/// let tc = Timecode(fps: .fps30)
/// tc.format(CMTime(seconds: 65.5, preferredTimescale: 600))   // "00:01:05:15"
/// tc.parse("00:01:05:15")                                     // CMTime(value: 1965, timescale: 30)
/// ```
///
/// Drop-frame timecode (`HH:MM:SS;FF` for 29.97/59.94) is **not** supported in v0.3.0.
/// Non-drop-frame is correct for all integer frame rates and for export presets that
/// target whole-number fps.
public struct Timecode: Sendable {
    /// The frame rate used to convert between `CMTime` and timecode strings.
    public let frameRate: FrameRate

    /// Frame rates supported by ``Timecode``. Use `.custom(_:)` for non-standard integer rates.
    public enum FrameRate: Sendable, Equatable {
        case fps24
        case fps25
        case fps30
        case fps50
        case fps60
        /// Custom integer frame rate. Drop-frame is not handled.
        case custom(Int)

        /// The integer frames-per-second value backing this rate.
        public var fps: Int {
            switch self {
            case .fps24:        return 24
            case .fps25:        return 25
            case .fps30:        return 30
            case .fps50:        return 50
            case .fps60:        return 60
            case .custom(let n): return n
            }
        }
    }

    /// Build a timecode formatter for the given frame rate.
    public init(fps: FrameRate) {
        self.frameRate = fps
    }

    /// Convert a `CMTime` to a SMPTE timecode string in `HH:MM:SS:FF` form.
    ///
    /// Negative times are clamped to `00:00:00:00`.
    public func format(_ time: CMTime) -> String {
        let seconds = max(0, CMTimeGetSeconds(time))
        let totalFrames = Int((seconds * Double(frameRate.fps)).rounded())
        let frames = totalFrames % frameRate.fps
        let totalSeconds = totalFrames / frameRate.fps
        let secs = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let mins = totalMinutes % 60
        let hours = totalMinutes / 60
        return String(format: "%02d:%02d:%02d:%02d", hours, mins, secs, frames)
    }

    /// Parse a SMPTE timecode string (`HH:MM:SS:FF`) into a `CMTime` at this timecode's
    /// frame rate. Returns `nil` if the string is malformed or any component is out of range.
    public func parse(_ string: String) -> CMTime? {
        let parts = string.split(separator: ":")
        guard parts.count == 4 else { return nil }
        guard
            let h = Int(parts[0]), h >= 0,
            let m = Int(parts[1]), m >= 0, m < 60,
            let s = Int(parts[2]), s >= 0, s < 60,
            let f = Int(parts[3]), f >= 0, f < frameRate.fps
        else {
            return nil
        }
        let totalFrames = h * 3600 * frameRate.fps + m * 60 * frameRate.fps + s * frameRate.fps + f
        return CMTime(value: Int64(totalFrames), timescale: Int32(frameRate.fps))
    }
}
