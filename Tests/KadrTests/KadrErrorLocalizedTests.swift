import Testing
import Foundation
@testable import Kadr

/// The text a person actually sees when something fails.
///
/// These assert the properties that matter at the point of failure rather than
/// exact copy: that every case says something, that nothing leaks a filesystem
/// path, and that `localizedDescription` — the property every error-handling
/// path reaches for — stops returning an NSError code.
struct KadrErrorLocalizedTests {

    private static let allCases: [KadrError] = [
        .invalidURL(URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application/ABC/clip-04.mov")),
        .unsupportedFormat("ProRes RAW"),
        .noClipsProvided,
        .exportFailed(underlying: NSError(domain: "AVFoundation", code: -11800)),
        .cancelled,
        .notYetImplemented("HDR export"),
        .invalidTransition("A transition needs a clip on each side."),
        .invalidSpeed(8),
        .invalidDuckingLevel(3),
        .invalidLUT(URL(fileURLWithPath: "/tmp/looks/teal-orange.cube"), reason: "Line 12 is malformed.")
    ]

    @Test(arguments: allCases)
    func everyCaseSaysSomething(error: KadrError) {
        let text = error.errorDescription
        #expect(text?.isEmpty == false, "A case with no description falls back to an NSError code.")
    }

    @Test(arguments: allCases)
    func localizedDescriptionIsNoLongerAnNSErrorCode(error: KadrError) {
        let text = error.localizedDescription
        #expect(!text.contains("The operation couldn't be completed"))
        #expect(!text.contains("Kadr.KadrError error"))
    }

    @Test(arguments: allCases)
    func noMessageLeaksAFilesystemPath(error: KadrError) {
        // A path is not something a person can act on, and it leaks the sandbox
        // layout into the interface.
        let text = [error.errorDescription, error.failureReason, error.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
        #expect(!text.contains("/private/var"))
        #expect(!text.contains("/tmp/"))
        #expect(!text.contains("Containers/Data"))
    }

    @Test func fileErrorsNameTheFileWithoutItsPath() {
        let e = KadrError.invalidURL(URL(fileURLWithPath: "/private/var/mobile/clip-04.mov"))
        #expect(e.errorDescription?.contains("clip-04.mov") == true)
        #expect(e.errorDescription?.contains("/private") == false)
    }

    @Test func theLUTReasonSurvivesAsFailureReason() {
        let e = KadrError.invalidLUT(URL(fileURLWithPath: "/tmp/x.cube"), reason: "Line 12 is malformed.")
        #expect(e.failureReason == "Line 12 is malformed.")
        #expect(e.errorDescription?.contains("x.cube") == true)
    }

    @Test func aHumanWrittenTransitionExplanationIsPassedThroughUnwrapped() {
        let explanation = "A transition cannot be longer than the clips it joins."
        #expect(KadrError.invalidTransition(explanation).errorDescription == explanation)
    }

    @Test func theUnderlyingExportFailureIsNotSwallowed() {
        let underlying = NSError(domain: "AVFoundation", code: -11800,
                                 userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed"])
        let text = KadrError.exportFailed(underlying: underlying).errorDescription ?? ""
        #expect(text.contains("The operation could not be completed"),
                "Losing the underlying reason would make export failures undiagnosable.")
    }

    // MARK: - Suggestions are offered only where there is something to do

    @Test(arguments: [KadrError.cancelled, .exportFailed(underlying: NSError(domain: "", code: 0)), .notYetImplemented("x")])
    func casesWithNoUsefulActionOfferNoSuggestion(error: KadrError) {
        #expect(error.recoverySuggestion == nil, "Filler in an error message costs trust.")
    }

    @Test(arguments: [KadrError.noClipsProvided, .invalidSpeed(9), .invalidDuckingLevel(4)])
    func actionableCasesSayWhatToDo(error: KadrError) {
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    // MARK: - Number formatting inside sentences

    @Test func wholeNumbersReadAsWholeNumbers() {
        #expect(KadrError.trim(4.0) == "4")
        #expect(KadrError.trim(0.25) == "0.25")
        #expect(KadrError.invalidSpeed(8).errorDescription?.contains("8×") == true)
    }
}
