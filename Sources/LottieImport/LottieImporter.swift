//
//  LottieImporter.swift
//  PureLottie
//

import Foundation
import LottieModel
import PureLayer

/// The result of an import: a PureLayer tree plus the timing facts needed to
/// drive it, and the report of everything that did not map exactly.
/// The result of an import: a PureLayer tree plus the timing facts needed to
/// drive it, and the report of everything that did not map exactly.
public struct LottieScene {
    public let root: Layer
    public let width: Double
    public let height: Double
    /// Seconds from the composition's in-point to its out-point.
    public let duration: Double
    public let frameRate: Double
    public let report: ImportReport
}

/// Tracks hierarchical timing (speed, beginTime, duration, startFrame) to properly map Lottie animations.
struct LayerTiming: Equatable {
    var speed: Double = 1.0
    var beginTime: Double = 0.0
    var duration: Double = 0.0
    var startFrame: Double = 0.0
}

/// Shared state for one import walk.
final class ImportContext {
    let animation: LottieAnimation
    let report = ImportReportBuilder()
    /// Recursion guard against precomposition reference cycles.
    var precompositionStack: [String] = []

    var frameRate: Double {
        animation.frameRate
    }

    var startFrame: Double {
        animation.inPoint
    }

    var duration: Double {
        max((animation.outPoint - animation.inPoint) / animation.frameRate, 0)
    }

    init(animation: LottieAnimation) {
        self.animation = animation
    }

    func seconds(_ frame: Double) -> Double {
        (frame - startFrame) / frameRate
    }
}

/// Maps a decoded `LottieAnimation` onto a PureLayer tree.
///
/// Supported subset (everything else lands in the `ImportReport`): shape layers
/// (paths, rectangles, ellipses, solid fills, strokes, trim paths including
/// animated trim), solids, nulls, precompositions without time stretch, layer
/// transforms with animated position/scale/rotation/opacity, in/out visibility
/// windows, transform parenting, and single additive alpha masks.
public struct LottieImporter {
    public init() {}

    public func scene(from animation: LottieAnimation) -> LottieScene {
        let context = ImportContext(animation: animation)
        let root = Layer()
        root.bounds = Rect(x: 0, y: 0, width: animation.width, height: animation.height)
        root.position = Point(x: animation.width / 2, y: animation.height / 2)
        root.masksToBounds = true
        let rootTiming = LayerTiming(speed: 1.0, beginTime: 0.0, duration: context.duration, startFrame: context.startFrame)
        build(layers: animation.layers, into: root, context: context, at: "root", parentTiming: rootTiming)
        return LottieScene(
            root: root,
            width: animation.width,
            height: animation.height,
            duration: context.duration,
            frameRate: animation.frameRate,
            report: context.report.report()
        )
    }

    // MARK: Layer walk

    /// Builds one composition's layers into `container`. Lottie lists the
    /// topmost layer first; PureLayer draws later sublayers on top, so the list
    /// is walked in reverse.
    private func build(layers: [LottieLayer], into container: Layer, context: ImportContext, at path: String, parentTiming: LayerTiming) {
        let byIndex = Dictionary(layers.compactMap { layer in layer.index.map { ($0, layer) } }, uniquingKeysWith: { first, _ in first })
        for lottieLayer in layers.reversed() {
            guard !lottieLayer.isHidden else { continue }
            let layerPath = "\(path) > layer '\(lottieLayer.name ?? "?")'"

            let layerStart = lottieLayer.startTime / context.frameRate
            let layerSpeed = lottieLayer.stretch
            let speed = parentTiming.speed / layerSpeed
            let beginTime = parentTiming.beginTime + layerStart / speed
            let duration = parentTiming.duration / layerSpeed
            let timing = LayerTiming(speed: speed, beginTime: beginTime, duration: duration, startFrame: parentTiming.startFrame)

            guard let built = buildLayer(lottieLayer, context: context, at: layerPath, parentTiming: parentTiming, timing: timing) else { continue }
            let wrapped = wrappedInParentChain(built, of: lottieLayer, byIndex: byIndex, context: context, at: layerPath, parentTiming: parentTiming)
            container.addSublayer(wrapped)
        }
    }

