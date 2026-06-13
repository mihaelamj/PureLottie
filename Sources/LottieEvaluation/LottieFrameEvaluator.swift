//
//  LottieFrameEvaluator.swift
//  PureLottie
//

import LottieModel

/// A half-open source-frame window. Lottie uses inclusive `ip` and exclusive
/// `op`, so frame `op` itself is outside the window.
public struct LottieFrameWindow: Sendable, Equatable {
    public let inPoint: Double
    public let outPoint: Double

    public init(inPoint: Double, outPoint: Double) {
        self.inPoint = inPoint
        self.outPoint = outPoint
    }

    public func contains(_ frame: Double) -> Bool {
        frame >= inPoint && frame < outPoint
    }
}

/// The result of evaluating one Lottie value at one source frame.
public struct LottieEvaluationResult<Value: Sendable & Equatable>: Sendable, Equatable {
    public let value: Value
    public let diagnostics: [ValidationError]
    public let trace: LottiePropertyEvaluationTrace?

    public init(value: Value, diagnostics: [ValidationError] = [], trace: LottiePropertyEvaluationTrace? = nil) {
        self.value = value
        self.diagnostics = diagnostics
        self.trace = trace
    }

    public var isExact: Bool {
        diagnostics.isEmpty
    }
}

/// Pure, frame-based Lottie semantic evaluator.
///
/// This target imports only `LottieModel`; it does not know about PureLayer.
/// It answers what a modeled Lottie property means at a source frame before
/// any renderer-specific lowering or frame-to-second conversion.
public struct LottieFrameEvaluator: Sendable {
    public let animation: LottieAnimation

    public init(animation: LottieAnimation) {
        self.animation = animation
    }

    /// The root composition frame window, using Lottie's half-open semantics.
    public var compositionWindow: LottieFrameWindow {
        LottieFrameWindow(inPoint: animation.inPoint, outPoint: animation.outPoint)
    }

    /// Returns true when `frame` is inside the root composition.
    public func containsCompositionFrame(_ frame: Double) -> Bool {
        compositionWindow.contains(frame)
    }

    /// Returns true when `frame` is inside both the composition and the layer's
    /// own half-open visibility window.
    public func isLayerVisible(_ layer: LottieLayer, at frame: Double) -> Bool {
        containsCompositionFrame(frame)
            && LottieFrameWindow(inPoint: layer.inPoint, outPoint: layer.outPoint).contains(frame)
    }

    /// Evaluates a layer's local source frame at a composition frame.
    ///
    /// Without `tm`, lottie-web computes `(parentFrame - st) / sr`. With `tm`,
    /// the remap property is authored in seconds, then multiplied by the root
    /// frame rate to recover local frames.
    public func localFrame(
        for layer: LottieLayer,
        at compositionFrame: Double,
        path: JSONPath = JSONPath()
    ) -> LottieEvaluationResult<Double> {
        if let timeRemap = layer.timeRemap, !LottieFaultInjector.isActive(.skippedPrecompTimeRemap) {
            let result = evaluate(
                timeRemap,
                at: compositionFrame,
                path: path.appending(.key("tm")),
                offsetFrame: layer.startTime
            )
            var frame = result.value * animation.frameRate
            if frame == layer.outPoint {
                frame = layer.outPoint - 1
            }
            return LottieEvaluationResult(value: frame, diagnostics: result.diagnostics)
        }

        guard abs(layer.stretch) > Self.epsilon else {
            return LottieEvaluationResult(
                value: 0,
                diagnostics: [
                    diagnostic(
                        ruleID: "lottie.evaluation.layer-stretch.nonzero",
                        reason: "Layer stretch `sr` must be non-zero before local frame evaluation.",
                        path: path.appending(.key("sr")),
                        classification: .gap
                    ),
                ]
            )
        }

        return LottieEvaluationResult(value: (compositionFrame - layer.startTime) / layer.stretch)
    }

