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
/// **This is a stopgap, not a resolution.** Filters, audio mixing and reverse
/// are unverified by CI until these run somewhere that can decode. Tracked in
/// the repo's issues rather than left to live in a comment.
enum TestEnvironment {

    /// `false` only when CI has declared it cannot survive a re-encode /
    /// second-asset decode round-trip.
    static var canReencodeMedia: Bool {
        ProcessInfo.processInfo.environment["KADR_SKIP_REENCODE_TESTS"] == nil
    }

    /// EXPERIMENT (issue #139, option 4): swap the re-encode tests onto a
    /// smaller, shorter fixture and an AAC audio track, to find out whether the
    /// runner is failing on the *size* of the intermediate it has to decode or
    /// on the capability itself.
    ///
    /// Two variables move together on purpose — this is a cheap yes/no, not a
    /// controlled study. If it passes, narrow it down; if it fails, the
    /// capability-absence hypothesis stands and this gets deleted.
    static var usesTinyFixtures: Bool {
        ProcessInfo.processInfo.environment["KADR_TINY_FIXTURES"] != nil
    }

    /// Video fixture the re-encode tests should load.
    static var videoFixtureName: String { usesTinyFixtures ? "tiny" : "sample" }

    /// Audio fixture, and its extension — the tiny variant is AAC rather than
    /// MP3, because MP3 decode is one of the things suspected of failing.
    static var audioFixtureName: String { usesTinyFixtures ? "tiny" : "sample" }
    static var audioFixtureExtension: String { usesTinyFixtures ? "m4a" : "mp3" }
}