    private func buildLayer(_ lottieLayer: LottieLayer, context: ImportContext, at path: String, parentTiming: LayerTiming, timing: LayerTiming) -> Layer? {
        let layer: Layer
        switch lottieLayer.type {
        case .shape:
            layer = Layer()
            layer.backgroundColor = nil
            bounds(of: lottieLayer, context: context).map { layer.bounds = $0 }
            let builder = ShapeBuilder(context: context)
            for sublayer in builder.layers(for: lottieLayer.shapes ?? [], bounds: layer.bounds, at: path, timing: timing) {
                layer.addSublayer(sublayer)
            }
        case .solid:
            layer = Layer()
            layer.bounds = Rect(x: 0, y: 0, width: lottieLayer.solidWidth ?? 0, height: lottieLayer.solidHeight ?? 0)
            layer.backgroundColor = Self.color(hex: lottieLayer.solidColor ?? "#000000")
        case .null:
            layer = Layer()
            layer.backgroundColor = nil
            bounds(of: lottieLayer, context: context).map { layer.bounds = $0 }
        case .precomposition:
            guard let referenceId = lottieLayer.referenceId,
                  let asset = context.animation.precomposition(id: referenceId),
                  let assetLayers = asset.layers
            else {
                context.report.skip("precomposition with missing asset", at: path)
                return nil
            }
            guard !context.precompositionStack.contains(referenceId) else {
                context.report.skip("recursive precomposition '\(referenceId)'", at: path)
                return nil
            }
            layer = Layer()
            layer.backgroundColor = nil
            layer.bounds = Rect(x: 0, y: 0, width: lottieLayer.width ?? context.animation.width, height: lottieLayer.height ?? context.animation.height)
            layer.masksToBounds = true
            let assetParentTiming = LayerTiming(speed: timing.speed, beginTime: timing.beginTime, duration: timing.duration, startFrame: 0.0)
            context.precompositionStack.append(referenceId)
            build(layers: assetLayers, into: layer, context: context, at: "\(path) > precomp '\(referenceId)'", parentTiming: assetParentTiming)
            context.precompositionStack.removeLast()
        default:
            context.report.skip("layer type \(lottieLayer.rawType)", at: path)
            return nil
        }

        apply(
            lottieLayer.transform,
            to: layer,
            context: context,
            at: path,
            includeOpacity: true,
            visibility: visibilityWindow(of: lottieLayer, context: context, parentTiming: parentTiming, childTiming: timing),
            timing: timing
        )
        applyMasks(lottieLayer, to: layer, context: context, at: path)
        return layer
    }

    /// The comp-sized bounds a shape or null layer lives in (its coordinate
    /// space is the composition's).
    private func bounds(of _: LottieLayer, context: ImportContext) -> Rect? {
        Rect(x: 0, y: 0, width: context.animation.width, height: context.animation.height)
    }

    /// The layer's visible window in scene seconds, or `nil` when it spans the
    /// whole scene.
    private func visibilityWindow(
        of lottieLayer: LottieLayer,
        context: ImportContext,
        parentTiming: LayerTiming,
        childTiming: LayerTiming
    ) -> (start: Double, end: Double)? {
        let parentStart = (lottieLayer.inPoint - parentTiming.startFrame) / context.frameRate
        let parentEnd = (lottieLayer.outPoint - parentTiming.startFrame) / context.frameRate
        let start = max(parentStart / lottieLayer.stretch - lottieLayer.startTime / context.frameRate, 0)
        let end = min(parentEnd / lottieLayer.stretch - lottieLayer.startTime / context.frameRate, childTiming.duration)
        if start <= 0.0001, end >= childTiming.duration - 0.0001 { return nil }
        guard end > start else { return (0, 0) }
        return (start, end)
    }

    // MARK: Transform mapping

