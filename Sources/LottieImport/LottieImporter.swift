//
//  LottieImporter.swift
//  PureLottie
//

import Foundation
import LottieModel
import PureLayer

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

/// Shared state for one import walk.
final class ImportContext {
    let animation: LottieAnimation
    let report = ImportReportBuilder()
    /// Seconds added to every created animation's `beginTime` (precomp offset).
    var timeShift: Double = 0
    /// Recursion guard against precomposition reference cycles.
    var precompositionStack: [String] = []

    var frameRate: Double { animation.frameRate }
    var startFrame: Double { animation.inPoint }
    var duration: Double { max((animation.outPoint - animation.inPoint) / animation.frameRate, 0) }

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
        build(layers: animation.layers, into: root, context: context, at: "root")
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
    private func build(layers: [LottieLayer], into container: Layer, context: ImportContext, at path: String) {
        let byIndex = Dictionary(layers.compactMap { layer in layer.index.map { ($0, layer) } }, uniquingKeysWith: { first, _ in first })
        for lottieLayer in layers.reversed() {
            guard !lottieLayer.isHidden else { continue }
            let layerPath = "\(path) > layer '\(lottieLayer.name ?? "?")'"
            guard let built = buildLayer(lottieLayer, context: context, at: layerPath) else { continue }
            let wrapped = wrappedInParentChain(built, of: lottieLayer, byIndex: byIndex, context: context, at: layerPath)
            container.addSublayer(wrapped)
        }
    }

    private func buildLayer(_ lottieLayer: LottieLayer, context: ImportContext, at path: String) -> Layer? {
        let layer: Layer
        switch lottieLayer.type {
        case .shape:
            layer = Layer()
            layer.backgroundColor = nil
            bounds(of: lottieLayer, context: context).map { layer.bounds = $0 }
            let builder = ShapeBuilder(context: context)
            for sublayer in builder.layers(for: lottieLayer.shapes ?? [], bounds: layer.bounds, at: path) {
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
            if abs(lottieLayer.stretch - 1) > 0.0001 {
                context.report.skip("precomposition time stretch", at: path)
            }
            layer = Layer()
            layer.backgroundColor = nil
            layer.bounds = Rect(x: 0, y: 0, width: lottieLayer.width ?? context.animation.width, height: lottieLayer.height ?? context.animation.height)
            layer.masksToBounds = true
            let outerShift = context.timeShift
            context.timeShift = outerShift + lottieLayer.startTime / context.frameRate
            context.precompositionStack.append(referenceId)
            build(layers: assetLayers, into: layer, context: context, at: "\(path) > precomp '\(referenceId)'")
            context.precompositionStack.removeLast()
            context.timeShift = outerShift
        default:
            context.report.skip("layer type \(lottieLayer.rawType)", at: path)
            return nil
        }

        apply(lottieLayer.transform, to: layer, context: context, at: path, includeOpacity: true, visibility: visibilityWindow(of: lottieLayer, context: context))
        applyMasks(lottieLayer, to: layer, context: context, at: path)
        return layer
    }

    /// The comp-sized bounds a shape or null layer lives in (its coordinate
    /// space is the composition's).
    private func bounds(of lottieLayer: LottieLayer, context: ImportContext) -> Rect? {
        Rect(x: 0, y: 0, width: context.animation.width, height: context.animation.height)
    }

    /// The layer's visible window in scene seconds, or `nil` when it spans the
    /// whole scene.
    private func visibilityWindow(of lottieLayer: LottieLayer, context: ImportContext) -> (start: Double, end: Double)? {
        let start = max(context.seconds(lottieLayer.inPoint) + context.timeShift, 0)
        let end = min(context.seconds(lottieLayer.outPoint) + context.timeShift, context.duration)
        if start <= 0.0001, end >= context.duration - 0.0001 { return nil }
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
        visibility: (start: Double, end: Double)?
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

        applyPosition(transform?.position, to: layer, context: context, at: path)

        var staticTransform = Transform3D.identity
        var hasStaticTransform = false
        if let scale = transform?.scale {
            if scale.isAnimated {
                addScaleAnimations(scale, to: layer, context: context)
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
                let samples = ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: context.startFrame) { $0 * .pi / 180 }
                if let animation = ScalarTimeline.animation(keyPath: "transform.rotation.z", samples: samples, sceneDuration: context.duration, beginTime: context.timeShift) {
                    layer.add(animation, forKey: "lottie.rotation")
                }
            } else {
                let radians = rotation.initialValue * .pi / 180
                if abs(radians) > 0.0001 {
                    staticTransform = staticTransform.concatenating(.rotation(angle: radians, x: 0, y: 0, z: 1))
                    hasStaticTransform = true
                }
            }
        }
        if hasStaticTransform {
            layer.transform = staticTransform
        }

        if includeOpacity {
            applyOpacity(transform?.opacity, to: layer, context: context, visibility: visibility)
        }
    }