    /// Evaluates a scalar animated Lottie property at a source frame.
    public func evaluate(
        _ property: AnimatedDouble,
        at sourceFrame: Double,
        path: JSONPath = JSONPath(),
        offsetFrame: Double = 0
    ) -> LottieEvaluationResult<Double> {
        switch property {
        case let .fixed(value):
            return LottieEvaluationResult(
                value: value,
                trace: fixedTrace(value: [value], sourceFrame: sourceFrame, offsetFrame: offsetFrame, path: path)
            )
        case let .keyframed(keyframes):
            let result = evaluateVectorKeyframes(
                keyframes,
                at: sourceFrame,
                path: path,
                offsetFrame: offsetFrame,
                reportSpatialInterpolation: false
            )
            let value = result.value.component(0) ?? 0
            var trace = result.trace
            trace?.finalValue = [value]
            return LottieEvaluationResult(
                value: value,
                diagnostics: result.diagnostics,
                trace: trace
            )
        }
    }

    /// Evaluates a vector animated Lottie property at a source frame.
    public func evaluate(
        _ property: AnimatedVector,
        at sourceFrame: Double,
        path: JSONPath = JSONPath(),
        offsetFrame: Double = 0
    ) -> LottieEvaluationResult<[Double]> {
        switch property {
        case let .fixed(value):
            LottieEvaluationResult(
                value: value,
                trace: fixedTrace(value: value, sourceFrame: sourceFrame, offsetFrame: offsetFrame, path: path)
            )
        case let .keyframed(keyframes):
            evaluateVectorKeyframes(
                keyframes,
                at: sourceFrame,
                path: path,
                offsetFrame: offsetFrame,
                reportSpatialInterpolation: true
            )
        }
    }

    /// Evaluates a split or unified position property at a source frame.
    public func evaluate(
        _ position: LottiePosition,
        at sourceFrame: Double,
        path: JSONPath = JSONPath(),
        offsetFrame: Double = 0
    ) -> LottieEvaluationResult<[Double]> {
        switch position {
        case let .vector(value):
            return evaluate(value, at: sourceFrame, path: path, offsetFrame: offsetFrame)
        case let .split(x, y, z):
            let xResult = evaluate(x, at: sourceFrame, path: path.appending(.key("x")), offsetFrame: offsetFrame)
            let yResult = evaluate(y, at: sourceFrame, path: path.appending(.key("y")), offsetFrame: offsetFrame)
            let zResult = z.map { evaluate($0, at: sourceFrame, path: path.appending(.key("z")), offsetFrame: offsetFrame) }
            let value = [xResult.value, yResult.value, zResult?.value ?? 0]
            return LottieEvaluationResult(
                value: value,
                diagnostics: xResult.diagnostics + yResult.diagnostics + (zResult?.diagnostics ?? []),
                trace: LottiePropertyEvaluationTrace(
                    propertyPath: path.description,
                    sourceFrame: sourceFrame,
                    offsetFrame: offsetFrame,
                    localFrame: sourceFrame + offsetFrame,
                    mode: .splitPosition,
                    finalValue: value,
                    childTraces: [xResult.trace, yResult.trace, zResult?.trace].compactMap { $0 }
                )
            )
        }
    }

    /// Evaluates a Bezier path. Static paths are exact; animated path morphing
    /// is diagnosed and returns the authored initial path until exact morphing
    /// is implemented.
    public func evaluate(
        _ property: AnimatedBezier,
        at _: Double,
        path: JSONPath = JSONPath()
    ) -> LottieEvaluationResult<LottieBezier?> {
        switch property {
        case let .fixed(value):
            LottieEvaluationResult(value: value)
        case let .keyframed(keyframes):
            LottieEvaluationResult(
                value: keyframes.first?.startValue?.first,
                diagnostics: [
                    diagnostic(
                        ruleID: "lottie.evaluation.path-morph.unsupported",
                        reason: "Animated Bezier path morphing is not yet evaluated; the initial path is returned.",
                        path: path,
                        classification: .approximate
                    ),
                ]
            )
        }
    }

    // MARK: Keyframes

    private static let epsilon = 0.0001
    private static let lottieWebSpatialCurveSegments = 150

