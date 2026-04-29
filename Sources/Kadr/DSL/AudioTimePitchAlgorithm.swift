import AVFoundation

/// How the engine preserves (or doesn't) audio pitch when an ``AudioTrack`` plays at a
/// non-`1.0` speed multiplier. Maps directly onto AVFoundation's
/// `AVAudioTimePitchAlgorithm`. Default is ``spectral`` — voice-friendly, broadly good.
public enum AudioTimePitchAlgorithm: Sendable, Equatable {

    /// Spectral processing — best for voice / narration. Highest quality at the cost of
    /// CPU. Default.
    case spectral

    /// Time-domain processing — best for music at small ratios (`~0.75x...~1.5x`). Lower
    /// CPU than spectral; can produce audible artifacts at extreme speeds.
    case timeDomain

    /// No pitch correction — the chipmunk effect at high speed, deepening at low speed.
    /// Use when you actually want the pitch shift (sound design, SFX), not for music or
    /// voice.
    case varispeed

    /// AVFoundation's underlying constant. Internal — used by the engine when assigning
    /// `AVMutableAudioMixInputParameters.audioTimePitchAlgorithm`.
    internal var avAlgorithm: AVAudioTimePitchAlgorithm {
        switch self {
        case .spectral:   return .spectral
        case .timeDomain: return .timeDomain
        case .varispeed:  return .varispeed
        }
    }
}
