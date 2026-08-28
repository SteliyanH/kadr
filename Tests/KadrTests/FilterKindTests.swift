import Testing
import Foundation
import CoreGraphics
// Plain import — a filter menu is built by a client, from the public surface.
import Kadr

/// Tests for `FilterKind`, the enumerable catalogue of what kadr can apply.
///
/// The point of these is not that the mapping is correct today; it is that the
/// catalogue cannot drift from `Filter`. Every previous version of this menu
/// lived hard-coded in an app, which meant a filter added to kadr simply never
/// appeared to users and nothing failed.
struct FilterKindTests {

    @Test("Every kind's default filter reports that same kind")
    func defaultsRoundTrip() {
        for kind in FilterKind.allCases {
            guard let filter = kind.defaultFilter else { continue }
            #expect(filter.kind == kind, "\(kind) built a filter of kind \(filter.kind)")
        }
    }

    @Test("Every kind is reachable — insertable, or documented as needing a payload")
    func everyKindIsAccountedFor() {
        let needPayload: Set<FilterKind> = [.lut, .chromaKey]
        for kind in FilterKind.allCases {
            if needPayload.contains(kind) {
                #expect(kind.defaultFilter == nil, "\(kind) should need a payload")
            } else {
                #expect(kind.defaultFilter != nil, "\(kind) has no default a menu could insert")
            }
        }
        #expect(FilterKind.insertable.count == FilterKind.allCases.count - needPayload.count)
    }

    @Test("Every kind has a non-empty display name, and no two collide")
    func displayNamesAreUsable() {
        let names = FilterKind.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test("Raw values are stable keys a localised app can look up")
    func rawValuesAreStable() {
        // Pinned deliberately: these are persisted and localised against, so a
        // rename is a breaking change and should fail here first.
        #expect(FilterKind.gaussianBlur.rawValue == "gaussianBlur")
        #expect(FilterKind.chromaKey.rawValue == "chromaKey")
        #expect(Set(FilterKind.allCases.map(\.rawValue)).count == FilterKind.allCases.count)
    }

    @Test("A constructed filter reports the kind it was built as")
    func constructedFiltersReportTheirKind() {
        #expect(Filter.brightness(0.3).kind == .brightness)
        #expect(Filter.mono.kind == .mono)
        #expect(Filter.gaussianBlur(radius: 4).kind == .gaussianBlur)
        #expect(Filter.chromaKey(ChromaKey(color: ColorComponents(r: 0, g: 1, b: 0), threshold: 0.3)).kind == .chromaKey)
    }

    @Test("hasIntensity matches which filters withScalar actually varies")
    func intensityFlagMatchesBehaviour() {
        for kind in FilterKind.allCases {
            guard let filter = kind.defaultFilter else { continue }
            let varied = filter.withScalar(0.5)
            if kind.hasIntensity {
                #expect(varied != filter, "\(kind) claims an intensity but withScalar changed nothing")
            } else {
                #expect(varied == filter, "\(kind) claims no intensity but withScalar changed it")
            }
        }
    }

    @Test("The catalogue covers every filter the DSL can produce")
    func catalogueIsComplete() {
        // A sample of every case, built by hand. `Filter.kind` is an exhaustive
        // switch, so a new case breaks the build there; this asserts the other
        // direction — that each one maps to a kind the catalogue lists.
        let everyCase: [Filter] = [
            .brightness(0), .contrast(1), .saturation(1), .exposure(0),
            .sepia(intensity: 1), .mono, .gaussianBlur(radius: 1),
            .vignette(intensity: 1), .sharpen(amount: 0.1), .zoomBlur(amount: 1),
            .glow(intensity: 1),
            .chromaKey(ChromaKey(color: ColorComponents(r: 0, g: 1, b: 0), threshold: 0.3)),
        ]
        let covered = Set(everyCase.map(\.kind))
        // .lut is omitted above because building one needs a file on disk.
        #expect(covered.union([.lut]) == Set(FilterKind.allCases))
    }
}