    private func evaluateVectorKeyframes(
        _ keyframes: [LottieKeyframe<[Double]>],
        at sourceFrame: Double,
        path: JSONPath,
        offsetFrame: Double,
        reportSpatialInterpolation: Bool
    ) -> LottieEvaluationResult<[Double]> {
        guard !keyframes.isEmpty else {
            return LottieEvaluationResult(
                value: [],
                diagnostics: [
                    diagnostic(
                        ruleID: "lottie.evaluation.keyframes.nonempty",
                        reason: "Animated property keyframes must be non-empty before evaluation.",
                        path: path,
                        classification: .gap
                    ),
                ],
                trace: LottiePropertyEvaluationTrace(
                    propertyPath: path.description,
                    sourceFrame: sourceFrame,
                    offsetFrame: offsetFrame,
                    localFrame: sourceFrame + offsetFrame,
                    mode: .emptyKeyframes,
                    finalValue: []
                )
            )
        }

        var diagnostics: [ValidationError] = []

        guard keyframes.count > 1 else {
            let value = keyframes[0].startValue ?? []
            return LottieEvaluationResult(
                value: value,
                diagnostics: diagnostics,
                trace: LottiePropertyEvaluationTrace(
                    propertyPath: path.description,
                    sourceFrame: sourceFrame,
                    offsetFrame: offsetFrame,
                    localFrame: sourceFrame + offsetFrame,
                    mode: .singleKeyframe,
                    finalValue: value
                )
            )
        }

        let firstTime = keyframes[0].time - offsetFrame
        if sourceFrame < firstTime {
            let value = keyframes[0].startValue ?? []
            return LottieEvaluationResult(
                value: value,
                diagnostics: diagnostics,
                trace: LottiePropertyEvaluationTrace(
                    propertyPath: path.description,
                    sourceFrame: sourceFrame,
                    offsetFrame: offsetFrame,
                    localFrame: sourceFrame + offsetFrame,
                    mode: .beforeFirstKeyframe,
                    finalValue: value
                )
            )
        }

        if let last = keyframes.last, sourceFrame >= last.time - offsetFrame {
            let previous = keyframes[keyframes.count - 2]
            let value = last.startValue ?? previous.endValue ?? previous.startValue ?? []
            return LottieEvaluationResult(
                value: value,
                diagnostics: diagnostics,
                trace: LottiePropertyEvaluationTrace(
                    propertyPath: path.description,
                    sourceFrame: sourceFrame,
                    offsetFrame: offsetFrame,
                    localFrame: sourceFrame + offsetFrame,
                    mode: .afterLastKeyframe,
                    finalValue: value
                )
            )
        }

        var segmentIndex = keyframes.indices.dropLast().first { index in
            sourceFrame < keyframes[index + 1].time - offsetFrame
        } ?? keyframes.startIndex

        let faultActive = LottieFaultInjector.isActive(.offByOneKeyframeIndex) && keyframes.count > 1
        if faultActive {
            segmentIndex = (segmentIndex + 1) % keyframes.count
        }

        let keyframe = keyframes[segmentIndex]
        let next = keyframes[faultActive ? (segmentIndex + 1) % keyframes.count : segmentIndex + 1]
        let start = keyframe.startValue ?? []
        let end = next.startValue ?? keyframe.endValue ?? start
        let startFrame = keyframe.time - offsetFrame
        let endFrame = next.time - offsetFrame
        let linearProgress = normalizedProgress(sourceFrame: sourceFrame, startFrame: startFrame, endFrame: endFrame)

        if keyframe.isHold {
            let span = spanTrace(
                keyframeIndex: segmentIndex,
                keyframe: keyframe,
                next: next,
                start: start,
                end: end,
                startFrame: startFrame,
                endFrame: endFrame,
                linearProgress: linearProgress,
                timingProgress: [0],
                interpolationSpace: .value,
                timingCurves: [],
                spatial: nil
            )
            return LottieEvaluationResult(
                value: start,
                diagnostics: diagnostics,
                trace: animatedTrace(
                    mode: .holdKeyframe,
                    value: start,
                    sourceFrame: sourceFrame,
                    offsetFrame: offsetFrame,
                    path: path,
                    span: span
                )
            )
        }

        if keyframe.easeOut == nil || keyframe.easeIn == nil {
            diagnostics.append(
                diagnostic(
                    ruleID: "lottie.evaluation.keyframe-timing.handles-complete",
                    reason: "Non-hold keyframe spans must carry both `o` and `i` easing handles before exact timing evaluation; a linear timing fallback is returned.",
                    path: path,
                    classification: .gap
                )
            )
        }

        if reportSpatialInterpolation, shouldEvaluateSpatialSegment(keyframe: keyframe, start: start, end: end) {
            guard let spatialOut = keyframe.spatialOut, let spatialIn = keyframe.spatialIn, spatialDimensionsMatch(
                start: start,
                end: end,
                spatialOut: spatialOut,
                spatialIn: spatialIn
            ) else {
                diagnostics.append(
                    diagnostic(
                        ruleID: "lottie.evaluation.spatial-interpolation.tangents-complete",
                        reason: "Spatial position keyframes must carry matching start, end, `to`, and `ti` dimensions before exact evaluation.",
                        path: path,
                        classification: .gap
                    )
                )
                let temporal = temporalValue(start: start, end: end, keyframe: keyframe, linearProgress: linearProgress)
                return LottieEvaluationResult(
                    value: temporal.value,
                    diagnostics: diagnostics,
                    trace: animatedTrace(
                        mode: .keyframeSpan,
                        value: temporal.value,
                        sourceFrame: sourceFrame,
                        offsetFrame: offsetFrame,
                        path: path,
                        span: spanTrace(
                            keyframeIndex: segmentIndex,
                            keyframe: keyframe,
                            next: next,
                            start: start,
                            end: end,
                            startFrame: startFrame,
                            endFrame: endFrame,
                            linearProgress: linearProgress,
                            timingProgress: temporal.progress,
                            interpolationSpace: .value,
                            timingCurves: temporal.curves,
                            spatial: nil
                        )
                    )
                )
            }

            let timing = timingProgress(linearProgress, out: keyframe.easeOut, in: keyframe.easeIn, component: 0)
            let spatial = spatialValue(
                start: start,
                end: end,
                spatialOut: spatialOut,
                spatialIn: spatialIn,
                timingProgress: timing.progress
            )
            let span = spanTrace(
                keyframeIndex: segmentIndex,
                keyframe: keyframe,
                next: next,
                start: start,
                end: end,
                startFrame: startFrame,
                endFrame: endFrame,
                linearProgress: linearProgress,
                timingProgress: [timing.progress],
                interpolationSpace: .spatialArcLength,
                timingCurves: timing.trace.map { [$0] } ?? [],
                spatial: spatial.trace
            )
            return LottieEvaluationResult(
                value: spatial.value,
                diagnostics: diagnostics,
                trace: animatedTrace(
                    mode: .keyframeSpan,
                    value: spatial.value,
                    sourceFrame: sourceFrame,
                    offsetFrame: offsetFrame,
                    path: path,
                    span: span
                )
            )
        }

        let temporal = temporalValue(start: start, end: end, keyframe: keyframe, linearProgress: linearProgress)
        let span = spanTrace(
            keyframeIndex: segmentIndex,
            keyframe: keyframe,
            next: next,
            start: start,
            end: end,
            startFrame: startFrame,
            endFrame: endFrame,
            linearProgress: linearProgress,
            timingProgress: temporal.progress,
            interpolationSpace: .value,
            timingCurves: temporal.curves,
            spatial: nil
        )
        return LottieEvaluationResult(
            value: temporal.value,
            diagnostics: diagnostics,
            trace: animatedTrace(
                mode: .keyframeSpan,
                value: temporal.value,
                sourceFrame: sourceFrame,
                offsetFrame: offsetFrame,
                path: path,
                span: span
            )
        )
    }