    private func applyPosition(_ position: LottiePosition?, to layer: Layer, context: ImportContext, at path: String) {
        guard let position else {
            layer.position = Point(x: layer.bounds.width * layer.anchorPoint.x, y: layer.bounds.height * layer.anchorPoint.y)
            return
        }
        let initial = position.initialPoint
        layer.position = Point(x: initial.x, y: initial.y)
        guard position.isAnimated else { return }

        func add(_ samples: [TimelineSample], keyPath: String, key: String) {
            if let animation = ScalarTimeline.animation(keyPath: keyPath, samples: samples, sceneDuration: context.duration, beginTime: context.timeShift) {
                layer.add(animation, forKey: key)
            }
        }
        switch position {
        case let .vector(vector):
            guard case let .keyframed(keyframes) = vector else { return }
            if keyframes.contains(where: { ($0.spatialOut ?? []).contains(where: { abs($0) > 0.0001 }) || ($0.spatialIn ?? []).contains(where: { abs($0) > 0.0001 }) }) {
                context.report.approximate("spatial position curve (linearized)", at: path)
            }
            add(ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: context.startFrame) { $0 }, keyPath: "position.x", key: "lottie.position.x")
            add(ScalarTimeline.samples(from: keyframes, dimension: 1, frameRate: context.frameRate, startFrame: context.startFrame) { $0 }, keyPath: "position.y", key: "lottie.position.y")
        case let .split(x, y):
            if case let .keyframed(keyframes) = x {
                add(ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: context.startFrame) { $0 }, keyPath: "position.x", key: "lottie.position.x")
            }
            if case let .keyframed(keyframes) = y {
                add(ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: context.startFrame) { $0 }, keyPath: "position.y", key: "lottie.position.y")
            }
        }
    }

    private func addScaleAnimations(_ scale: AnimatedVector, to layer: Layer, context: ImportContext) {
        guard case let .keyframed(keyframes) = scale else { return }
        let map = { (percent: Double) in percent / 100 }
        let xSamples = ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: context.startFrame, map: map)
        let ySamples = ScalarTimeline.samples(from: keyframes, dimension: 1, frameRate: context.frameRate, startFrame: context.startFrame, map: map)
        if let animation = ScalarTimeline.animation(keyPath: "transform.scale.x", samples: xSamples, sceneDuration: context.duration, beginTime: context.timeShift) {
            layer.add(animation, forKey: "lottie.scale.x")
        }
        if let animation = ScalarTimeline.animation(keyPath: "transform.scale.y", samples: ySamples, sceneDuration: context.duration, beginTime: context.timeShift) {
            layer.add(animation, forKey: "lottie.scale.y")
        }
    }

    /// Opacity and the in/out visibility window share the `opacity` key path,
    /// so they are merged into one sampled timeline.
    private func applyOpacity(_ opacity: AnimatedDouble?, to layer: Layer, context: ImportContext, visibility: (start: Double, end: Double)?) {
        let map = { (percent: Double) in min(max(percent / 100, 0), 1) }
        var samples: [TimelineSample]?
        if case let .keyframed(keyframes) = opacity {
            samples = ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: context.startFrame, map: map)
        }
        let staticValue = map(opacity?.initialValue ?? 100)
        switch (samples, visibility) {
        case (nil, nil):
            layer.opacity = staticValue
        case let (nil, .some(window)):
            layer.opacity = staticValue
            let constant = [TimelineSample(time: 0, value: staticValue), TimelineSample(time: context.duration, value: staticValue)]
            let gated = ScalarTimeline.gated(constant, window: window, duration: context.duration)
            if let animation = ScalarTimeline.animation(keyPath: "opacity", samples: gated, sceneDuration: context.duration, beginTime: context.timeShift) {
                layer.add(animation, forKey: "lottie.opacity")
            }
        case let (.some(timeline), nil):
            if let animation = ScalarTimeline.animation(keyPath: "opacity", samples: timeline, sceneDuration: context.duration, beginTime: context.timeShift) {
                layer.add(animation, forKey: "lottie.opacity")
            }
        case let (.some(timeline), .some(window)):
            let gated = ScalarTimeline.gated(timeline, window: window, duration: context.duration)
            if let animation = ScalarTimeline.animation(keyPath: "opacity", samples: gated, sceneDuration: context.duration, beginTime: context.timeShift) {
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
        at path: String
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
            apply(ancestor.transform, to: holder, context: context, at: "\(path) > parent '\(ancestor.name ?? "?")'", includeOpacity: false, visibility: nil)
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
