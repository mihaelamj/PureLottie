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

/// Tracks the accumulated static transform (translation, anchor, scale) of parent compositions and layers.
struct AccumulatedTransform: Equatable {
    var position: Point = .init(x: 0, y: 0)
    var anchor: Point = .init(x: 0, y: 0)
    var scale: Double = 1.0
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
    private typealias AffineTransform = PureLayer.AffineTransform

    public init() {}

    public func scene(from animation: LottieAnimation) -> LottieScene {
        let context = ImportContext(animation: animation)
        let root = Layer()
        root.bounds = Rect(x: 0, y: 0, width: animation.width, height: animation.height)
        root.position = Point(x: animation.width / 2, y: animation.height / 2)
        root.masksToBounds = false
        let rootTiming = LayerTiming(speed: 1.0, beginTime: 0.0, duration: context.duration, startFrame: context.startFrame)
        build(layers: animation.layers, into: root, context: context, at: "root", parentTiming: rootTiming, accumulated: AccumulatedTransform())
        return LottieScene(
            root: root,
            width: animation.width,
            height: animation.height,
            duration: context.duration,
            frameRate: animation.frameRate,
            report: context.report.report()
        )
    }

    private func combine(_ child: AccumulatedTransform, with parent: AccumulatedTransform) -> AccumulatedTransform {
        let newScale = child.scale * parent.scale
        let newAnchor = child.anchor
        let newPosition = Point(
            x: (child.position.x - parent.anchor.x) * parent.scale + parent.position.x,
            y: (child.position.y - parent.anchor.y) * parent.scale + parent.position.y
        )
        return AccumulatedTransform(position: newPosition, anchor: newAnchor, scale: newScale)
    }

    private func build(
        layers: [LottieLayer],
        into container: Layer,
        context: ImportContext,
        at path: String,
        parentTiming: LayerTiming,
        accumulated: AccumulatedTransform
    ) {
        var builtLayers: [Int: Layer] = [:]

        // Pre-compute original timelines and timings for all active layers in this composition
        var timelines: [Int: TransformTimeline] = [:]
        var timings: [Int: LayerTiming] = [:]

        for lottieLayer in layers {
            guard let index = lottieLayer.index else { continue }

            let layerStart = lottieLayer.startTime / context.frameRate
            let layerSpeed = lottieLayer.stretch
            let speed = parentTiming.speed / layerSpeed
            let beginTime = parentTiming.beginTime + layerStart / speed
            let duration = parentTiming.duration / layerSpeed
            let timing = LayerTiming(speed: speed, beginTime: beginTime, duration: duration, startFrame: parentTiming.startFrame)

            timings[index] = timing

            let hasValidParent = lottieLayer.parent != nil && layers.contains(where: { $0.index == lottieLayer.parent })
            let layerAccumulated = hasValidParent ? AccumulatedTransform() : accumulated

            let timeline = Self.originalTimeline(
                for: lottieLayer,
                context: context,
                timing: timing,
                accumulated: layerAccumulated
            )
            timelines[index] = timeline
        }

        // Pass 1: Build all layers with timing and properties
        for lottieLayer in layers.reversed() {
            if lottieLayer.isHidden && lottieLayer.index == nil { continue }
            let layerPath = "\(path) > layer '\(lottieLayer.name ?? "?")'"

            let layerStart = lottieLayer.startTime / context.frameRate
            let layerSpeed = lottieLayer.stretch
            let speed = parentTiming.speed / layerSpeed
            let beginTime = parentTiming.beginTime + layerStart / speed
            let duration = parentTiming.duration / layerSpeed
            let timing = LayerTiming(speed: speed, beginTime: beginTime, duration: duration, startFrame: parentTiming.startFrame)

            let hasValidParent = lottieLayer.parent != nil && layers.contains(where: { $0.index == lottieLayer.parent })
            let layerAccumulated = hasValidParent ? AccumulatedTransform() : accumulated

            let finalTimeline: TransformTimeline

            if let index = lottieLayer.index {
                guard let timeline = timelines[index] else { continue }
                finalTimeline = timeline
            } else {
                finalTimeline = Self.originalTimeline(
                    for: lottieLayer,
                    context: context,
                    timing: timing,
                    accumulated: layerAccumulated
                )
            }

            if let built = buildLayer(
                lottieLayer,
                context: context,
                at: layerPath,
                parentTiming: parentTiming,
                timing: timing,
                accumulated: layerAccumulated,
                timeline: finalTimeline
            ) {
                if let index = lottieLayer.index {
                    builtLayers[index] = built
                } else {
                    container.addSublayer(built)
                }
            }
        }

        // Pass 2: Establish actual parent-child relationships in the layer tree
        for lottieLayer in layers.reversed() {
            guard let index = lottieLayer.index,
                  let built = builtLayers[index]
            else { continue }

            if let parentIndex = lottieLayer.parent, let parentLayer = builtLayers[parentIndex] {
                parentLayer.addSublayer(built)
            } else {
                container.addSublayer(built)
            }
        }
    }

