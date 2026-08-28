import Foundation

/// The set of filters this version of kadr can apply, as a value you can
/// enumerate.
///
/// ``Filter`` is an enum with associated values, so it cannot be `CaseIterable`
/// — there is no single `.brightness` to list, only `.brightness(0.2)`. Any UI
/// offering "add a filter" therefore has to hard-code the menu, and every
/// hard-coded menu goes stale the moment a filter is added here. This type is
/// the fix: iterate ``FilterKind/allCases``, and a filter added to kadr appears
/// in the menu without the consumer changing anything.
///
/// ```swift
/// ForEach(FilterKind.insertable, id: \.self) { kind in
///     Button(kind.displayName) { add(kind.defaultFilter!) }
/// }
/// ```
///
/// The link back to ``Filter`` is compiler-enforced in both directions:
/// ``Filter/kind`` switches exhaustively over `Filter`, so adding a case there
/// fails the build until it is classified here.
///
/// Added in v0.22.
public enum FilterKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case brightness
    case contrast
    case saturation
    case exposure
    case sepia
    case mono
    case gaussianBlur
    case vignette
    case sharpen
    case zoomBlur
    case glow
    case lut
    case chromaKey

    /// A reasonable starting value for this kind — what a menu inserts when the
    /// user picks it.
    ///
    /// `nil` for the two kinds that cannot be built from nothing: ``lut`` needs
    /// a cube file, and ``chromaKey`` needs a colour and a threshold. A UI
    /// offering those routes through its own picker instead. See
    /// ``FilterKind/insertable``.
    public var defaultFilter: Filter? {
        switch self {
        case .brightness:   return .brightness(0)
        case .contrast:     return .contrast(1)
        case .saturation:   return .saturation(1)
        case .exposure:     return .exposure(0)
        case .sepia:        return .sepia(intensity: 1)
        case .mono:         return .mono
        case .gaussianBlur: return .gaussianBlur(radius: 10)
        case .vignette:     return .vignette(intensity: 1)
        case .sharpen:      return .sharpen(amount: 0.4)
        case .zoomBlur:     return .zoomBlur(amount: 20)
        case .glow:         return .glow(intensity: 1)
        case .lut, .chromaKey: return nil
        }
    }

    /// The kinds a menu can insert directly — every kind with a
    /// ``defaultFilter``.
    public static var insertable: [FilterKind] {
        allCases.filter { $0.defaultFilter != nil }
    }

    /// An English name, for menus.
    ///
    /// kadr ships no localisation. ``rawValue`` is a stable key, so a localised
    /// app can look up its own string by it and fall back to this.
    public var displayName: String {
        switch self {
        case .brightness:   return "Brightness"
        case .contrast:     return "Contrast"
        case .saturation:   return "Saturation"
        case .exposure:     return "Exposure"
        case .sepia:        return "Sepia"
        case .mono:         return "Mono"
        case .gaussianBlur: return "Gaussian Blur"
        case .vignette:     return "Vignette"
        case .sharpen:      return "Sharpen"
        case .zoomBlur:     return "Zoom Blur"
        case .glow:         return "Glow"
        case .lut:          return "Colour LUT"
        case .chromaKey:    return "Chroma Key"
        }
    }

    /// Whether this kind responds to ``Filter/withScalar(_:)`` — i.e. whether a
    /// UI should offer an intensity slider for it.
    ///
    /// ``mono`` has nothing to vary, and ``lut`` / ``chromaKey`` are configured
    /// by their payload rather than by a scalar.
    public var hasIntensity: Bool {
        switch self {
        case .mono, .lut, .chromaKey: return false
        case .brightness, .contrast, .saturation, .exposure, .sepia,
             .gaussianBlur, .vignette, .sharpen, .zoomBlur, .glow: return true
        }
    }
}

extension Filter {

    /// Which ``FilterKind`` this filter is.
    ///
    /// Exhaustive by construction: a new `Filter` case fails to compile here
    /// until it is given a kind, which is what keeps ``FilterKind/allCases``
    /// honest.
    ///
    /// Added in v0.22.
    public var kind: FilterKind {
        switch self {
        case .brightness:   return .brightness
        case .contrast:     return .contrast
        case .saturation:   return .saturation
        case .exposure:     return .exposure
        case .sepia:        return .sepia
        case .mono:         return .mono
        case .gaussianBlur: return .gaussianBlur
        case .vignette:     return .vignette
        case .sharpen:      return .sharpen
        case .zoomBlur:     return .zoomBlur
        case .glow:         return .glow
        case .lut:          return .lut
        case .chromaKey:    return .chromaKey
        }
    }
}
