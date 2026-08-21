import Foundation

/// Human-readable text for every ``KadrError`` case.
///
/// Without `LocalizedError`, a Swift error enum bridges to
/// `"The operation couldn't be completed. (Kadr.KadrError error 6.)"` — which is
/// what a consumer's UI showed when an export failed, because
/// `error.localizedDescription` is the one thing every error-handling path
/// reaches for.
///
/// Two rules shape the wording below.
///
/// **No raw file paths.** A path is not information a person can act on, and it
/// leaks a sandbox layout into the interface. Where a file is involved the text
/// names it (`clip-04.mov`), not where it lives. Consumers were sanitising these
/// strings themselves for exactly this reason.
///
/// **Written for whoever hit the error, not whoever wrote the code.**
/// `errorDescription` says what happened; `recoverySuggestion` says what to do
/// about it when there is something to do. Cases with no useful action — a
/// cancellation, an engine bug — get no suggestion rather than a hollow one.
///
/// Not localised: these packages ship no string catalogue, so translation is a
/// separate piece of work. English text is still a large improvement on an
/// NSError code.
extension KadrError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Couldn't read “\(url.lastPathComponent)”."
        case let .unsupportedFormat(detail):
            return "That media format isn't supported on this device. \(detail)"
        case .noClipsProvided:
            return "There's nothing to export."
        case let .exportFailed(underlying):
            return "The export didn't finish. \(underlying.localizedDescription)"
        case .cancelled:
            return "The export was cancelled."
        case let .notYetImplemented(feature):
            return "\(feature) isn't available yet."
        case let .invalidTransition(explanation):
            // Already written as an explanation for a person; passing it through
            // beats wrapping it in a second sentence.
            return explanation
        case let .invalidSpeed(rate):
            return "A clip's speed of \(KadrError.trim(rate))× is outside the supported range."
        case let .invalidDuckingLevel(level):
            return "A ducking level of \(KadrError.trim(level)) is outside the supported range."
        case let .invalidLUT(url, _):
            return "Couldn't load the colour LUT “\(url.lastPathComponent)”."
        }
    }

    public var failureReason: String? {
        switch self {
        case let .invalidLUT(_, reason):
            return reason
        default:
            return nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "The file may have moved, or it may not contain a video track."
        case .unsupportedFormat:
            return "Try converting it to H.264 or HEVC first."
        case .noClipsProvided:
            return "Add at least one clip before exporting."
        case .invalidSpeed:
            return "Speed must be between 0.25× and 4×."
        case .invalidDuckingLevel:
            return "Ducking must be between 0 and 1."
        case .invalidLUT:
            return "The file may be truncated, or not a .cube LUT."
        case .invalidTransition:
            return "Transitions need a clip on each side, and cannot be longer than the clips they join."
        case .exportFailed, .cancelled, .notYetImplemented:
            // Nothing the person can usefully do. A suggestion here would be
            // filler, and filler in an error message costs trust.
            return nil
        }
    }

    /// `4.0` reads better as `4` in a sentence; `0.25` must stay `0.25`.
    nonisolated static func trim(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%g", value)
    }
}
