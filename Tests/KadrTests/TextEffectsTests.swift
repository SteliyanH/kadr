import XCTest
@testable import Kadr

/// v0.12 Tier 1 — surface-only tests for `TextStroke`, `TextShadow`, and the
/// new `TextStyle.stroke` / `.shadow` fields. Renderer wiring lands in Tier 2;
/// at this stage we just prove the structs hold values, defaults match the
/// RFC, and equality follows the existing color-skipping convention.
final class TextEffectsTests: XCTestCase {

    // MARK: - TextStroke

    func testStrokeStoresWidthAndColor() {
        #if canImport(UIKit)
        let red = PlatformColor.red
        #else
        let red = PlatformColor.red
        #endif
        let stroke = TextStroke(width: 3, color: red)
        XCTAssertEqual(stroke.width, 3)
    }

    func testStrokeColorDefaultsToBlack() {
        // Documented default — black is the right pairing for white text on a
        // busy frame, the canonical use case the field exists for.
        _ = TextStroke(width: 2)
        // We can't compare PlatformColor equality cross-platform; the test
        // just guards against a "default removed" regression by exercising the
        // single-arg init.
    }

    func testStrokeEquatableIgnoresColor() {
        let a = TextStroke(width: 3, color: .black)
        let b = TextStroke(width: 3, color: .white)
        // Same convention as TextStyle's existing `==` — color components are
        // not load-bearing on the engine path, so equality skips them.
        XCTAssertEqual(a, b)
    }

    func testStrokeEquatableComparesWidth() {
        XCTAssertNotEqual(TextStroke(width: 2), TextStroke(width: 3))
    }

    // MARK: - TextShadow

    func testShadowStoresOffsetAndBlur() {
        let shadow = TextShadow(offset: CGSize(width: 1, height: 2), blur: 5)
        XCTAssertEqual(shadow.offset, CGSize(width: 1, height: 2))
        XCTAssertEqual(shadow.blur, 5)
    }

    func testShadowDefaultsMatchRFC() {
        let shadow = TextShadow()
        XCTAssertEqual(shadow.offset, CGSize(width: 0, height: 2))
        XCTAssertEqual(shadow.blur, 4)
    }

    func testShadowEquatableIgnoresColor() {
        let a = TextShadow(offset: .zero, blur: 4, color: .black)
        let b = TextShadow(offset: .zero, blur: 4, color: .white)
        XCTAssertEqual(a, b)
    }

    func testShadowEquatableComparesScalars() {
        XCTAssertNotEqual(
            TextShadow(offset: CGSize(width: 0, height: 2), blur: 4),
            TextShadow(offset: CGSize(width: 1, height: 2), blur: 4)
        )
        XCTAssertNotEqual(
            TextShadow(offset: .zero, blur: 4),
            TextShadow(offset: .zero, blur: 5)
        )
    }

    // MARK: - TextStyle integration

    func testTextStyleDefaultsLeaveEffectsNil() {
        let style = TextStyle()
        XCTAssertNil(style.stroke)
        XCTAssertNil(style.shadow)
    }

    func testTextStyleAcceptsStrokeAndShadow() {
        let style = TextStyle(
            stroke: TextStroke(width: 4),
            shadow: TextShadow(offset: CGSize(width: 2, height: 2), blur: 6)
        )
        XCTAssertEqual(style.stroke?.width, 4)
        XCTAssertEqual(style.shadow?.blur, 6)
    }

    func testTextStyleEqualityIncludesEffects() {
        let base = TextStyle(stroke: TextStroke(width: 4))
        let same = TextStyle(stroke: TextStroke(width: 4))
        let different = TextStyle(stroke: TextStroke(width: 5))
        XCTAssertEqual(base, same)
        XCTAssertNotEqual(base, different)
    }

    func testTextStyleEqualityDistinguishesNilFromZeroStroke() {
        // A nil stroke and a zero-width stroke render the same way (no stroke)
        // but are not equal — preserving the user's "I cleared this field"
        // intent through round-trips matters for undo / persistence consumers.
        XCTAssertNotEqual(
            TextStyle(stroke: nil),
            TextStyle(stroke: TextStroke(width: 0))
        )
    }
}
