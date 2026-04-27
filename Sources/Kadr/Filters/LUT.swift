import Foundation

/// A 3D color lookup table loaded from a `.cube` file. Once constructed, can be reused
/// across multiple ``Filter/lut(_:)`` applications without re-parsing the source file.
///
/// ```swift
/// let lut = try LUT(url: lutFileURL)
/// VideoClip(url: clipURL).filter(.lut(lut))
/// ```
///
/// For one-shot usage where loading errors don't need to be handled separately from
/// composition errors, the throwing factory ``Filter/lut(url:)`` is more ergonomic:
///
/// ```swift
/// VideoClip(url: clipURL).filter(try .lut(url: lutFileURL))
/// ```
///
/// **Format support.** Standard `.cube` 3D LUT files (Adobe Cube LUT spec). 1D LUTs
/// (`LUT_1D_SIZE`) are not supported in v0.5; they use a different CIFilter and have
/// substantially different semantics. `TITLE`, `DOMAIN_MIN`, `DOMAIN_MAX` headers are
/// parsed and ignored — Kadr assumes `[0,1]` input/output range.
public struct LUT: Sendable, Equatable {

    /// Source `.cube` file URL the LUT was loaded from.
    public let url: URL

    /// Side length of the cube. A 33-entry-per-axis LUT (typical for color-grading
    /// applications) reports `33` here; total entries = `dimension³`.
    internal let dimension: Int

    /// Packed RGBA `Float32` data ready for `CIColorCube.inputCubeData`. Length =
    /// `dimension³ * 4 * 4` bytes.
    internal let data: Data

    /// Load and parse a `.cube` file synchronously.
    ///
    /// - Throws: ``KadrError/invalidLUT(_:reason:)`` if the file is missing, can't be
    ///   read as UTF-8, omits a `LUT_3D_SIZE` declaration, or has an entry count
    ///   that doesn't match `dimension³`.
    public init(url: URL) throws {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            throw KadrError.invalidLUT(url, reason: "Cannot read file as UTF-8")
        }
        let (dim, data) = try LUT.parse(raw, sourceURL: url)
        self.url = url
        self.dimension = dim
        self.data = data
    }

    /// Pure: parse `.cube` text. Internal so it's unit-testable without disk I/O.
    internal static func parse(_ raw: String, sourceURL: URL) throws -> (Int, Data) {
        var dimension: Int?
        var floats: [Float] = []

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let head = tokens.first else { continue }

            switch head {
            case "LUT_3D_SIZE":
                guard tokens.count >= 2, let n = Int(tokens[1]) else {
                    throw KadrError.invalidLUT(sourceURL, reason: "Malformed LUT_3D_SIZE line")
                }
                dimension = n
            case "LUT_1D_SIZE":
                throw KadrError.invalidLUT(sourceURL, reason: "1D LUTs are not supported (v0.5)")
            case "TITLE", "DOMAIN_MIN", "DOMAIN_MAX":
                continue   // accepted but ignored
            default:
                guard tokens.count >= 3,
                      let r = Float(tokens[0]),
                      let g = Float(tokens[1]),
                      let b = Float(tokens[2])
                else {
                    throw KadrError.invalidLUT(sourceURL, reason: "Malformed entry: \"\(line)\"")
                }
                floats.append(contentsOf: [r, g, b, 1.0])   // alpha = 1
            }
        }

        guard let dim = dimension else {
            throw KadrError.invalidLUT(sourceURL, reason: "Missing LUT_3D_SIZE declaration")
        }
        let expected = dim * dim * dim * 4
        guard floats.count == expected else {
            throw KadrError.invalidLUT(
                sourceURL,
                reason: "Entry count \(floats.count / 4) does not match dimension³ (\(dim * dim * dim))"
            )
        }

        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        return (dim, data)
    }
}
