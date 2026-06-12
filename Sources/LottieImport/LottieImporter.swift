//
//  LottieImporter.swift
//  PureLottie
//

import Foundation
import LottieEvaluation
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
    let frameEvaluator: LottieFrameEvaluator
    let transformEvaluator: LottieTransformEvaluator
    let report = ImportReportBuilder()
    /// Seconds added to every created animation's `beginTime` (precomp offset).
    var timeShift: Double = 0
    /// Recursion guard against precomposition reference cycles.
    var precompositionStack: [String] = []
    /// Size of the composition currently being lowered.
    var compositionSize: (width: Double, height: Double)

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
        frameEvaluator = LottieFrameEvaluator(animation: animation)
        transformEvaluator = LottieTransformEvaluator(animation: animation)
        compositionSize = (animation.width, animation.height)
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

    /// Validates source JSON before decoding and importing.
    ///
    /// This is the safe entry point for external Lottie files. Validation
    /// failures are thrown before any PureLayer tree is built; `ImportReport`
    /// remains reserved for lowering limitations after validation succeeds.
    public func scene(
        from data: Data,
        validator: LottieValidator = LottieValidator()
    ) throws -> LottieScene {
        let document = try LottieSourceDocument.parse(data)
        try document.validate(using: validator)
        let animation = try document.decodeAnimation()
        return scene(from: animation, sourceDocument: document)
    }

    /// Imports an already-decoded document.
    ///
    /// This low-level entry point assumes the caller has already validated the
    /// source or intentionally wants raw model-level behavior for tests.
    public func scene(from animation: LottieAnimation) -> LottieScene {
        scene(from: animation, sourceDocument: nil)
    }

    private func scene(from animation: LottieAnimation, sourceDocument: LottieSourceDocument?) -> LottieScene {
        let context = ImportContext(animation: animation)
        let binding = LottieBinder(animation: animation, sourceDocument: sourceDocument, report: context.report).bind()
        let root = Layer()
        root.bounds = Rect(x: 0, y: 0, width: animation.width, height: animation.height)
        root.position = Point(x: animation.width / 2, y: animation.height / 2)
        root.masksToBounds = true
        build(composition: binding.root, into: root, context: context, binding: binding)
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
    private func build(
        composition: BoundComposition,
        into container: Layer,
        context: ImportContext,
        binding: LottieBinding,
        compositionSizeOverride: (width: Double, height: Double)? = nil
    ) {
        let previousSize = context.compositionSize
        context.compositionSize = compositionSizeOverride ?? composition.sourceSize ?? previousSize
        defer { context.compositionSize = previousSize }

        for boundLayer in composition.layers.reversed() {
            guard !boundLayer.layer.isHidden else { continue }
            guard let built = buildLayer(boundLayer, context: context, binding: binding) else { continue }
            let wrapped = wrappedInParentChain(built, parents: boundLayer.parents, context: context, at: boundLayer.path)
            container.addSublayer(wrapped)
        }
    }

    private func buildLayer(_ boundLayer: BoundLayer, context: ImportContext, binding: LottieBinding) -> Layer? {
        let lottieLayer = boundLayer.layer
        let path = boundLayer.path
        let jsonPath = boundLayer.sourcePath ?? JSONPath()
        if lottieLayer.timeRemap != nil {
            context.report.skip(
                "time remap",
                at: path,
                sourcePath: boundLayer.sourcePath?.appending(.key("tm")),
                sourceRange: sourceRange(for: boundLayer, field: "tm", binding: binding)
            )
        }
        if let source = lottieLayer.trackMatteSource {
            context.report.skip(
                "track matte source marker \(source)",
                at: path,
                sourcePath: boundLayer.sourcePath?.appending(.key("td")),
                sourceRange: sourceRange(for: boundLayer, field: "td", binding: binding)
            )
            return nil
        }

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
                  boundLayer.referencedAsset != nil,
                  let composition = binding.precomposition(id: referenceId)
            else {
                return nil
            }
            guard !context.precompositionStack.contains(referenceId) else {
                context.report.skip(
                    "recursive precomposition '\(referenceId)'",
                    at: path,
                    sourcePath: boundLayer.sourcePath?.appending(.key("refId")),
                    sourceRange: sourceRange(for: boundLayer, field: "refId", binding: binding)
                )
                return nil
            }
            if abs(lottieLayer.stretch - 1) > 0.0001 {
                context.report.skip(
                    "precomposition time stretch",
                    at: path,
                    sourcePath: boundLayer.sourcePath?.appending(.key("sr")),
                    sourceRange: sourceRange(for: boundLayer, field: "sr", binding: binding)
                )
            }
            layer = Layer()
            layer.backgroundColor = nil
            layer.bounds = Rect(x: 0, y: 0, width: lottieLayer.width ?? context.animation.width, height: lottieLayer.height ?? context.animation.height)
            layer.masksToBounds = true
            let outerShift = context.timeShift
            context.timeShift = outerShift + lottieLayer.startTime / context.frameRate
            context.precompositionStack.append(referenceId)
            build(
                composition: composition,
                into: layer,
                context: context,
                binding: binding,
                compositionSizeOverride: (width: layer.bounds.width, height: layer.bounds.height)
            )
            context.precompositionStack.removeLast()
            context.timeShift = outerShift
        case .image:
            if boundLayer.referencedAsset == nil {
                return nil
            }
            context.report.skip(
                "image layer",
                at: path,
                sourcePath: boundLayer.sourcePath?.appending(.key("ty")),
                sourceRange: sourceRange(for: boundLayer, field: "ty", binding: binding)
            )
            return nil
        default:
            context.report.skip(
                "layer type \(lottieLayer.rawType)",
                at: path,
                sourcePath: boundLayer.sourcePath?.appending(.key("ty")),
                sourceRange: sourceRange(for: boundLayer, field: "ty", binding: binding)
            )
            return nil
        }

        if let matte = boundLayer.matte {
            var feature = "track matte mode \(matte.mode)"
            if let source = matte.source {
                feature += " using \(source.path)"
            }
            context.report.skip(
                feature,
                at: path,
                sourcePath: boundLayer.sourcePath?.appending(.key("tt")),
                sourceRange: sourceRange(for: boundLayer, field: "tt", binding: binding)
            )
        }
        apply(
            lottieLayer,
            to: layer,
            context: context,
            at: path,
            jsonPath: jsonPath,
            includeOpacity: true,
            visibility: visibilityWindow(of: lottieLayer, context: context)
        )
        applyMasks(lottieLayer, to: layer, context: context, at: path)
        return layer
    }

    private func sourceRange(for layer: BoundLayer, field: String, binding: LottieBinding) -> SourceRange? {
        binding.sourceRange(at: layer.sourcePath?.appending(.key(field)))
    }

    /// The comp-sized bounds a shape or null layer lives in (its coordinate
    /// space is the composition's).
    private func bounds(of _: LottieLayer, context: ImportContext) -> Rect? {
        Rect(x: 0, y: 0, width: context.compositionSize.width, height: context.compositionSize.height)
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
        _ lottieLayer: LottieLayer,
        to layer: Layer,
        context: ImportContext,
        at path: String,
        jsonPath: JSONPath,
        includeOpacity: Bool,
        visibility: (start: Double, end: Double)?
    ) {
        let transform = lottieLayer.transform
        let evaluated = evaluatedTransformState(for: lottieLayer, context: context, at: path, jsonPath: jsonPath)
        let anchor = evaluated.anchor
        if transform?.anchor?.isAnimated == true {
            context.report.skip("animated anchor point", at: path)
        }
        let anchorX = anchor.component(0) ?? 0
        let anchorY = anchor.component(1) ?? 0
        layer.anchorPointZ = anchor.component(2) ?? 0
        if layer.bounds.width > 0, layer.bounds.height > 0 {
            layer.anchorPoint = Point(x: anchorX / layer.bounds.width, y: anchorY / layer.bounds.height)
        }

        applyPosition(transform?.position, evaluatedPosition: evaluated.position, to: layer, context: context, at: path)
        layer.zPosition = evaluated.position.component(2) ?? 0

        var staticTransform = Transform3D.identity
        var hasStaticTransform = false
        if let scale = transform?.scale {
            if scale.isAnimated {
                addScaleAnimations(scale, to: layer, context: context)
            } else {
                let value = evaluated.scale
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
                let radians = evaluated.rotationZDegrees * .pi / 180
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

    private func evaluatedTransformState(
        for lottieLayer: LottieLayer,
        context: ImportContext,
        at path: String,
        jsonPath: JSONPath
    ) -> LottieTransformState {
        let localFrame = context.frameEvaluator.localFrame(
            for: lottieLayer,
            at: context.startFrame,
            path: jsonPath
        )
        let result = context.transformEvaluator.localTransform(
            for: lottieLayer,
            at: localFrame.value,
            path: jsonPath
        )
        context.report.reportTransformDiagnostics(localFrame.diagnostics + result.diagnostics, at: path)
        return result.value
    }

    private func applyPosition(
        _ position: LottiePosition?,
        evaluatedPosition: [Double],
        to layer: Layer,
        context: ImportContext,
        at path: String
    ) {
        guard let position else {
            layer.position = Point(x: layer.bounds.width * layer.anchorPoint.x, y: layer.bounds.height * layer.anchorPoint.y)
            return
        }
        layer.position = Point(x: evaluatedPosition.component(0) ?? 0, y: evaluatedPosition.component(1) ?? 0)
        guard position.isAnimated else { return }

        func add(_ samples: [TimelineSample], keyPath: String, key: String) {
            if let animation = ScalarTimeline.animation(keyPath: keyPath, samples: samples, sceneDuration: context.duration, beginTime: context.timeShift) {
                layer.add(animation, forKey: key)
            }
        }
        switch position {
        case let .vector(vector):
            guard case let .keyframed(keyframes) = vector else { return }
            if SpatialInterpolationClassifier.containsUnsupportedSpatialInterpolation(keyframes) {
                context.report.approximate("spatial position curve (linearized)", at: path)
            }
            add(
                ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: context.startFrame) { $0 },
                keyPath: "position.x",
                key: "lottie.position.x"
            )
            add(
                ScalarTimeline.samples(from: keyframes, dimension: 1, frameRate: context.frameRate, startFrame: context.startFrame) { $0 },
                keyPath: "position.y",
                key: "lottie.position.y"
            )
        case let .split(x, y, _):
            if case let .keyframed(keyframes) = x {
                add(
                    ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: context.startFrame) { $0 },
                    keyPath: "position.x",
                    key: "lottie.position.x"
                )
            }
            if case let .keyframed(keyframes) = y {
                add(
                    ScalarTimeline.samples(from: keyframes, dimension: 0, frameRate: context.frameRate, startFrame: context.startFrame) { $0 },
                    keyPath: "position.y",
                    key: "lottie.position.y"
                )
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
        parents: [BoundLayerReference],
        context: ImportContext,
        at path: String
    ) -> Layer {
        guard !parents.isEmpty else { return layer }

        var wrapped = layer
        for parent in parents {
            let holder = Layer()
            holder.backgroundColor = nil
            holder.bounds = Rect(x: 0, y: 0, width: context.compositionSize.width, height: context.compositionSize.height)
            apply(
                parent.layer,
                to: holder,
                context: context,
                at: "\(path) > parent '\(parent.layer.name ?? "?")'",
                jsonPath: parent.sourcePath ?? JSONPath(),
                includeOpacity: false,
                visibility: nil
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
