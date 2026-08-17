import Foundation

/// Environment gate for tests that export real media.
///
/// **Why this exists.** A handful of tests decode the bundled H.264
/// `sample.mov` and run a real `AVAssetExportSession`. On real hardware they
/// pass in seconds. On GitHub's macOS runners — which are virtualised and have
/// no hardware video decode path — every one of them fails with
/// `AVFoundationErrorDomain -11821 "Cannot Decode"`, and the test process then
/// **fails to exit**: the runner reports `Terminate orphan process
/// (swiftpm-testing)` and the job burns its entire timeout doing nothing. One
/// such run sat for 33 minutes against a suite that takes 32 seconds locally.
///
/// **Why skip rather than fix.** The failure is environmental, not a defect in
/// the engine: same Xcode, same commit, passes on hardware, fails in a VM.
/// Deleting the tests would lose real coverage, and rewriting them against a
/// synthetic asset would test a different thing than what ships.
///
/// **Nothing is skipped by default.** The gate is opt-*out*: a developer
/// running `swift test` locally runs everything. Only CI sets
/// `KADR_SKIP_MEDIA_EXPORT_TESTS`, and it does so explicitly, in the workflow,
/// where it is visible.
///
/// **This is a stopgap.** Export is the engine's whole job, and CI no longer
/// covers it. The durable fix is to run these on hardware that can decode —
/// a self-hosted runner, or a scheduled job on a real machine. Tracked as a
/// follow-up rather than pretended away.
enum TestEnvironment {

    /// `false` only when CI has declared it cannot decode media.
    static var canDecodeMedia: Bool {
        ProcessInfo.processInfo.environment["KADR_SKIP_MEDIA_EXPORT_TESTS"] == nil
    }
}
