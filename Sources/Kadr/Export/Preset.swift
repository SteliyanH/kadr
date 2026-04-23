import Foundation

public enum Codec: Sendable, Equatable {
    case h264
    case hevc
}

public enum Preset: Sendable {
    case auto
    case reelsAndShorts
    case tiktok
    case square
    case cinema
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
