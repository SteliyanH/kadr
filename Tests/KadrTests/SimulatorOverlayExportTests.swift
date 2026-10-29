import Testing
import Foundation
@testable import Kadr
import CoreGraphics

/// On the iOS Simulator, exporting with overlays used to kill the app: Core Animation
/// wraps AVFoundation's `malloc`-backed frames in an IOSurface and libxpc traps with
/// "Attempt to pass a malloc(3)ed region to xpc_shmem_create()". The engine now
/// refuses such an export with an error. See the Known Platform Issues article.
struct SimulatorOverlayExportTests {

    // MARK: - Decision (runs everywhere)

    @Test func overlayExportIsRefusedOnTheIOSSimulator() throws {
        let error = try #require(ExportEngine.simulatorOverlayError(hasOverlays: true, onIOSSimulator: true))
        guard case .exportFailed(let underlying) = error else {
            Issue.record("expected .exportFailed, got \(error)")
            return
        }
        let message = (underlying as NSError).localizedDescription
        #expect(message.contains("iOS Simulator"))
        #expect(message.contains("Known Platform Issues"))
    }

    @Test func exportWithoutOverlaysIsAllowedOnTheIOSSimulator() {
        #expect(ExportEngine.simulatorOverlayError(hasOverlays: false, onIOSSimulator: true) == nil)
    }

    @Test func overlayExportIsAllowedElsewhere() {
        #expect(ExportEngine.simulatorOverlayError(hasOverlays: true, onIOSSimulator: false) == nil)
    }

    // MARK: - Export (iOS Simulator only)

    @Test(.enabled(if: ExportEngine.isIOSSimulator, "Only the iOS Simulator refuses overlay exports"))
    func overlayExportThrowsInsteadOfCrashing() async throws {
        let size = CGSize(width: 64, height: 64)
        let context = try #require(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let cg = try #require(context.makeImage())
        #if canImport(UIKit)
        let image = PlatformImage(cgImage: cg)
        #else
        let image = PlatformImage(cgImage: cg, size: size)
        #endif
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simulator_overlay_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        await #expect(throws: KadrError.self) {
            _ = try await Video { ImageClip(image, duration: 1.0) }
                .overlay(TextOverlay("hello"))
                .export(to: outputURL)
        }
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }
}