    private func fixedTrace(value: [Double], sourceFrame: Double, offsetFrame: Double, path: JSONPath) -> LottiePropertyEvaluationTrace {
        LottiePropertyEvaluationTrace(
            propertyPath: path.description,
            sourceFrame: sourceFrame,
            offsetFrame: offsetFrame,
            localFrame: sourceFrame + offsetFrame,
            mode: .fixed,
            finalValue: value
        )
    }

    private func animatedTrace(
        mode: LottiePropertyEvaluationMode,
        value: [Double],
        sourceFrame: Double,
        offsetFrame: Double,
        path: JSONPath,
        span: LottieKeyframeSpanTrace
    ) -> LottiePropertyEvaluationTrace {
        LottiePropertyEvaluationTrace(
            propertyPath: path.description,
            sourceFrame: sourceFrame,
            offsetFrame: offsetFrame,
            localFrame: sourceFrame + offsetFrame,
            mode: mode,
            finalValue: value,
            span: span
        )
    }

    private func spanTrace(
        keyframeIndex: Int,
        keyframe: LottieKeyframe<[Double]>,
        next: LottieKeyframe<[Double]>,
        start: [Double],
        end: [Double],
        startFrame: Double,
        endFrame: Double,
        linearProgress: Double,
        timingProgress: [Double],
        interpolationSpace: LottieInterpolationSpace,
        timingCurves: [LottieTimingCurveTrace],
        spatial: LottieSpatialEvaluationTrace?
    ) -> LottieKeyframeSpanTrace {
        LottieKeyframeSpanTrace(
            keyframeIndex: keyframeIndex,
            authoredStartFrame: keyframe.time,
            authoredEndFrame: next.time,
            evaluatedStartFrame: startFrame,
            evaluatedEndFrame: endFrame,
            startValue: start,
            endValue: end,
            linearProgress: linearProgress,
            timingProgress: timingProgress,
            interpolationSpace: interpolationSpace,
            isHold: keyframe.isHold,
            timingCurves: timingCurves,
            spatial: spatial
        )
    }

