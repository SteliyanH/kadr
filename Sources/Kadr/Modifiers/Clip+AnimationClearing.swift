import Foundation
import CoreMedia

// MARK: - Animation-clearing modifiers (v0.10.1)

// Closes the install-but-can't-uninstall asymmetry on every animatable
// property. Each modifier replaces just the animation field, preserving
// the static base value and every other field. Pass `nil` to clear; pass
// a new `Animation<T>` to swap in.
//
// Companion to the v0.8 `transform(_:animation:)` / `opacity(_:animation:)` /
// `filter(_:animation:)` modifiers, which install but require a full
// reconstruction to clear.

extension VideoClip {

    /// Replace the transform animation, preserving the static base
    /// transform. Pass `nil` to clear; the engine then renders the static
    /// transform at every frame.
    ///
    /// Companion to ``transform(_:animation:)``. Use that when setting both
    /// fields together; reach for this one to swap out (or clear) the
    /// animation while keeping the static base value untouched.
    /// Added in v0.10.1.
    public func transformAnimation(_ animation: Animation<Transform>?) -> VideoClip {
        VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: speedRate,
            filters: filters,
            filterAnimations: filterAnimations,
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: animation,
            opacity: opacity,
            opacityAnimation: opacityAnimation,
            speedCurve: speedCurve
        )
    }

    /// Replace the opacity animation, preserving the static base opacity.
    /// Pass `nil` to clear. Added in v0.10.1.
    public func opacityAnimation(_ animation: Animation<Double>?) -> VideoClip {
        VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: speedRate,
            filters: filters,
            filterAnimations: filterAnimations,
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: animation,
            speedCurve: speedCurve
        )
    }

    /// Replace the animation on `filters[index]`. Pass `nil` to clear.
    /// No-op if `index` is out of range — the clip is returned unchanged
    /// rather than throwing, matching the editor-consumer mental model
    /// where stale indices can race with reorders. Added in v0.10.1.
    public func filterAnimation(at index: Int, _ animation: Animation<Double>?) -> VideoClip {
        guard index >= 0, index < filterAnimations.count else { return self }
        var newAnimations = filterAnimations
        newAnimations[index] = animation
        return VideoClip(
            url: url,
            trimRange: trimRange,
            isReversed: isReversed,
            isMuted: isMuted,
            replacementAudioURL: replacementAudioURL,
            speedRate: speedRate,
            filters: filters,
            filterAnimations: newAnimations,
            compositors: compositors,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: opacityAnimation,
            speedCurve: speedCurve
        )
    }
}

extension ImageClip {

    /// Replace the transform animation, preserving the static base. Pass
    /// `nil` to clear. Added in v0.10.1.
    public func transformAnimation(_ animation: Animation<Transform>?) -> ImageClip {
        ImageClip(
            image: image,
            duration: _duration,
            backgroundColor: backgroundColor,
            audioURL: audioURL,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: animation,
            opacity: opacity,
            opacityAnimation: opacityAnimation
        )
    }

    /// Replace the opacity animation, preserving the static base. Pass
    /// `nil` to clear. Added in v0.10.1.
    public func opacityAnimation(_ animation: Animation<Double>?) -> ImageClip {
        ImageClip(
            image: image,
            duration: _duration,
            backgroundColor: backgroundColor,
            audioURL: audioURL,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: animation
        )
    }
}

extension TitleSequence {

    /// Replace the transform animation, preserving the static base. Pass
    /// `nil` to clear. Added in v0.10.1.
    public func transformAnimation(_ animation: Animation<Transform>?) -> TitleSequence {
        TitleSequence(
            text: text,
            duration: _duration,
            style: style,
            backgroundColor: backgroundColor,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: animation,
            opacity: opacity,
            opacityAnimation: opacityAnimation
        )
    }

    /// Replace the opacity animation, preserving the static base. Pass
    /// `nil` to clear. Added in v0.10.1.
    public func opacityAnimation(_ animation: Animation<Double>?) -> TitleSequence {
        TitleSequence(
            text: text,
            duration: _duration,
            style: style,
            backgroundColor: backgroundColor,
            clipID: clipID,
            startTime: startTime,
            transform: transform,
            transformAnimation: transformAnimation,
            opacity: opacity,
            opacityAnimation: animation
        )
    }
}

extension ImageOverlay {

    /// Replace the position animation, preserving the static base. Pass
    /// `nil` to clear. Added in v0.10.1.
    public func positionAnimation(_ animation: Animation<Position>?) -> ImageOverlay {
        ImageOverlay(
            image: image,
            position: position,
            size: size,
            anchor: anchor,
            opacity: opacity,
            layerID: layerID,
            visibilityRange: visibilityRange,
            positionAnimation: animation,
            sizeAnimation: sizeAnimation
        )
    }

    /// Replace the size animation, preserving the static base. Pass `nil`
    /// to clear. Added in v0.10.1.
    public func sizeAnimation(_ animation: Animation<Size>?) -> ImageOverlay {
        ImageOverlay(
            image: image,
            position: position,
            size: size,
            anchor: anchor,
            opacity: opacity,
            layerID: layerID,
            visibilityRange: visibilityRange,
            positionAnimation: positionAnimation,
            sizeAnimation: animation
        )
    }
}

extension StickerOverlay {

    /// Replace the position animation, preserving the static base. Pass
    /// `nil` to clear. Added in v0.10.1.
    public func positionAnimation(_ animation: Animation<Position>?) -> StickerOverlay {
        StickerOverlay(
            image: image,
            position: position,
            size: size,
            anchor: anchor,
            opacity: opacity,
            layerID: layerID,
            rotation: rotation,
            shadow: shadow,
            visibilityRange: visibilityRange,
            positionAnimation: animation,
            sizeAnimation: sizeAnimation
        )
    }

    /// Replace the size animation, preserving the static base. Pass `nil`
    /// to clear. Added in v0.10.1.
    public func sizeAnimation(_ animation: Animation<Size>?) -> StickerOverlay {
        StickerOverlay(
            image: image,
            position: position,
            size: size,
            anchor: anchor,
            opacity: opacity,
            layerID: layerID,
            rotation: rotation,
            shadow: shadow,
            visibilityRange: visibilityRange,
            positionAnimation: positionAnimation,
            sizeAnimation: animation
        )
    }
}
