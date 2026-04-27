import Testing
import Foundation
@testable import Kadr

/// Tests for the v0.5.0 ``LUT`` value type and the new ``Filter/lut(_:)`` case. The
/// `.cube` parser is `internal`, so this file uses `@testable import` to exercise it
/// directly. Filter-integration tests round-trip through a temp `.cube` file so they
/// also verify the public init's I/O path.
struct LUTTests {

    /// Identity LUT_3D_SIZE 2 — the smallest possible 3D LUT. 2³ = 8 entries.
    private let identity2: String = """
    # Identity LUT
    TITLE "Identity 2x2x2"
    LUT_3D_SIZE 2
    0.0 0.0 0.0
    1.0 0.0 0.0
    0.0 1.0 0.0
    1.0 1.0 0.0
    0.0 0.0 1.0
    1.0 0.0 1.0
    0.0 1.0 1.0
    1.0 1.0 1.0
    """

    private func writeTempCube(_ raw: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadr_lut_\(UUID().uuidString).cube")
        try raw.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Parser

    @Test func parsesValidIdentityLUT() throws {
        let url = URL(fileURLWithPath: "/tmp/identity.cube")
        let (dim, data) = try LUT.parse(identity2, sourceURL: url)
        #expect(dim == 2)
        // 2³ entries × 4 floats × 4 bytes = 128 bytes
        #expect(data.count == 128)
    }

    @Test func skipsCommentsAndHeaders() throws {
        let raw = """
        # This is a comment
        TITLE "test"
        DOMAIN_MIN 0 0 0
        DOMAIN_MAX 1 1 1
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """
        let url = URL(fileURLWithPath: "/tmp/test.cube")
        let (dim, _) = try LUT.parse(raw, sourceURL: url)
        #expect(dim == 2)
    }

    @Test func throwsOnMissingDimension() {
        let raw = """
        # No LUT_3D_SIZE here
        0.0 0.0 0.0
        1.0 1.0 1.0
        """
        let url = URL(fileURLWithPath: "/tmp/bad.cube")
        #expect(throws: KadrError.self) {
            try LUT.parse(raw, sourceURL: url)
        }
    }

    @Test func throwsOnMismatchedEntryCount() {
        let raw = """
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        """
        let url = URL(fileURLWithPath: "/tmp/short.cube")
        #expect(throws: KadrError.self) {
            try LUT.parse(raw, sourceURL: url)
        }
    }

    @Test func throwsOn1DLUT() {
        let raw = """
        LUT_1D_SIZE 16
        0.0 0.0 0.0
        """
        let url = URL(fileURLWithPath: "/tmp/1d.cube")
        #expect(throws: KadrError.self) {
            try LUT.parse(raw, sourceURL: url)
        }
    }

    @Test func throwsOnMalformedEntry() {
        let raw = """
        LUT_3D_SIZE 2
        not a number here
        """
        let url = URL(fileURLWithPath: "/tmp/malformed.cube")
        #expect(throws: KadrError.self) {
            try LUT.parse(raw, sourceURL: url)
        }
    }

    // MARK: - Public init (I/O path)

    @Test func loadsLUTFromTempFile() throws {
        let url = try writeTempCube(identity2)
        defer { try? FileManager.default.removeItem(at: url) }
        let lut = try LUT(url: url)
        #expect(lut.dimension == 2)
        #expect(lut.data.count == 128)
        #expect(lut.url == url)
    }

    @Test func throwsForMissingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/to/lut.cube")
        #expect(throws: KadrError.self) {
            _ = try LUT(url: url)
        }
    }

    // MARK: - Filter integration

    @Test func filterLutCaseEqualityFromSameFile() throws {
        let url = try writeTempCube(identity2)
        defer { try? FileManager.default.removeItem(at: url) }
        let a = try LUT(url: url)
        let b = try LUT(url: url)
        #expect(Filter.lut(a) == Filter.lut(b))
    }

    @Test func filterLutMapsToCIColorCube() throws {
        let url = try writeTempCube(identity2)
        defer { try? FileManager.default.removeItem(at: url) }
        let lut = try LUT(url: url)
        #expect(Filter.lut(lut).ciFilterName == "CIColorCube")
    }

    // MARK: - Throwing convenience factory

    @Test func filterFactoryLoadsAndWraps() throws {
        let url = try writeTempCube(identity2)
        defer { try? FileManager.default.removeItem(at: url) }
        let filter = try Filter.lut(url: url)
        #expect(filter.ciFilterName == "CIColorCube")
    }

    @Test func filterFactoryThrowsForMissingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/to/lut.cube")
        #expect(throws: KadrError.self) {
            _ = try Filter.lut(url: url)
        }
    }
}