    private func temporalValue(
        start: [Double],
        end: [Double],
        keyframe: LottieKeyframe<[Double]>,
        linearProgress: Double
    ) -> (value: [Double], progress: [Double], curves: [LottieTimingCurveTrace]) {
        let count = max(start.count, end.count)
        var progressValues: [Double] = []
        var curves: [LottieTimingCurveTrace] = []
        var value: [Double] = []

        for index in 0 ..< count {
            let timing = timingProgress(linearProgress, out: keyframe.easeOut, in: keyframe.easeIn, component: index)
            progressValues.append(timing.progress)
            if let trace = timing.trace {
                curves.append(trace)
            }
            let startComponent = start.component(index) ?? 0
            let endComponent = end.component(index) ?? startComponent
            value.append(startComponent + (endComponent - startComponent) * timing.progress)
        }

        return (value, progressValues, curves)
    }

    private func normalizedProgress(sourceFrame: Double, startFrame: Double, endFrame: Double) -> Double {
        if sourceFrame >= endFrame { return 1 }
        if sourceFrame < startFrame || endFrame <= startFrame { return 0 }
        return (sourceFrame - startFrame) / (endFrame - startFrame)
    }

    private func timingProgress(
        _ progress: Double,
        out: EasingHandle?,
        in easeIn: EasingHandle?,
        component: Int
    ) -> (progress: Double, trace: LottieTimingCurveTrace?) {
        guard let out, let easeIn else { return (progress, nil) }
        let value = BezierEasing(
            x1: out.xComponent(component),
            y1: out.yComponent(component),
            x2: easeIn.xComponent(component),
            y2: easeIn.yComponent(component)
        ).value(at: progress)
        return (
            value,
            LottieTimingCurveTrace(
                component: component,
                outX: out.xComponent(component),
                outY: out.yComponent(component),
                inX: easeIn.xComponent(component),
                inY: easeIn.yComponent(component),
                result: value
            )
        )
    }

    private func shouldEvaluateSpatialSegment(keyframe: LottieKeyframe<[Double]>, start: [Double], end: [Double]) -> Bool {
        guard let spatialOut = keyframe.spatialOut else { return false }
        let spatialIn = keyframe.spatialIn ?? []
        guard hasSpatialTangent(spatialOut) || hasSpatialTangent(spatialIn) else { return false }
        return !isEffectivelyLinearSpatialSegment(
            start: start,
            end: end,
            spatialOut: spatialOut,
            spatialIn: spatialIn
        )
    }

    private func spatialDimensionsMatch(start: [Double], end: [Double], spatialOut: [Double], spatialIn: [Double]) -> Bool {
        !start.isEmpty
            && start.count == end.count
            && start.count == spatialOut.count
            && start.count == spatialIn.count
    }

