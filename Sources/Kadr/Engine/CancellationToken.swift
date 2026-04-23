import AVFoundation

/// Thread-safe cancellation token shared between Exporter and ExportEngine.
/// Stores a reference to the active AVAssetExportSession so cancel() can reach it.
internal final class CancellationToken: @unchecked Sendable {
    private var exportSession: AVAssetExportSession?
    private var _isCancelled = false

    var isCancelled: Bool { _isCancelled }

    func register(_ session: AVAssetExportSession) {
        exportSession = session
        if _isCancelled {
            session.cancelExport()
        }
    }

    func cancel() {
        _isCancelled = true
        exportSession?.cancelExport()
    }
}
