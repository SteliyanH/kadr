import Foundation
import CoreMedia

/// How hard the encoder should work, independent of resolution and frame rate.
///
/// ``Preset`` decides *what shape* the output is — dimensions, frame rate, codec.
/// This decides *how many bits* are spent on it. The two are orthogonal: a 1080×1920
/// reel can be a 12 MB upload or a 60 MB master.
///
/// Added in v0.20.
public enum ExportQuality: Sendable, Equatable {

    /// Encoder default for the codec and resolution. What every export did before
    /// v0.20, and what still happens when nothing is set.
    case automatic

    /// A target average bitrate in bits per second.
    ///
    /// ```swift
    /// video.quality(.bitrate(4_000_000))   // ~4 Mbps
    /// ```
    ///
    /// The encoder treats this as an average, not a ceiling — a complex scene may
    /// exceed it briefly. For a hard limit on the file, use ``fileSize(bytes:)``.
    case bitrate(Int)

    /// Solve for a bitrate that lands the whole export near `bytes`.
    ///
    /// The arithmetic is deliberately visible rather than hidden in the engine:
    /// bits available = `bytes × 8`, minus the audio allowance, divided by the
    /// duration. Whether the result is achievable depends on the content — this is a
    /// target, not a guarantee, and ``resolvedBitrate(forDuration:)`` is where the
    /// assumption lives.
    ///
    /// ```swift
    /// video.quality(.fileSize(bytes: 25 * 1_000_000))   // "under 25 MB, please"
    /// ```
    case fileSize(bytes: Int)

    /// Audio is assumed to occupy this much of the budget when solving a file-size
    /// target. 128 kbps is AAC stereo at a quality nobody complains about, and
    /// over-reserving costs less than under-reserving: too little video bitrate
    /// looks bad, too little audio bitrate is unlistenable.
    public static let assumedAudioBitrate = 128_000

    /// The video bitrate this quality implies for a composition of `duration`, or
    /// `nil` when the encoder should choose.
    ///
    /// Returns `nil` for ``automatic``. For ``fileSize(bytes:)`` with a zero or
    /// negative duration there is nothing to solve, so it also returns `nil` rather
    /// than dividing by zero — an export with no duration has no bitrate problem.
    public func resolvedBitrate(forDuration duration: CMTime) -> Int? {
        switch self {
        case .automatic:
            return nil
        case .bitrate(let bps):
            return bps > 0 ? bps : nil
        case .fileSize(let bytes):
            let seconds = duration.seconds
            guard bytes > 0, seconds.isFinite, seconds > 0 else { return nil }
            let totalBits = Double(bytes) * 8.0
            let videoBits = totalBits - (Double(ExportSettings.assumedAudioBitrateFor(seconds: seconds)))
            guard videoBits > 0 else { return nil }
            return max(1, Int(videoBits / seconds))
        }
    }
}

/// Namespace for the arithmetic behind ``ExportQuality/fileSize(bytes:)``.
enum ExportSettings {
    static func assumedAudioBitrateFor(seconds: Double) -> Double {
        Double(ExportQuality.assumedAudioBitrate) * seconds
    }
}