    private func spatialValue(
        start: [Double],
        end: [Double],
        spatialOut: [Double],
        spatialIn: [Double],
        timingProgress: Double
    ) -> (value: [Double], trace: LottieSpatialEvaluationTrace) {
        let bezier = buildSpatialBezierData(
            start: start,
            end: end,
            spatialOut: spatialOut,
            spatialIn: spatialIn
        )
        let distance = bezier.segmentLength * timingProgress
        let sample = sampleSpatialBezier(bezier, distance: distance, timingProgress: timingProgress)
        let trace = LottieSpatialEvaluationTrace(
            outTangent: spatialOut,
            inTangent: spatialIn,
            controlPoint1: zipComponents(start, spatialOut, +),
            controlPoint2: zipComponents(end, spatialIn, +),
            curveSegments: bezier.points.count,
            segmentLength: bezier.segmentLength,
            distance: distance,
            pointIndex: sample.pointIndex,
            pointSegmentProgress: sample.pointSegmentProgress
        )
        return (sample.value, trace)
    }

    private func buildSpatialBezierData(
        start: [Double],
        end: [Double],
        spatialOut: [Double],
        spatialIn: [Double]
    ) -> SpatialBezierData {
        var points: [SpatialPoint] = []
        var addedLength = 0.0
        var lastPoint: [Double]?

        for index in 0 ..< Self.lottieWebSpatialCurveSegments {
            let progress = Double(index) / Double(Self.lottieWebSpatialCurveSegments - 1)
            let inverse = 1 - progress
            let point = start.indices.map { component in
                (inverse * inverse * inverse * start[component])
                    + (3 * inverse * inverse * progress * (start[component] + spatialOut[component]))
                    + (3 * inverse * progress * progress * (end[component] + spatialIn[component]))
                    + (progress * progress * progress * end[component])
            }
            let partialLength: Double
            if let lastPoint {
                partialLength = distance(from: lastPoint, to: point)
                addedLength += partialLength
            } else {
                partialLength = 0
            }
            points.append(SpatialPoint(partialLength: partialLength, point: point))
            lastPoint = point
        }

        return SpatialBezierData(segmentLength: addedLength, points: points)
    }

    private func sampleSpatialBezier(
        _ bezier: SpatialBezierData,
        distance: Double,
        timingProgress: Double
    ) -> (value: [Double], pointIndex: Int, pointSegmentProgress: Double?) {
        guard let first = bezier.points.first else {
            return ([], 0, nil)
        }
        guard bezier.segmentLength > Self.epsilon else {
            return (first.point, 0, nil)
        }

        var addedLength = 0.0
        for index in bezier.points.indices {
            let point = bezier.points[index]
            addedLength += point.partialLength
            if distance == 0 || timingProgress == 0 || index == bezier.points.count - 1 {
                return (point.point, index, nil)
            }
            let next = bezier.points[index + 1]
            if distance >= addedLength, distance < addedLength + next.partialLength {
                let segmentProgress = (distance - addedLength) / next.partialLength
                let value = point.point.indices.map { component in
                    point.point[component] + (next.point[component] - point.point[component]) * segmentProgress
                }
                return (value, index, segmentProgress)
            }
        }

        let lastIndex = bezier.points.count - 1
        return (bezier.points[lastIndex].point, lastIndex, nil)
    }

    private func hasSpatialTangent(_ values: [Double]) -> Bool {
        values.contains { abs($0) > Self.epsilon }
    }

    private func isEffectivelyLinearSpatialSegment(
        start: [Double],
        end: [Double],
        spatialOut: [Double],
        spatialIn: [Double]
    ) -> Bool {
        switch start.count {
        case 2:
            isLinear2D(start: start, end: end, spatialOut: spatialOut, spatialIn: spatialIn)
        case 3:
            isLinear3D(start: start, end: end, spatialOut: spatialOut, spatialIn: spatialIn)
        default:
            false
        }
    }

