import Foundation

extension VideoClip {
    /// Plays this clip at the given speed multiplier. Valid range: `0.25...4.0`.
    /// `2.0` halves the clip's duration; `0.5` doubles it. Audio pitch is preserved.
    /// Out-of-range values throw `KadrError.invalidSpeed` at export time.
    public func speed(_ rate: Double) -> VideoClip {
        VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: rate,
            filters: filters,
            clipID: clipID
        )
    }
}
