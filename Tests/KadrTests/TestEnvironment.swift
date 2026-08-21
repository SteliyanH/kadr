import Foundation

/// Test-environment notes.
///
/// This file used to gate 15 tests behind `KADR_SKIP_REENCODE_TESTS`, on the
/// diagnosis that GitHub's macOS runners were Apple-Silicon VMs without the
/// media engine exposed to the guest. **That diagnosis was wrong**, and the
/// gate is gone. The story is kept because it cost real time and the wrong
/// answer was convincing.
///
/// **What was actually wrong.** `swift-testing` runs in parallel by default,
/// and this suite fires many concurrent `AVAssetExportSession` jobs.
/// VideoToolbox has a finite number of concurrent sessions, and exhausting them
/// fails as an opaque `-11821 "Cannot Decode"` wrapping `-16977` — nothing that
/// resembles "too many sessions". Serialised, all 562 pass on the same runners
/// that used to fail 15 of them. CI now runs `swift test --no-parallel`; the
/// cost is roughly 25s → 57s of wall clock.
///
/// **Why the wrong answer looked right.** The failures clustered exactly on the
/// paths that pre-render an intermediate (filters via `FilterProcessor`,
/// reverse via `ReverseProcessor`) or decode a second asset (the audio tests
/// and `sample.mp3`) — because those are the heaviest media work in the suite,
/// so they lose the race for sessions first. A clean mechanical story fitted a
/// coincidence.
///
/// **What broke it.** Four hypotheses were tested and killed cheaply:
///
/// - *Fixture too large.* 5.7MB → 3.0MB and MP3 → AAC produced byte-identical
///   failure counts.
/// - *MP3 decode unavailable.* AAC failed the same way.
/// - *Media engine absent in VMs.* A third-party runner reporting
///   `kern.hv_vmm_present = 1` decoded video happily — the thumbnail tests load
///   the real fixture and pass — and recovered all six audio tests that GitHub
///   failed. Two VMs behaving differently is not a capability story.
/// - *Wrong export preset.* Adding the compatibility check the main export path
///   uses changed nothing: it returned `true`, and the file was still
///   unreadable.
///
/// **The giveaway was nondeterminism.** The same tests passed in one run on one
/// machine and failed in the next. A missing capability does not come and go.
/// Every environment-shaped explanation had to ignore that; contention explains
/// it directly.
///
/// **If these tests start failing again**, suspect concurrency before hardware.
/// A `--no-parallel` run that goes green is the fastest way to tell the two
/// apart, and it is one flag rather than a machine.
enum TestEnvironment {

    /// Retained so any straggling reference still compiles. Nothing is skipped:
    /// the media tests run everywhere now.
    ///
    /// Deliberately not removed outright — a consumer or a branch may still
    /// reference it, and a compile error is a worse way to learn this than a
    /// value that simply says "yes".
    @available(*, deprecated, message: "Always true. The re-encode tests are no longer skipped anywhere — the failures were parallelism, not capability. See this file's documentation.")
    static var canReencodeMedia: Bool { true }
}