    private func isLinear2D(start: [Double], end: [Double], spatialOut: [Double], spatialIn: [Double]) -> Bool {
        guard
            let startX = start.exactComponent(0),
            let startY = start.exactComponent(1),
            let endX = end.exactComponent(0),
            let endY = end.exactComponent(1),
            let outX = spatialOut.exactComponent(0),
            let outY = spatialOut.exactComponent(1),
            let inX = spatialIn.exactComponent(0),
            let inY = spatialIn.exactComponent(1)
        else { return false }

        if approximatelyEqual(startX, endX), approximatelyEqual(startY, endY) {
            return approximatelyZero(outX) && approximatelyZero(outY)
                && approximatelyZero(inX) && approximatelyZero(inY)
        }

        return pointOnLine2D(startX, startY, endX, endY, startX + outX, startY + outY)
            && pointOnLine2D(startX, startY, endX, endY, endX + inX, endY + inY)
    }

    private func isLinear3D(start: [Double], end: [Double], spatialOut: [Double], spatialIn: [Double]) -> Bool {
        guard
            let startX = start.exactComponent(0),
            let startY = start.exactComponent(1),
            let startZ = start.exactComponent(2),
            let endX = end.exactComponent(0),
            let endY = end.exactComponent(1),
            let endZ = end.exactComponent(2),
            let outX = spatialOut.exactComponent(0),
            let outY = spatialOut.exactComponent(1),
            let outZ = spatialOut.exactComponent(2),
            let inX = spatialIn.exactComponent(0),
            let inY = spatialIn.exactComponent(1),
            let inZ = spatialIn.exactComponent(2)
        else { return false }

        if approximatelyEqual(startX, endX), approximatelyEqual(startY, endY), approximatelyEqual(startZ, endZ) {
            return approximatelyZero(outX) && approximatelyZero(outY) && approximatelyZero(outZ)
                && approximatelyZero(inX) && approximatelyZero(inY) && approximatelyZero(inZ)
        }

        return pointOnLine3D(
            startX,
            startY,
            startZ,
            endX,
            endY,
            endZ,
            startX + outX,
            startY + outY,
            startZ + outZ
        )
            && pointOnLine3D(
                startX,
                startY,
                startZ,
                endX,
                endY,
                endZ,
                endX + inX,
                endY + inY,
                endZ + inZ
            )
    }

    private func pointOnLine2D(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) -> Bool {
        let determinant = (x1 * y2) + (y1 * x3) + (x2 * y3) - (x3 * y2) - (y3 * x1) - (x2 * y1)
        return abs(determinant) < 0.001
    }

    private func pointOnLine3D(
        _ x1: Double,
        _ y1: Double,
        _ z1: Double,
        _ x2: Double,
        _ y2: Double,
        _ z2: Double,
        _ x3: Double,
        _ y3: Double,
        _ z3: Double
    ) -> Bool {
        if approximatelyZero(z1), approximatelyZero(z2), approximatelyZero(z3) {
            return pointOnLine2D(x1, y1, x2, y2, x3, y3)
        }

        let dist1 = distance3D(x1, y1, z1, x2, y2, z2)
        let dist2 = distance3D(x1, y1, z1, x3, y3, z3)
        let dist3 = distance3D(x2, y2, z2, x3, y3, z3)
        let diffDist: Double = if dist1 > dist2 {
            if dist1 > dist3 {
                dist1 - dist2 - dist3
            } else {
                dist3 - dist2 - dist1
            }
        } else if dist3 > dist2 {
            dist3 - dist2 - dist1
        } else {
            dist2 - dist1 - dist3
        }
        return abs(diffDist) < 0.0001
    }

    private func distance3D(
        _ x1: Double,
        _ y1: Double,
        _ z1: Double,
        _ x2: Double,
        _ y2: Double,
        _ z2: Double
    ) -> Double {
        let x = x2 - x1
        let y = y2 - y1
        let z = z2 - z1
        return (x * x + y * y + z * z).squareRoot()
    }

    private func distance(from start: [Double], to end: [Double]) -> Double {
        zip(start, end)
            .map { left, right in
                let delta = right - left
                return delta * delta
            }
            .reduce(0, +)
            .squareRoot()
    }

    private func zipComponents(_ left: [Double], _ right: [Double], _ operation: (Double, Double) -> Double) -> [Double] {
        zip(left, right).map(operation)
    }