    /// Maps the Lottie transform onto CA-style layer geometry: `p` is the
    /// position of the anchor in the parent, `a` the anchor in points, scale
    /// and rotation compose about the anchor. Animated components become
    /// keyframe animations on the engine's own key paths; their static initial
    /// values are deliberately not baked, since the animations span the whole
    /// scene with `fillMode: .both`.
    private func apply(
        _ transform: LottieTransform?,
        to layer: Layer,
        context: ImportContext,
        at path: String,
        includeOpacity: Bool,
        visibility: (start: Double, end: Double)?,
        timing: LayerTiming
    ) {
        let anchor = transform?.anchor?.initialValue ?? []
        if transform?.anchor?.isAnimated == true {
            context.report.skip("animated anchor point", at: path)
        }
        let anchorX = anchor.component(0) ?? 0
        let anchorY = anchor.component(1) ?? 0
        if layer.bounds.width > 0, layer.bounds.height > 0 {
            layer.anchorPoint = Point(x: anchorX / layer.bounds.width, y: anchorY / layer.bounds.height)
        }

        applyPosition(transform?.position, to: layer, context: context, at: path, timing: timing)

        var staticTransform = Transform3D.identity
        var hasStaticTransform = false
        if let scale = transform?.scale {
            if scale.isAnimated {
                addScaleAnimations(scale, to: layer, context: context, timing: timing)
            } else {
                let value = scale.initialValue
                let x = (value.component(0) ?? 100) / 100
                let y = (value.component(1) ?? 100) / 100
                if abs(x - 1) > 0.0001 || abs(y - 1) > 0.0001 {
                    staticTransform = staticTransform.concatenating(.scale(x: x, y: y, z: 1))
                    hasStaticTransform = true
                }
            }
        }
        if let rotation = transform?.rotation {
            if case let .keyframed(keyframes) = rotation {
                let samples = ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: timing.startFrame) { $0 * .pi / 180 }
                if let animation = ScalarTimeline.animation(
                    keyPath: "transform.rotation.z",
                    samples: samples,
                    duration: timing.duration,
                    beginTime: timing.beginTime,
                    speed: timing.speed
                ) {
                    layer.add(animation, forKey: "lottie.rotation")
                }
            } else {
                let radians = rotation.initialValue * .pi / 180
                if abs(radians) > 0.0001 {
                    if transform?.scale?.isAnimated == true {
                        // Bypasses the order-of-operations bug in PureLayer's resolvedTransform:
                        // if scale is animated but rotation is static, concatenating scale onto
                        // the baked rotation transform would scale the rotated axes (shearing).
                        // Animating rotation constantly forces resolvedTransform to start from
                        // identity and concatenate in the correct order (scale then rotate).
                        let samples = [
                            TimelineSample(time: 0, value: radians),
                            TimelineSample(time: timing.duration, value: radians),
                        ]
                        if let animation = ScalarTimeline.animation(
                            keyPath: "transform.rotation.z",
                            samples: samples,
                            duration: timing.duration,
                            beginTime: timing.beginTime,
                            speed: timing.speed
                        ) {
                            layer.add(animation, forKey: "lottie.rotation")
                        }
                    } else {
                        staticTransform = staticTransform.concatenating(.rotation(angle: radians, x: 0, y: 0, z: 1))
                        hasStaticTransform = true
                    }
                }
            }
        }
        if hasStaticTransform {
            layer.transform = staticTransform
        }

