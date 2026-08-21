import Foundation

/// Environment gate for tests that need a second decode pass.
///
/// **What fails, precisely.** Export is *not* broken on GitHub's macOS runners.
/// Crop, overlays, transitions, speed and multi-overlay exports all pass there.
/// What fails is narrower, and it clusters exactly:
///
/// | Underlying OSStatus | Tests | Feature |
/// | --- | --- | --- |
/// | `-16977` | 13 | every filter test, and every audio test (ducking, background music, replaceAudio) |
/// | `-12137` | 2 | the two reverse tests |
///
/// **Why those and not the others.** `CompositionBuilder` pre-renders certain
/// features to a temporary file before composition — reverse first via
/// `ReverseProcessor` (`AVAssetReader` → `AVAssetWriter`), then filters via
/// `FilterProcessor` (`applyingCIFiltersWithHandler`). Each writes an
/// intermediate the pipeline must then decode *again*. The audio tests pull in
/// a second asset, the `sample.mp3` fixture, for `AVMutableAudioMix`.
///
/// Everything that fails asks the runner either to encode an intermediate and
/// read it back, or to decode a second media file. Everything that passes goes
/// through a single composition pass with no re-encode. No exceptions in either
/// direction — that pattern is what the gate is named after.
///
/// **Root cause, inferred rather than proven:** GitHub's macOS runners are
/// Apple-Silicon VMs where the hardware media engine is not exposed to the
/// guest. Single-pass composition survives on the software path; the
/// intermediate encode produces something the runner's own decoder cannot read,
/// and MP3 decode fails the same way. This is not reproducible on hardware —
/// all 539 tests pass locally — so the mechanism is a strong inference from the
/// failure pattern, not a verified claim.
///
/// **The expensive symptom.** After those failures the test process never
/// exits: the runner logs `Terminate orphan process (swiftpm-testing)`. One run
/// sat 33 minutes against a suite that takes 32 seconds locally and had to be
/// cancelled by hand. `timeout-minutes` in the workflow now caps that.
///
/// **Nothing is skipped by default.** The gate is opt-*out*: `swift test`
/// locally runs all 539. Only the workflow sets the variable, explicitly, where
/// it is visible.
///
/// **What was tried, so nobody re-runs it.** The alternatives are exhausted,
/// and each was tested rather than assumed:
///
/// - *A smaller fixture.* Video 5.7MB → 3.0MB and audio MP3 → AAC produced
///   byte-identical failure counts. Not a resource limit, and not MP3-specific.
/// - *A different hosted provider.* Codemagic's Mac mini M2 machines fail with
///   the same `-11821` / `-16977`. Virtualised the same way.
/// - *A self-hosted runner.* No machine available to dedicate to it.
/// - *Asserting composition structure instead.* Mostly redundant — the DSL
///   surface these tests exercise is already covered by ungated tests in the
///   same files. The version that would add real coverage means separating the
///   ramp and filter-chain *decisions* from their *application* inside
///   `CompositionBuilder`, and even that would not test the encode path.
///
/// **So this is a known limitation, not a stopgap awaiting a fix.** Filters,
/// audio mixing and reverse are verified on every local run — all 562 tests
/// pass on hardware in about 30 seconds — and unverified by CI. Stated plainly
/// here and in the release notes rather than implied away.
///
/// Reopening is cheap: `nightly-hardware.yml` is written and inert, and needs
/// only a runner and a repository variable.
enum TestEnvironment {

    /// `false` only when CI has declared it cannot survive a re-encode /
    /// second-asset decode round-trip.
    static var canReencodeMedia: Bool {
        ProcessInfo.processInfo.environment["KADR_SKIP_REENCODE_TESTS"] == nil
    }
}
