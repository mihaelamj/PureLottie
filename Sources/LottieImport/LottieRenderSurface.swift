//
//  LottieRenderSurface.swift
//  PureLottie
//

import PureLayer

/// Helpers for placing a Lottie scene on a concrete PureLayer render surface.
public enum LottieRenderSurface {
    /// The pixel dimensions used when rendering a composition at `scale`.
    public static func pixelSize(width: Double, height: Double, scale: Double) -> PixelSize {
        PixelSize(
            width: max(1, Int((width * scale).rounded())),
            height: max(1, Int((height * scale).rounded()))
        )
    }

    /// The pixel dimensions used when rendering a scene at `scale`.
    public static func pixelSize(for scene: LottieScene, scale: Double) -> PixelSize {
        pixelSize(width: scene.width, height: scene.height, scale: scale)
    }

    /// Returns a root layer that renders the Lottie composition at `scale`.
    ///
    /// PureLayer render backends map layer points to output pixels directly. A
    /// larger output surface therefore needs an explicit scale transform, or the
    /// composition remains pinned into the upper-left portion of the canvas.
    public static func root(for scene: LottieScene, scale: Double) -> Layer {
        root(scene.root, width: scene.width, height: scene.height, scale: scale)
    }

    /// Returns a root layer that renders `root` at `scale`.
    public static func root(_ root: Layer, width: Double, height: Double, scale: Double) -> Layer {
        guard abs(scale - 1) > 0.0001 else { return root }
        let scaled = scaledLayer(root, scale: scale)
        scaled.bounds = Rect(x: 0, y: 0, width: width * scale, height: height * scale)
        scaled.position = Point(x: scaled.bounds.width / 2, y: scaled.bounds.height / 2)
        return scaled
    }

    private static func scaledLayer(_ layer: Layer, scale: Double) -> Layer {
        let copy = layer.makeCopy()
        copy.copyProperties(from: layer)
        applyScale(scale, to: copy)
        let carrierAnchor = carrierAnchor(for: copy, hasSublayers: !layer.sublayers.isEmpty)
        if let carrierAnchor {
            foldCarrierPositionIntoTransform(
                copy,
                anchor: carrierAnchor,
                animatesX: hasAnimation(layer, keyPath: "position.x"),
                animatesY: hasAnimation(layer, keyPath: "position.y")
            )
        }
        copy.mask = layer.mask.map { scaledLayer($0, scale: scale) }
        copyAnimations(from: layer, to: copy, scale: scale, carrierAnchor: carrierAnchor)
        for sublayer in layer.sublayers {
            copy.addSublayer(scaledLayer(sublayer, scale: scale))
        }
        return copy
    }

    private static func applyScale(_ scale: Double, to layer: Layer) {
        layer.bounds = scaled(layer.bounds, by: scale)
        layer.position = scaled(layer.position, by: scale)
        layer.transform = scaled(layer.transform, by: scale)
        layer.sublayerTransform = scaled(layer.sublayerTransform, by: scale)
        layer.zPosition *= scale
        layer.anchorPointZ *= scale
        layer.contentsScale *= scale
        layer.cornerRadius *= scale
        layer.borderWidth *= scale
        layer.shadowOffset = scaled(layer.shadowOffset, by: scale)
        layer.shadowRadius *= scale
        layer.shadowPath = layer.shadowPath?.applying(AffineTransform.scale(x: scale, y: scale))

        if let shape = layer as? ShapeLayer {
            shape.path = shape.path?.applying(AffineTransform.scale(x: scale, y: scale))
            shape.lineWidth *= scale
        }
        if let text = layer as? TextLayer {
            text.fontSize *= scale
        }
    }

    private static func carrierAnchor(for layer: Layer, hasSublayers: Bool) -> Point? {
        guard hasSublayers,
              layer.backgroundColor == nil,
              layer.contents == nil,
              !(layer is ShapeLayer),
              !(layer is GradientLayer),
              !(layer is TextLayer)
        else {
            return nil
        }
        return Point(
            x: layer.bounds.width * layer.anchorPoint.x,
            y: layer.bounds.height * layer.anchorPoint.y
        )
    }

    private static func foldCarrierPositionIntoTransform(
        _ layer: Layer,
        anchor: Point,
        animatesX: Bool,
        animatesY: Bool
    ) {
        let frameOrigin = layer.frame.origin
        let translationX = animatesX ? 0 : frameOrigin.x
        let translationY = animatesY ? 0 : frameOrigin.y
        if abs(translationX) > 0.0001 || abs(translationY) > 0.0001 {
            layer.transform = layer.transform.concatenating(.translation(x: translationX, y: translationY, z: 0))
        }
        layer.position = anchor
    }

    private static func scaled(_ point: Point, by scale: Double) -> Point {
        Point(x: point.x * scale, y: point.y * scale)
    }

