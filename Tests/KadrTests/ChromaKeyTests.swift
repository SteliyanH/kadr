import Testing
import Foundation
@testable import Kadr

/// Tests for the v0.5.0 ``ChromaKey`` value type and the new ``Filter/chromaKey(_:)``
/// case. Cube-build math is `internal`, exercised via `@testable`.
struct ChromaKeyTests {

    private let dim = ChromaKey.cubeDimension

    // MARK: - Public construction

    @Test func constructsFromPlatformColor() {
        let key = ChromaKey(color: .green, threshold: 0.4)
        #expect(key.threshold == 0.4)
        // Components are platform-extracted; just sanity-check the cube was built.
        #expect(key.cubeData.count == dim * dim * dim * 4 * MemoryLayout<Float>.size)
    }

    @Test func equatableSameInputsProduceEqualValues() {
        let a = ChromaKey(color: .green, threshold: 0.35)
        let b = ChromaKey(color: .green, threshold: 0.35)
        #expect(a == b)
    }

    @Test func equatableDifferentThresholdsAreUnequal() {
        let a = ChromaKey(color: .green, threshold: 0.30)
        let b = ChromaKey(color: .green, threshold: 0.40)
        #expect(a != b)
    }

    // MARK: - Cube semantics

    @Test func cubeIsAllOpaqueWhenThresholdIsZero() {
        // threshold = 0 means only an exact chroma match passes the strict-less-than
        // check. With cube quantization, the target chroma rarely lands exactly on a
        // grid point, so effectively every entry has alpha = 1.
        let target = ColorComponents(r: 0, g: 1, b: 0)   // pure green
        let cube = ChromaKey.buildCube(target: target, threshold: 0)

        let alphas = readAlphas(cube)
        // No exact match → all opaque.
        #expect(alphas.allSatisfy { $0 == 1 })
    }

    @Test func cubeIsAllTransparentWhenThresholdIsHuge() {
        // Distance-squared in (Cb, Cr) is bounded; threshold² > 2 covers the whole
        // chroma plane.
        let target = ColorComponents(r: 0, g: 1, b: 0)
        let cube = ChromaKey.buildCube(target: target, threshold: 10.0)

        let alphas = readAlphas(cube)
        #expect(alphas.allSatisfy { $0 == 0 })
    }

    @Test func cubePartiallyTransparentForReasonableThreshold() {
        // For green-screen footage, threshold ≈ 0.35 should mark a non-trivial subset
        // (greens and adjacent chromas) as transparent without nuking the entire cube.
        let target = ColorComponents(r: 0, g: 1, b: 0)
        let cube = ChromaKey.buildCube(target: target, threshold: 0.35)

        let alphas = readAlphas(cube)
        let removed = alphas.filter { $0 == 0 }.count
        let preserved = alphas.filter { $0 == 1 }.count
        #expect(removed > 0)
        #expect(preserved > 0)
        // Sanity: greens dominate but most colors aren't green-ish; preserved should
        // still be the majority.
        #expect(preserved > removed)
    }

    @Test func cubeUsesPremultipliedAlpha() {
        // CIColorCube requires premultiplied alpha — RGB must be 0 wherever alpha is 0.
        let target = ColorComponents(r: 0, g: 1, b: 0)
        let cube = ChromaKey.buildCube(target: target, threshold: 0.35)

        cube.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            let floats = rawBuffer.bindMemory(to: Float.self)
            // Step through each entry; every entry where alpha == 0 must have RGB == 0.
            var i = 0
            while i < floats.count {
                let r = floats[i]
                let g = floats[i + 1]
                let b = floats[i + 2]
                let a = floats[i + 3]
                if a == 0 {
                    #expect(r == 0)
                    #expect(g == 0)
                    #expect(b == 0)
                }
                i += 4
            }
        }
    }

    // MARK: - Filter integration

    @Test func filterChromaKeyMapsToCIColorCube() {
        let key = ChromaKey(color: .green, threshold: 0.4)
        #expect(Filter.chromaKey(key).ciFilterName == "CIColorCube")
    }

    @Test func filterChromaKeyFactoryWraps() {
        let filter = Filter.chromaKey(color: .green, threshold: 0.4)
        if case .chromaKey(let key) = filter {
            #expect(key.threshold == 0.4)
        } else {
            Issue.record("Expected .chromaKey case")
        }
    }

    // MARK: - ColorComponents

    @Test func colorComponentsExtractFromBlackAndWhite() {
        let black = ColorComponents(platformColor: .black)
        #expect(black.r == 0 && black.g == 0 && black.b == 0)
        let white = ColorComponents(platformColor: .white)
        #expect(white.r == 1 && white.g == 1 && white.b == 1)
    }

    // MARK: - Helpers

    /// Read the alpha channel out of a packed RGBA Float32 cube.
    private func readAlphas(_ cube: Data) -> [Float] {
        var alphas: [Float] = []
        alphas.reserveCapacity(cube.count / (4 * MemoryLayout<Float>.size))
        cube.withUnsafeBytes { rawBuffer in
            let floats = rawBuffer.bindMemory(to: Float.self)
            var i = 3
            while i < floats.count {
                alphas.append(floats[i])
                i += 4
            }
        }
        return alphas
    }
}
