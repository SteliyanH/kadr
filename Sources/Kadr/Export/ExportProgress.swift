import Foundation

/// Progress snapshot yielded by ``Exporter/run()`` during an export.
public struct ExportProgress: Sendable {
    /// Completion fraction in `0...1`. `1.0` is the final yielded value.
    public let fractionCompleted: Double

    /// Estimated wall-clock seconds remaining until the export finishes, or `nil`
    /// before enough samples are available to estimate.
    ///
    /// > Note: This is **wall-clock time** (how long the user must wait), not media
    /// > timeline time. That's why it's `TimeInterval` rather than `CMTime` —
    /// > frame accuracy doesn't apply to elapsed seconds. Media-timeline values
    /// > elsewhere in the API (clip durations, transition durations, trim ranges) use
    /// > `CMTime` for frame precision.
    public let estimatedTimeRemaining: TimeInterval?

    /// Build a progress snapshot. Typically constructed by ``Exporter`` and yielded
    /// through ``Exporter/run()`` rather than created by callers directly.
    public init(fractionCompleted: Double, estimatedTimeRemaining: TimeInterval? = nil) {
        self.fractionCompleted = fractionCompleted
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
}