        if includeOpacity {
            applyOpacity(transform?.opacity, to: layer, context: context, visibility: visibility, timing: timing)
        }
    }

    private func applyPosition(_ position: LottiePosition?, to layer: Layer, context: ImportContext, at path: String, timing: LayerTiming) {
        guard let position else {
            layer.position = Point(x: layer.bounds.width * layer.anchorPoint.x, y: layer.bounds.height * layer.anchorPoint.y)
            return
        }
        let initial = position.initialPoint
        layer.position = Point(x: initial.x, y: initial.y)
        guard position.isAnimated else { return }

        func add(_ samples: [TimelineSample], keyPath: String, key: String) {
            if let animation = ScalarTimeline.animation(keyPath: keyPath, samples: samples, duration: timing.duration, beginTime: timing.beginTime, speed: timing.speed) {
                layer.add(animation, forKey: key)
            }
        }
        switch position {
        case let .vector(vector):
            guard case let .keyframed(keyframes) = vector else { return }
            if keyframes.contains(where: { ($0.spatialOut ?? []).contains(where: { abs($0) > 0.0001 }) || ($0.spatialIn ?? []).contains(where: { abs($0) > 0.0001 }) }) {
                context.report.approximate("spatial position curve (linearized)", at: path)
            }
            add(
                ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: timing.startFrame) { $0 },
                keyPath: "position.x",
                key: "lottie.position.x"
            )
            add(
                ScalarTimeline.samples(from: keyframes, dimension: 1, frameRate: context.frameRate, startFrame: timing.startFrame) { $0 },
                keyPath: "position.y",
                key: "lottie.position.y"
            )
        case let .split(x, y):
            if case let .keyframed(keyframes) = x {
                add(
                    ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: timing.startFrame) { $0 },
                    keyPath: "position.x",
                    key: "lottie.position.x"
                )
            }
            if case let .keyframed(keyframes) = y {
                add(
                    ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: timing.startFrame) { $0 },
                    keyPath: "position.y",
                    key: "lottie.position.y"
                )
            }
        }
    }

    private func addScaleAnimations(_ scale: AnimatedVector, to layer: Layer, context: ImportContext, timing: LayerTiming) {
        guard case let .keyframed(keyframes) = scale else { return }
        let map = { (percent: Double) in percent / 100 }
        let xSamples = ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: timing.startFrame, map: map)
        let ySamples = ScalarTimeline.samples(from: keyframes, dimension: 1, frameRate: context.frameRate, startFrame: timing.startFrame, map: map)
        if let animation = ScalarTimeline.animation(keyPath: "transform.scale.x", samples: xSamples, duration: timing.duration, beginTime: timing.beginTime, speed: timing.speed) {
            layer.add(animation, forKey: "lottie.scale.x")
        }
        if let animation = ScalarTimeline.animation(keyPath: "transform.scale.y", samples: ySamples, duration: timing.duration, beginTime: timing.beginTime, speed: timing.speed) {
            layer.add(animation, forKey: "lottie.scale.y")
        }
    }

    /// Opacity and the in/out visibility window share the `opacity` key path,
    /// so they are merged into one sampled timeline.
    private func applyOpacity(_ opacity: AnimatedDouble?, to layer: Layer, context: ImportContext, visibility: (start: Double, end: Double)?, timing: LayerTiming) {
        let map = { (percent: Double) in min(max(percent / 100, 0), 1) }
        var samples: [TimelineSample]?
        if case let .keyframed(keyframes) = opacity {
            samples = ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: timing.startFrame, map: map)
        }
        let staticValue = map(opacity?.initialValue ?? 100)
        switch (samples, visibility) {
        case (nil, nil):
            layer.opacity = staticValue
        case let (nil, .some(window)):
            layer.opacity = staticValue
            let constant = [TimelineSample(time: 0, value: staticValue), TimelineSample(time: timing.duration, value: staticValue)]
            let gated = ScalarTimeline.gated(constant, window: window, duration: timing.duration)
            if let animation = ScalarTimeline.animation(keyPath: "opacity", samples: gated, duration: timing.duration, beginTime: timing.beginTime, speed: timing.speed) {
                layer.add(animation, forKey: "lottie.opacity")
            }
        case let (.some(timeline), nil):
            if let animation = ScalarTimeline.animation(keyPath: "opacity", samples: timeline, duration: timing.duration, beginTime: timing.beginTime, speed: timing.speed) {
                layer.add(animation, forKey: "lottie.opacity")
            }
        case let (.some(timeline), .some(window)):
            let gated = ScalarTimeline.gated(timeline, window: window, duration: timing.duration)
            if let animation = ScalarTimeline.animation(keyPath: "opacity", samples: gated, duration: timing.duration, beginTime: timing.beginTime, speed: timing.speed) {
                layer.add(animation, forKey: "lottie.opacity")
            }
        }
    }

    // MARK: Parenting

    /// Wraps `layer` in holder layers replicating each transform ancestor, so
    /// parenting applies transforms (including animated ones) without
    /// disturbing sibling z-order. Lottie parenting inherits transforms only,
    /// never opacity, so holders get no opacity mapping.
    private func wrappedInParentChain(
        _ layer: Layer,
        of lottieLayer: LottieLayer,
        byIndex: [Int: LottieLayer],
        context: ImportContext,
        at path: String,
        parentTiming: LayerTiming
    ) -> Layer {
        var ancestors: [LottieLayer] = []
        var cursor = lottieLayer.parent
        var guardCounter = 0
        while let parentIndex = cursor, let parent = byIndex[parentIndex], guardCounter < 64 {
            ancestors.append(parent)
            cursor = parent.parent
            guardCounter += 1
        }
        guard !ancestors.isEmpty else { return layer }

        var wrapped = layer
        for ancestor in ancestors {
            let holder = Layer()
            holder.backgroundColor = nil
            holder.bounds = Rect(x: 0, y: 0, width: context.animation.width, height: context.animation.height)

            let ancestorStart = ancestor.startTime / context.frameRate
            let ancestorSpeed = ancestor.stretch
            let speed = parentTiming.speed / ancestorSpeed
            let beginTime = parentTiming.beginTime + ancestorStart / speed
            let duration = parentTiming.duration / ancestorSpeed
            let ancestorTiming = LayerTiming(speed: speed, beginTime: beginTime, duration: duration, startFrame: parentTiming.startFrame)

            apply(
                ancestor.transform,
                to: holder,
                context: context,
                at: "\(path) > parent '\(ancestor.name ?? "?")'",
                includeOpacity: false,
                visibility: nil,
                timing: ancestorTiming
            )
            holder.addSublayer(wrapped)
            wrapped = holder
        }
        return wrapped
    }

    // MARK: Masks

    /// Maps a single additive, non-inverted mask onto `layer.mask`; everything
    /// else is reported.
    private func applyMasks(_ lottieLayer: LottieLayer, to layer: Layer, context: ImportContext, at path: String) {
        guard let masks = lottieLayer.masks, !masks.isEmpty else { return }
        guard masks.count == 1, let mask = masks.first else {
            context.report.skip("multiple masks", at: path)
            return
        }
        guard mask.mode == "a" || mask.mode == "n" else {
            context.report.skip("mask mode '\(mask.mode)'", at: path)
            return
        }
        guard mask.mode != "n" else { return }
        if mask.isInverted {
            context.report.skip("inverted mask", at: path)
            return
        }
        if mask.path.isAnimated {
            context.report.approximate("animated mask path (initial shape used)", at: path)
        }
        if mask.opacity?.isAnimated == true {
            context.report.approximate("animated mask opacity (initial value used)", at: path)
        }
        guard let bezier = mask.path.initialValue else { return }
        var geometry = Path()
        PathBuilder.path(from: bezier, into: &geometry)
        let maskLayer = ShapeLayer()
        maskLayer.bounds = layer.bounds
        maskLayer.position = Point(x: layer.bounds.width / 2, y: layer.bounds.height / 2)
        maskLayer.path = geometry
        maskLayer.fillColor = Color(red: 0, green: 0, blue: 0, alpha: min(max((mask.opacity?.initialValue ?? 100) / 100, 0), 1))
        layer.mask = maskLayer
    }

    // MARK: Colors

    /// Parses `#rrggbb` / `#rrggbbaa` solid-layer colors.
    static func color(hex: String) -> Color {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8 else { return Color(red: 0, green: 0, blue: 0, alpha: 1) }
        if digits.count == 6 { digits += "ff" }
        var value: UInt64 = 0
        guard Scanner(string: digits).scanHexInt64(&value) else { return Color(red: 0, green: 0, blue: 0, alpha: 1) }
        return Color(
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            alpha: Double(value & 0xFF) / 255
        )
    }
}
