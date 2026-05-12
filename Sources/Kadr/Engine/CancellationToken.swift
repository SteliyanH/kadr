import AVFoundation
import Foundation

/// Thread-safe cancellation token shared between `Exporter` and `ExportEngine`.
/// Stores a reference to the active `AVAssetExportSession` so `cancel()` can
/// reach it from a different thread than the one that called `register(_:)`.
///
/// **v0.11 hardening.** Pre-v0.11 the type was `@unchecked Sendable` with
/// **no synchronization** — every `register` / `cancel` racing pair
/// produced undefined behavior under Swift 6 strict concurrency.
///
/// v0.11 keeps `@unchecked Sendable` (the type holds an
/// `AVAssetExportSession`, which isn't `Sendable` on macOS), but now backs
/// the claim with a real `NSLock` serializing every field access. The
/// `@unchecked` annotation is now an inner-detail compromise around
/// AVFoundation's macOS Sendable gap, not a "trust me" claim about
/// concurrency safety.
internal final class CancellationToken: @unchecked Sendable {

    /// Guards every read / write of `_isCancelled` and `_exportSession`.
    /// Cross-thread access to either field without first acquiring this
    /// lock is a bug.
    private let lock = NSLock()

    /// Guarded by `lock`.
    private var _isCancelled = false

    /// Guarded by `lock`.
    private var _exportSession: AVAssetExportSession?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    /// Register the in-flight export session. If `cancel()` already fired,
    /// the session is cancelled immediately so the caller doesn't have to
    /// branch on the race. Safe to call concurrently with `cancel()`.
    func register(_ session: AVAssetExportSession) {
        lock.lock()
        _exportSession = session
        let shouldCancelImmediately = _isCancelled
        lock.unlock()
        // Call AVFoundation outside the lock — `cancelExport()` returns
        // immediately (it sets an internal flag) but keeping AVFoundation
        // calls outside the critical section avoids reentrancy with
        // delegate callbacks.
        if shouldCancelImmediately {
            session.cancelExport()
        }
    }

    /// Mark the token cancelled and cancel any registered session.
    /// Idempotent; safe to call from any thread.
    func cancel() {
        lock.lock()
        _isCancelled = true
        let session = _exportSession
        lock.unlock()
        session?.cancelExport()
    }
}