    private static func scaled(_ rect: Rect, by scale: Double) -> Rect {
        Rect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private static func scaled(_ transform: Transform3D, by scale: Double) -> Transform3D {
        var scaled = transform
        scaled.m41 *= scale
        scaled.m42 *= scale
        return scaled
    }

    private static func copyAnimations(
        from source: Layer,
        to destination: Layer,
        scale: Double,
        carrierAnchor: Point?
    ) {
        for key in source.animationKeys() {
            guard let animation = source.animation(forKey: key),
                  let clone = clonedAnimation(animation, scale: scale, carrierAnchor: carrierAnchor)
            else {
                continue
            }
            destination.add(clone, forKey: key)
        }
    }

    private static func clonedAnimation(
        _ animation: Animation,
        scale: Double,
        carrierAnchor: Point?
    ) -> Animation? {
        switch animation {
        case let animation as KeyframeAnimation:
            let clone = KeyframeAnimation(keyPath: scaledKeyPath(animation.keyPath, carrierAnchor: carrierAnchor), timing: animation.timing)
            copyCommonAnimationState(from: animation, to: clone)
            clone.keyPath = scaledKeyPath(animation.keyPath, carrierAnchor: carrierAnchor)
            clone.values = animation.values.map { scaledValue($0, keyPath: animation.keyPath, scale: scale, carrierAnchor: carrierAnchor) }
            clone.keyTimes = animation.keyTimes
            clone.calculationMode = animation.calculationMode
            return clone
        case let animation as BasicAnimation:
            let clone = BasicAnimation(keyPath: scaledKeyPath(animation.keyPath, carrierAnchor: carrierAnchor), timing: animation.timing)
            copyCommonAnimationState(from: animation, to: clone)
            clone.keyPath = scaledKeyPath(animation.keyPath, carrierAnchor: carrierAnchor)
            if shouldScale(keyPath: animation.keyPath) {
                clone.fromValue = animation.fromValue.map { scaledValue($0, keyPath: animation.keyPath, scale: scale, carrierAnchor: carrierAnchor) }
                clone.toValue = animation.toValue.map { scaledValue($0, keyPath: animation.keyPath, scale: scale, carrierAnchor: carrierAnchor) }
                clone.byValue = animation.byValue.map { $0 * scale }
            } else {
                clone.fromValue = animation.fromValue
                clone.toValue = animation.toValue
                clone.byValue = animation.byValue
            }
            return clone
        case let animation as SpringAnimation:
            let clone = SpringAnimation(keyPath: scaledKeyPath(animation.keyPath, carrierAnchor: carrierAnchor), spring: animation.spring)
            copyCommonAnimationState(from: animation, to: clone)
            clone.keyPath = scaledKeyPath(animation.keyPath, carrierAnchor: carrierAnchor)
            if shouldScale(keyPath: animation.keyPath) {
                clone.fromValue = animation.fromValue.map { scaledValue($0, keyPath: animation.keyPath, scale: scale, carrierAnchor: carrierAnchor) }
                clone.toValue = animation.toValue.map { scaledValue($0, keyPath: animation.keyPath, scale: scale, carrierAnchor: carrierAnchor) }
            } else {
                clone.fromValue = animation.fromValue
                clone.toValue = animation.toValue
            }
            clone.initialVelocity = animation.initialVelocity
            return clone
        case let animation as ColorAnimation:
            let clone = ColorAnimation(keyPath: animation.keyPath, timing: animation.timing)
            copyCommonAnimationState(from: animation, to: clone)
            clone.fromColor = animation.fromColor
            clone.toColor = animation.toColor
            return clone
        case let animation as AnimationGroup:
            let clone = AnimationGroup(timing: animation.timing)
            copyBaseAnimationState(from: animation, to: clone)
            clone.animations = animation.animations.compactMap {
                clonedAnimation($0, scale: scale, carrierAnchor: carrierAnchor)
            }
            return clone
        default:
            return nil
        }
    }

    private static func scaledKeyPath(_ keyPath: String?, carrierAnchor: Point?) -> String? {
        guard carrierAnchor != nil else { return keyPath }
        switch keyPath {
        case "position.x":
            return "transform.translation.x"
        case "position.y":
            return "transform.translation.y"
        default:
            return keyPath
        }
    }

    private static func scaledValue(
        _ value: Double,
        keyPath: String?,
        scale: Double,
        carrierAnchor: Point?
    ) -> Double {
        guard shouldScale(keyPath: keyPath) else { return value }
        let scaled = value * scale
        guard let carrierAnchor else { return scaled }
        switch keyPath {
        case "position.x":
            return scaled - carrierAnchor.x
        case "position.y":
            return scaled - carrierAnchor.y
        default:
            return scaled
        }
    }

    private static func hasAnimation(_ animation: Animation, keyPath: String) -> Bool {
        if let property = animation as? PropertyAnimation, property.keyPath == keyPath {
            return true
        }
        if let group = animation as? AnimationGroup {
            return group.animations.contains { hasAnimation($0, keyPath: keyPath) }
        }
        return false
    }

    private static func hasAnimation(_ layer: Layer, keyPath: String) -> Bool {
        layer.animationKeys().contains { key in
            guard let animation = layer.animation(forKey: key) else { return false }
            return hasAnimation(animation, keyPath: keyPath)
        }
    }

    private static func copyCommonAnimationState(from source: PropertyAnimation, to destination: PropertyAnimation) {
        copyBaseAnimationState(from: source, to: destination)
        destination.keyPath = source.keyPath
        destination.isAdditive = source.isAdditive
        destination.isCumulative = source.isCumulative
    }

    private static func copyBaseAnimationState(from source: Animation, to destination: Animation) {
        destination.timing = source.timing
        destination.timingFunction = source.timingFunction
        destination.isRemovedOnCompletion = source.isRemovedOnCompletion
    }

    private static func shouldScale(keyPath: String?) -> Bool {
        switch keyPath {
        case "position.x",
             "position.y",
             "bounds.origin.x",
             "bounds.origin.y",
             "bounds.size.width",
             "bounds.size.height",
             "transform.translation.x",
             "transform.translation.y":
            true
        default:
            false
        }
    }
}
