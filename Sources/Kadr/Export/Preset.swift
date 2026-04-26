import Foundation

/// Video codec used during export. H.264 has the broadest compatibility; HEVC produces
/// smaller files at the same quality on Apple Silicon and most modern devices.
public enum Codec: Sendable, Equatable {
    /// H.264 / AVC. Most compatible.
    case h264
    /// H.265 / HEVC. Smaller files, requires modern decoders.
    case hevc
}

/// Resolution / frame rate / codec preset for export.
///
/// The built-in cases target common social-media formats. For other dimensions or
/// frame rates, use ``custom(width:height:frameRate:codec:)``.
public enum Preset: Sendable {
    /// 1080×1920, 30fps, H.264 (vertical). Default when no preset is set.
    case auto
    /// 1080×1920, 30fps, HEVC (vertical). Tuned for Instagram Reels and YouTube Shorts.
    case reelsAndShorts
    /// 1080×1920, 30fps, H.264 (vertical). Tuned for TikTok.
    case tiktok
    /// 1080×1080, 30fps, H.264 (square).
    case square
    /// 1920×1080, 24fps, H.264 (cinematic widescreen).
    case cinema
    /// Fully custom dimensions, frame rate, and codec. `frameRate` is an integer fps;
    /// for fractional frame rates (e.g. 23.976) use ``Preset/cinema`` or post-process.
    case custom(width: Int, height: Int, frameRate: Int, codec: Codec)

    internal var resolution: CGSize {
        switch self {
        case .auto:
            return CGSize(width: 1080, height: 1920)
        case .reelsAndShorts:
            return CGSize(width: 1080, height: 1920)
        case .tiktok:
            return CGSize(width: 1080, height: 1920)
        case .square:
            return CGSize(width: 1080, height: 1080)
        case .cinema:
            return CGSize(width: 1920, height: 1080)
        case .custom(let width, let height, _, _):
            return CGSize(width: width, height: height)
        }
    }

    internal var frameRate: Int {
        switch self {
        case .auto:
            return 30
        case .reelsAndShorts:
            return 30
        case .tiktok:
            return 30
        case .square:
            return 30
        case .cinema:
            return 24
        case .custom(_, _, let frameRate, _):
            return frameRate
        }
    }

    internal var codec: Codec {
        switch self {
        case .auto:
            return .h264
        case .reelsAndShorts:
            return .hevc
        case .tiktok:
            return .h264
        case .square:
            return .h264
        case .cinema:
            return .h264
        case .custom(_, _, _, let codec):
            return codec
        }
    }
}
