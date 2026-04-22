import Foundation

public enum KadrError: Error, Sendable {
    case invalidURL(URL)
    case unsupportedFormat(String)
    case noClipsProvided
    case exportFailed(underlying: any Error)
    case cancelled
    case notYetImplemented(String)
}
