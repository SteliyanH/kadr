import Testing
import Foundation
// Plain import: the gap was that a *client* could not rebuild a ChromaKey from
// its own public properties. Inside the package the internals are in reach, so
// `@testable` would hide exactly the thing under test.
import Kadr

/// Tests for `ChromaKey(color:threshold:)`.
struct ChromaKeyComponentsTests {

    @Test("A ChromaKey can be rebuilt from its own public properties")
    func roundTripsThroughItsOwnProperties() {
        let original = ChromaKey(color: PlatformColor(red: 0, green: 1, blue: 0, alpha: 1), threshold: 0.35)
        let rebuilt = ChromaKey(color: original.color, threshold: original.threshold)
        #expect(rebuilt == original)
    }

    @Test("Components survive exactly, without a PlatformColor round trip")
    func componentsAreVerbatim() {
        let components = ColorComponents(r: 0.125, g: 0.5, b: 0.875)
        let key = ChromaKey(color: components, threshold: 0.4)
        #expect(key.color == components)
        #expect(key.threshold == 0.4)
    }

    @Test("Both initialisers agree for the same colour")
    func initialisersAgree() {
        let fromPlatform = ChromaKey(color: PlatformColor(red: 0, green: 1, blue: 0, alpha: 1), threshold: 0.3)
        let fromComponents = ChromaKey(color: ColorComponents(r: 0, g: 1, b: 0), threshold: 0.3)
        #expect(fromPlatform == fromComponents)
    }

    @Test("A restored key still filters — the cube is rebuilt, not dropped")
    func cubeIsRebuilt() {
        let original = ChromaKey(color: ColorComponents(r: 0, g: 1, b: 0), threshold: 0.35)
        let restored = ChromaKey(color: original.color, threshold: original.threshold)
        // Equality covers cubeData, which is the expensive precomputed part; if
        // the second initialiser skipped building it these would differ.
        #expect(restored == original)
    }
}