    private func approximatelyEqual(_ left: Double, _ right: Double) -> Bool {
        abs(left - right) <= Self.epsilon
    }

    private func approximatelyZero(_ value: Double) -> Bool {
        abs(value) <= Self.epsilon
    }

    private func diagnostic(
        ruleID: String,
        reason: String,
        path: JSONPath,
        classification: FeatureClassification
    ) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: reason,
            at: path,
            severity: .warning,
            phase: .semantic,
            classification: classification
        )
    }
}

private struct SpatialBezierData {
    var segmentLength: Double
    var points: [SpatialPoint]
}

private struct SpatialPoint {
    var partialLength: Double
    var point: [Double]
}

/// Port of lottie-web's `BezierEaser` timing function.
private struct BezierEasing {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double

    private static let newtonIterations = 4
    private static let newtonMinSlope = 0.001
    private static let subdivisionPrecision = 0.0000001
    private static let subdivisionMaxIterations = 10
    private static let sampleTableSize = 11
    private static let sampleStepSize = 1.0 / Double(sampleTableSize - 1)

    func value(at x: Double) -> Double {
        if x1 == y1, x2 == y2 { return x }
        if x == 0 { return 0 }
        if x == 1 { return 1 }
        return calcBezier(tForX(x), y1, y2)
    }

    private func tForX(_ x: Double) -> Double {
        let samples = (0 ..< Self.sampleTableSize).map { index in
            calcBezier(Double(index) * Self.sampleStepSize, x1, x2)
        }

        var intervalStart = 0.0
        var currentSample = 1
        let lastSample = Self.sampleTableSize - 1
        while currentSample != lastSample, samples[currentSample] <= x {
            intervalStart += Self.sampleStepSize
            currentSample += 1
        }
        currentSample -= 1

        let dist = (x - samples[currentSample]) / (samples[currentSample + 1] - samples[currentSample])
        let guess = intervalStart + dist * Self.sampleStepSize
        let initialSlope = slope(guess, x1, x2)
        if initialSlope >= Self.newtonMinSlope {
            return newtonRaphsonIterate(x, guess: guess)
        }
        if initialSlope == 0 {
            return guess
        }
        return binarySubdivide(x, a: intervalStart, b: intervalStart + Self.sampleStepSize)
    }

    private func newtonRaphsonIterate(_ x: Double, guess: Double) -> Double {
        var guess = guess
        for _ in 0 ..< Self.newtonIterations {
            let currentSlope = slope(guess, x1, x2)
            if currentSlope == 0 { return guess }
            let currentX = calcBezier(guess, x1, x2) - x
            guess -= currentX / currentSlope
        }
        return guess
    }

    private func binarySubdivide(_ x: Double, a: Double, b: Double) -> Double {
        var a = a
        var b = b
        var currentX: Double
        var currentT: Double
        var iteration = 0
        repeat {
            currentT = a + (b - a) / 2
            currentX = calcBezier(currentT, x1, x2) - x
            if currentX > 0 {
                b = currentT
            } else {
                a = currentT
            }
            iteration += 1
        } while abs(currentX) > Self.subdivisionPrecision && iteration < Self.subdivisionMaxIterations
        return currentT
    }

    private func calcBezier(_ t: Double, _ a1: Double, _ a2: Double) -> Double {
        ((a(a1, a2) * t + b(a1, a2)) * t + c(a1)) * t
    }

    private func slope(_ t: Double, _ a1: Double, _ a2: Double) -> Double {
        3 * a(a1, a2) * t * t + 2 * b(a1, a2) * t + c(a1)
    }

    private func a(_ a1: Double, _ a2: Double) -> Double {
        1 - 3 * a2 + 3 * a1
    }

    private func b(_ a1: Double, _ a2: Double) -> Double {
        3 * a2 - 6 * a1
    }

    private func c(_ a1: Double) -> Double {
        3 * a1
    }
}

private extension [Double] {
    func component(_ index: Int) -> Double? {
        if indices.contains(index) { return self[index] }
        return last
    }

    func exactComponent(_ index: Int) -> Double? {
        if indices.contains(index) { return self[index] }
        return nil
    }
}
