import Foundation

extension Video {
    /// Add a watermark image to the composition. Sugar over ``overlay(_:)`` with
    /// watermark-typical defaults: bottom-right corner, anchored so the image sits
    /// flush in that corner, 60% opacity, layer ID `"watermark"`.
    ///
    /// ```swift
    /// Video {
    ///     VideoClip(url: clipURL)
    /// }
    /// .watermark(logo)                                                  // bottom-right, 60%
    /// .watermark(logo, position: .topRight, opacity: 0.4)               // tweak corner / opacity
    /// .watermark(logo, size: .normalized(width: 0.1, height: 0.05))     // explicit size
    /// .export(to: outputURL)
    /// ```
    ///
    /// For anything more complex (custom anchor, layer ID, padding from the edge), drop
    /// down to ``overlay(_:)`` with a hand-built ``ImageOverlay``.
    public func watermark(
        _ image: PlatformImage,
        position: Position = .bottomRight,
        size: Size? = nil,
        opacity: Double = 0.6
    ) -> Video {
        var overlayInstance = ImageOverlay(image)
            .position(position)
            .anchor(Self.defaultAnchor(for: position))
            .opacity(opacity)
            .id("watermark")
        if let size {
            overlayInstance = overlayInstance.size(size)
        }
        return overlay(overlayInstance)
    }

    /// Match a `Position` to the Anchor that pins the overlay flush against that point.
    /// For non-named positions (custom `.normalized` / `.pixels` / `.percent` values),
    /// falls back to `.center`.
    private static func defaultAnchor(for position: Position) -> Anchor {
        if position == .topLeft     { return .topLeft }
        if position == .top         { return .top }
        if position == .topRight    { return .topRight }
        if position == .left        { return .left }
        if position == .center      { return .center }
        if position == .right       { return .right }
        if position == .bottomLeft  { return .bottomLeft }
        if position == .bottom      { return .bottom }
        if position == .bottomRight { return .bottomRight }
        return .center
    }
}
