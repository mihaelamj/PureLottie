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

    public init(value: Value, diagnostics: [ValidationError] = []) {
        self.value = value
        self.diagnostics = diagnostics
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
        if let timeRemap = layer.timeRemap {
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
            return LottieEvaluationResult(value: value)
        case let .keyframed(keyframes):
            let result = evaluateVectorKeyframes(
                keyframes,
                at: sourceFrame,
                path: path,
                offsetFrame: offsetFrame,
                reportSpatialInterpolation: false
            )
            return LottieEvaluationResult(
                value: result.value.component(0) ?? 0,
                diagnostics: result.diagnostics
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
            LottieEvaluationResult(value: value)
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
        case let .split(x, y):
            let xResult = evaluate(x, at: sourceFrame, path: path.appending(.key("x")), offsetFrame: offsetFrame)
            let yResult = evaluate(y, at: sourceFrame, path: path.appending(.key("y")), offsetFrame: offsetFrame)
            return LottieEvaluationResult(
                value: [xResult.value, yResult.value],
                diagnostics: xResult.diagnostics + yResult.diagnostics
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
                ]
            )
        }

        var diagnostics: [ValidationError] = []
        if reportSpatialInterpolation, keyframes.contains(where: hasSpatialInterpolation) {
            diagnostics.append(
                diagnostic(
                    ruleID: "lottie.evaluation.spatial-interpolation.unsupported",
                    reason: "Spatial interpolation is not yet evaluated; temporal interpolation is returned.",
                    path: path,
                    classification: .approximate
                )
            )
        }

        guard keyframes.count > 1 else {
            return LottieEvaluationResult(value: keyframes[0].startValue ?? [], diagnostics: diagnostics)
        }

        let firstTime = keyframes[0].time - offsetFrame
        if sourceFrame < firstTime {
            return LottieEvaluationResult(value: keyframes[0].startValue ?? [], diagnostics: diagnostics)
        }

        if let last = keyframes.last, sourceFrame >= last.time - offsetFrame {
            let previous = keyframes[keyframes.count - 2]
            return LottieEvaluationResult(
                value: last.startValue ?? previous.endValue ?? previous.startValue ?? [],
                diagnostics: diagnostics
            )
        }

        let segmentIndex = keyframes.indices.dropLast().first { index in
            sourceFrame < keyframes[index + 1].time - offsetFrame
        } ?? keyframes.startIndex

        let keyframe = keyframes[segmentIndex]
        let next = keyframes[segmentIndex + 1]
        let start = keyframe.startValue ?? []
        let end = next.startValue ?? keyframe.endValue ?? start
        guard !keyframe.isHold else {
            return LottieEvaluationResult(value: start, diagnostics: diagnostics)
        }

        let startFrame = keyframe.time - offsetFrame
        let endFrame = next.time - offsetFrame
        let progress: Double
        if sourceFrame >= endFrame {
            progress = 1
        } else if sourceFrame < startFrame || endFrame <= startFrame {
            progress = 0
        } else {
            let linearProgress = (sourceFrame - startFrame) / (endFrame - startFrame)
            progress = easedProgress(linearProgress, out: keyframe.easeOut, in: keyframe.easeIn)
        }

        let count = max(start.count, end.count)
        let value = (0 ..< count).map { index in
            let startComponent = start.component(index) ?? 0
            let endComponent = end.component(index) ?? startComponent
            return startComponent + (endComponent - startComponent) * progress
        }
        return LottieEvaluationResult(value: value, diagnostics: diagnostics)
    }

    private func easedProgress(_ progress: Double, out: EasingHandle?, in easeIn: EasingHandle?) -> Double {
        guard let out, let easeIn else { return progress }
        return BezierEasing(x1: out.x, y1: out.y, x2: easeIn.x, y2: easeIn.y).value(at: progress)
    }

    private func hasSpatialInterpolation(_ keyframe: LottieKeyframe<[Double]>) -> Bool {
        (keyframe.spatialOut ?? []).contains { abs($0) > Self.epsilon }
            || (keyframe.spatialIn ?? []).contains { abs($0) > Self.epsilon }
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
}