    private func buildLayer(
        _ lottieLayer: LottieLayer,
        context: ImportContext,
        at path: String,
        parentTiming: LayerTiming,
        timing: LayerTiming,
        accumulated: AccumulatedTransform,
        timeline: TransformTimeline
    ) -> Layer? {
        let layer: Layer
        let contentLayer: Layer?
        let isLayerHidden = lottieLayer.isHidden

        if isLayerHidden {
            layer = Layer()
            layer.backgroundColor = nil
            bounds(of: lottieLayer, context: context).map { layer.bounds = $0 }
            contentLayer = nil
        } else {
            switch lottieLayer.type {
            case .shape:
                layer = Layer()
                layer.backgroundColor = nil
                bounds(of: lottieLayer, context: context).map { layer.bounds = $0 }

                let content = Layer()
                content.bounds = layer.bounds
                content.position = Point(x: 0, y: 0)
                content.anchorPoint = Point(x: 0, y: 0)
                content.backgroundColor = nil

                let builder = ShapeBuilder(context: context)
                for sublayer in builder.layers(for: lottieLayer.shapes ?? [], bounds: layer.bounds, at: path, timing: timing) {
                    content.addSublayer(sublayer)
                }
                contentLayer = content

            case .solid:
                layer = Layer()
                layer.bounds = Rect(x: 0, y: 0, width: lottieLayer.solidWidth ?? 0, height: lottieLayer.solidHeight ?? 0)
                layer.backgroundColor = nil

                let content = Layer()
                content.bounds = layer.bounds
                content.position = Point(x: 0, y: 0)
                content.anchorPoint = Point(x: 0, y: 0)
                content.backgroundColor = Self.color(hex: lottieLayer.solidColor ?? "#000000")
                contentLayer = content

            case .null:
                layer = Layer()
                layer.backgroundColor = nil
                bounds(of: lottieLayer, context: context).map { layer.bounds = $0 }
                contentLayer = nil

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
                layer.masksToBounds = false

                let content = Layer()
                content.bounds = layer.bounds
                content.position = Point(x: 0, y: 0)
                content.anchorPoint = Point(x: 0, y: 0)
                content.backgroundColor = nil
                content.masksToBounds = false

                let assetParentTiming = LayerTiming(speed: timing.speed, beginTime: timing.beginTime, duration: timing.duration, startFrame: 0.0)

                let transform = lottieLayer.transform
                let anchor = transform?.anchor?.initialValue ?? []
                let scale = transform?.scale?.initialValue ?? []

                let anchorX = anchor.component(0) ?? 0
                let anchorY = anchor.component(1) ?? 0
                let posPoint = transform?.position?.initialPoint
                let posX = posPoint?.x ?? 0
                let posY = posPoint?.y ?? 0
                let scaleX = (scale.component(0) ?? 100) / 100

                let precompAcc = AccumulatedTransform(
                    position: Point(x: posX, y: posY),
                    anchor: Point(x: anchorX, y: anchorY),
                    scale: scaleX
                )
                let childAccumulated = combine(precompAcc, with: accumulated)

                context.precompositionStack.append(referenceId)
                build(layers: assetLayers, into: content, context: context, at: "\(path) > precomp '\(referenceId)'", parentTiming: assetParentTiming, accumulated: childAccumulated)
                context.precompositionStack.removeLast()
                contentLayer = content

            default:
                context.report.skip("layer type \(lottieLayer.rawType)", at: path)
                return nil
            }
        }

        if lottieLayer.type == .precomposition {
            layer.position = Point(x: 0, y: 0)
            layer.anchorPoint = Point(x: 0, y: 0)
            layer.transform = Transform3D.identity
            if let contentLayer {
                let visibility = visibilityWindow(of: lottieLayer, context: context, parentTiming: parentTiming, childTiming: timing)
                applyOpacity(lottieLayer.transform?.opacity, to: contentLayer, context: context, visibility: visibility, timing: timing)
            }
        } else {
            applyTimeline(
                timeline,
                to: layer,
                timing: timing
            )
            if let contentLayer {
                contentLayer.transform = Transform3D.translation(x: -timeline.anchor.x, y: -timeline.anchor.y, z: 0)
                let visibility = visibilityWindow(of: lottieLayer, context: context, parentTiming: parentTiming, childTiming: timing)
                applyOpacity(lottieLayer.transform?.opacity, to: contentLayer, context: context, visibility: visibility, timing: timing)
            }
        }

        if let contentLayer {
            contentLayer.name = "\(lottieLayer.name ?? "?") content"
            applyMasks(lottieLayer, to: contentLayer, context: context, at: path)
            layer.addSublayer(contentLayer)
        }

        layer.name = lottieLayer.name
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

    // MARK: - Transform mapping

    private struct TransformTimeline {
        var anchor: Point
        var tx: [TimelineSample]
        var ty: [TimelineSample]
        var sx: [TimelineSample]
        var sy: [TimelineSample]
        var rz: [TimelineSample]
    }

    private static func originalTimeline(
        for lottieLayer: LottieLayer,
        context: ImportContext,
        timing: LayerTiming,
        accumulated: AccumulatedTransform
    ) -> TransformTimeline {
        let transform = lottieLayer.transform
        let anchor = transform?.anchor?.initialValue ?? []
        let anchorX = anchor.component(0) ?? 0
        let anchorY = anchor.component(1) ?? 0

        let transformPoint = { (p: Point) -> Point in
            Point(
                x: (p.x - accumulated.anchor.x) * accumulated.scale + accumulated.position.x,
                y: (p.y - accumulated.anchor.y) * accumulated.scale + accumulated.position.y
            )
        }

        var tx: [TimelineSample]
        var ty: [TimelineSample]

        if let position = transform?.position {
            if position.isAnimated {
                switch position {
                case let .vector(vector):
                    if case let .keyframed(keyframes) = vector {
                        tx = ScalarTimeline.samples(
                            from: keyframes,
                            dimension: 0,
                            frameRate: context.frameRate,
                            startFrame: timing.startFrame,
                            beginTime: timing.beginTime,
                            speed: timing.speed
                        ) { x in
                            (x - accumulated.anchor.x) * accumulated.scale + accumulated.position.x
                        }
                        ty = ScalarTimeline.samples(
                            from: keyframes,
                            dimension: 1,
                            frameRate: context.frameRate,
                            startFrame: timing.startFrame,
                            beginTime: timing.beginTime,
                            speed: timing.speed
                        ) { y in
                            (y - accumulated.anchor.y) * accumulated.scale + accumulated.position.y
                        }
                    } else {
                        let initialPt = position.initialPoint
                        let p = transformPoint(Point(x: initialPt.x, y: initialPt.y))
                        tx = [TimelineSample(time: 0, value: p.x), TimelineSample(time: timing.duration, value: p.x)]
                        ty = [TimelineSample(time: 0, value: p.y), TimelineSample(time: timing.duration, value: p.y)]
                    }
                case let .split(x, y):
                    if case let .keyframed(keyframes) = x {
                        tx = ScalarTimeline.samples(
                            from: keyframes,
                            dimension: 0,
                            frameRate: context.frameRate,
                            startFrame: timing.startFrame,
                            beginTime: timing.beginTime,
                            speed: timing.speed
                        ) { val in
                            (val - accumulated.anchor.x) * accumulated.scale + accumulated.position.x
                        }
                    } else {
                        let initialPt = position.initialPoint
                        let p = transformPoint(Point(x: initialPt.x, y: initialPt.y))
                        tx = [TimelineSample(time: 0, value: p.x), TimelineSample(time: timing.duration, value: p.x)]
                    }
                    if case let .keyframed(keyframes) = y {
                        ty = ScalarTimeline.samples(
                            from: keyframes,
                            dimension: 0,
                            frameRate: context.frameRate,
                            startFrame: timing.startFrame,
                            beginTime: timing.beginTime,
                            speed: timing.speed
                        ) { val in
                            (val - accumulated.anchor.y) * accumulated.scale + accumulated.position.y
                        }
                    } else {
                        let initialPt = position.initialPoint
                        let p = transformPoint(Point(x: initialPt.x, y: initialPt.y))
                        ty = [TimelineSample(time: 0, value: p.y), TimelineSample(time: timing.duration, value: p.y)]
                    }
                }
            } else {
                let initialPt = position.initialPoint
                let p = transformPoint(Point(x: initialPt.x, y: initialPt.y))
                tx = [TimelineSample(time: 0, value: p.x), TimelineSample(time: timing.duration, value: p.x)]
                ty = [TimelineSample(time: 0, value: p.y), TimelineSample(time: timing.duration, value: p.y)]
            }
        } else {
            let p = transformPoint(.zero)
            tx = [TimelineSample(time: 0, value: p.x), TimelineSample(time: timing.duration, value: p.x)]
            ty = [TimelineSample(time: 0, value: p.y), TimelineSample(time: timing.duration, value: p.y)]
        }

        var sx: [TimelineSample]
        var sy: [TimelineSample]
        let mapScale = { (percent: Double) in (percent / 100) * accumulated.scale }

        if let scale = transform?.scale {
            if scale.isAnimated, case let .keyframed(keyframes) = scale {
                sx = ScalarTimeline.samples(
                    from: keyframes,
                    dimension: 0,
                    frameRate: context.frameRate,
                    startFrame: timing.startFrame,
                    beginTime: timing.beginTime,
                    speed: timing.speed,
                    map: mapScale
                )
                sy = ScalarTimeline.samples(
                    from: keyframes,
                    dimension: 1,
                    frameRate: context.frameRate,
                    startFrame: timing.startFrame,
                    beginTime: timing.beginTime,
                    speed: timing.speed,
                    map: mapScale
                )
            } else {
                let value = scale.initialValue
                let valX = ((value.component(0) ?? 100) / 100) * accumulated.scale
                let valY = ((value.component(1) ?? 100) / 100) * accumulated.scale
                sx = [TimelineSample(time: 0, value: valX), TimelineSample(time: timing.duration, value: valX)]
                sy = [TimelineSample(time: 0, value: valY), TimelineSample(time: timing.duration, value: valY)]
            }
        } else {
            sx = [TimelineSample(time: 0, value: accumulated.scale), TimelineSample(time: timing.duration, value: accumulated.scale)]
            sy = [TimelineSample(time: 0, value: accumulated.scale), TimelineSample(time: timing.duration, value: accumulated.scale)]
        }

        var rz: [TimelineSample]
        if let rotation = transform?.rotation {
            if case let .keyframed(keyframes) = rotation {
                rz = ScalarTimeline.samples(
                    from: keyframes,
                    dimension: 0,
                    frameRate: context.frameRate,
                    startFrame: timing.startFrame,
                    beginTime: timing.beginTime,
                    speed: timing.speed
                ) { $0 * .pi / 180 }
            } else {
                let radians = rotation.initialValue * .pi / 180
                rz = [TimelineSample(time: 0, value: radians), TimelineSample(time: timing.duration, value: radians)]
            }
        } else {
            rz = [TimelineSample(time: 0, value: 0), TimelineSample(time: timing.duration, value: 0)]
        }

        return TransformTimeline(
            anchor: Point(x: anchorX, y: anchorY),
            tx: tx,
            ty: ty,
            sx: sx,
            sy: sy,
            rz: rz
        )
    }

    private func applyTimeline(
        _ timeline: TransformTimeline,
        to layer: Layer,
        timing: LayerTiming
    ) {
        layer.position = Point(x: 0, y: 0)
        layer.anchorPoint = Point(x: 0, y: 0)
        layer.transform = Transform3D.identity

        addTimelineAnimation(keyPath: "transform.translation.x", samples: timeline.tx, key: "lottie.position.x", to: layer, timing: timing)
        addTimelineAnimation(keyPath: "transform.translation.y", samples: timeline.ty, key: "lottie.position.y", to: layer, timing: timing)
        addTimelineAnimation(keyPath: "transform.scale.x", samples: timeline.sx, key: "lottie.scale.x", to: layer, timing: timing)
        addTimelineAnimation(keyPath: "transform.scale.y", samples: timeline.sy, key: "lottie.scale.y", to: layer, timing: timing)
        addTimelineAnimation(keyPath: "transform.rotation.z", samples: timeline.rz, key: "lottie.rotation", to: layer, timing: timing)
    }

    private func addTimelineAnimation(
        keyPath: String,
        samples: [TimelineSample],
        key: String,
        to layer: Layer,
        timing: LayerTiming
    ) {
        if let animation = ScalarTimeline.animation(keyPath: keyPath, samples: samples, duration: timing.duration, beginTime: timing.beginTime, speed: timing.speed) {
            layer.add(animation, forKey: key)
        }
    }

    /// Opacity and the in/out visibility window share the `opacity` key path,
    /// so they are merged into one sampled timeline.
    private func applyOpacity(_ opacity: AnimatedDouble?, to layer: Layer, context: ImportContext, visibility: (start: Double, end: Double)?, timing: LayerTiming) {
        let map = { (percent: Double) in min(max(percent / 100, 0), 1) }
        var samples: [TimelineSample]?
        if case let .keyframed(keyframes) = opacity {
            samples = ScalarTimeline.samples(
                from: keyframes,
                dimension: 0,
                frameRate: context.frameRate,
                startFrame: timing.startFrame,
                beginTime: timing.beginTime,
                speed: timing.speed,
                map: map
            )
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
