import Foundation

public struct ExportProgress: Sendable {
    public let fractionCompleted: Double
    public let estimatedTimeRemaining: TimeInterval?

    public init(fractionCompleted: Double, estimatedTimeRemaining: TimeInterval? = nil) {
        self.fractionCompleted = fractionCompleted
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
}
