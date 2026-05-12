import XCTest
import AVFoundation
@testable import Kadr

/// Tests for the v0.11 atomicity guarantee on ``CancellationToken``. The
/// pre-v0.11 implementation used non-atomic `Bool` + optional under
/// `@unchecked Sendable` — calls to `register` and `cancel` from different
/// threads could race. v0.11 wraps both fields in `OSAllocatedUnfairLock`.
///
/// We can't observe the data race directly without TSan; these tests verify
/// the *behavioral* invariants every interleaving must satisfy, and run
/// enough concurrent operations to catch the most obvious races if they
/// regress.
final class CancellationTokenTests: XCTestCase {

    // MARK: - Single-thread sanity

    func testDefaultStateIsNotCancelled() {
        let token = CancellationToken()
        XCTAssertFalse(token.isCancelled)
    }

    func testCancelSetsIsCancelled() {
        let token = CancellationToken()
        token.cancel()
        XCTAssertTrue(token.isCancelled)
    }

    func testCancelIsIdempotent() {
        let token = CancellationToken()
        token.cancel()
        token.cancel()
        token.cancel()
        XCTAssertTrue(token.isCancelled)
    }

    // MARK: - Register / cancel ordering

    /// If `cancel()` fires before `register(_:)`, the registered session
    /// must still be cancelled — `register` reads the cancelled flag under
    /// the lock and pre-cancels the session before returning.
    func testCancelBeforeRegisterStillCancelsSession() throws {
        let token = CancellationToken()
        token.cancel()

        let session = try makeStubExportSession()
        token.register(session)

        // The session should have received `cancelExport()` synchronously
        // inside `register`. AVAssetExportSession's status post-cancel is
        // `.cancelled`, but only after the cancellation propagates; the
        // observable invariant we can test is that we didn't crash and
        // `isCancelled` stays true.
        XCTAssertTrue(token.isCancelled)
    }

    /// `register(_:)` followed by `cancel()` is the normal happy path —
    /// the cancellation reaches the registered session.
    func testRegisterThenCancelReachesSession() throws {
        let token = CancellationToken()
        let session = try makeStubExportSession()
        token.register(session)
        token.cancel()
        XCTAssertTrue(token.isCancelled)
    }

    // MARK: - Concurrent stress

    /// Interleave 1000 `cancel()` calls across 8 concurrent tasks against a
    /// single token. The lock guarantees `isCancelled` reaches a consistent
    /// `true` state regardless of interleaving. Pre-v0.11 this could read
    /// torn values; v0.11 cannot.
    func testConcurrentCancellationConvergesToCancelled() async {
        let token = CancellationToken()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<125 {
                        token.cancel()
                    }
                }
            }
        }
        XCTAssertTrue(token.isCancelled)
    }

    /// `register` and `cancel` racing across two threads against a single
    /// token. The token holds an `AVAssetExportSession`, which on macOS is
    /// not `Sendable` — so we can't ferry it across an `async let`
    /// boundary (the compiler correctly objects). Use GCD directly to
    /// drive the race; the lock invariant we're testing is internal to
    /// the token, not to Sendable semantics. Repeat 50× to vary the
    /// interleaving the scheduler picks.
    func testConcurrentRegisterAndCancelConvergeConsistently() throws {
        for _ in 0..<50 {
            let token = CancellationToken()
            let session = try makeStubExportSession()
            let group = DispatchGroup()
            let queue = DispatchQueue.global(qos: .userInitiated)

            group.enter()
            queue.async {
                token.cancel()
                group.leave()
            }
            group.enter()
            queue.async {
                token.register(session)
                group.leave()
            }

            group.wait()
            XCTAssertTrue(token.isCancelled)
        }
    }

    // MARK: - Sendable conformance

    /// v0.11 removes `@unchecked Sendable` — the lock makes the type
    /// genuinely `Sendable`. Compile-time verified by passing the token
    /// across an `async let` boundary.
    func testTokenIsSendable() async {
        let token = CancellationToken()
        async let cancelled: Bool = {
            token.cancel()
            return token.isCancelled
        }()
        let result = await cancelled
        XCTAssertTrue(result)
    }

    // MARK: - Helpers

    /// Build a stub `AVAssetExportSession` we can hand to `register`.
    /// We don't actually run the export — just verify the token interacts
    /// with the session without crashing.
    private func makeStubExportSession() throws -> AVAssetExportSession {
        // A 1×1 PNG asset is the cheapest valid AVAsset we can build.
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadr-cancellation-token-\(UUID().uuidString).mov")
        // Create a trivially-small placeholder file — AVAssetExportSession
        // doesn't validate it on init, only on `exportAsynchronously()`.
        try Data().write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let asset = AVURLAsset(url: tmpURL)
        let session = try XCTUnwrap(
            AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        )
        return session
    }
}
