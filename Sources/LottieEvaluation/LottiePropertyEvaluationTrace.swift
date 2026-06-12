//
//  LottiePropertyEvaluationTrace.swift
//  PureLottie
//

/// Typed source-frame evidence for one evaluated scalar or vector Lottie
/// property. This is the measurable step before RenderIR or PureLayer lowering.
public struct LottiePropertyEvaluationTrace: Codable, Sendable, Equatable {
    public var propertyPath: String
    public var sourceFrame: Double
    public var offsetFrame: Double
    public var localFrame: Double
    public var mode: LottiePropertyEvaluationMode
    public var finalValue: [Double]
    public var span: LottieKeyframeSpanTrace?
    public var childTraces: [LottiePropertyEvaluationTrace]

    public init(
        propertyPath: String,
        sourceFrame: Double,
        offsetFrame: Double,
        localFrame: Double,
        mode: LottiePropertyEvaluationMode,
        finalValue: [Double],
        span: LottieKeyframeSpanTrace? = nil,
        childTraces: [LottiePropertyEvaluationTrace] = []
    ) {
        self.propertyPath = propertyPath
        self.sourceFrame = sourceFrame
        self.offsetFrame = offsetFrame
        self.localFrame = localFrame
        self.mode = mode
        self.finalValue = finalValue
        self.span = span
        self.childTraces = childTraces
    }
}

public enum LottiePropertyEvaluationMode: String, Codable, Sendable, Equatable {
    case fixed
    case emptyKeyframes
    case singleKeyframe
    case beforeFirstKeyframe
    case afterLastKeyframe
    case keyframeSpan
    case holdKeyframe
    case splitPosition
}

public struct LottieKeyframeSpanTrace: Codable, Sendable, Equatable {
    public var keyframeIndex: Int
    public var authoredStartFrame: Double
    public var authoredEndFrame: Double
    public var evaluatedStartFrame: Double
    public var evaluatedEndFrame: Double
    public var startValue: [Double]
    public var endValue: [Double]
    public var linearProgress: Double
    public var timingProgress: [Double]
    public var interpolationSpace: LottieInterpolationSpace
    public var isHold: Bool
    public var timingCurves: [LottieTimingCurveTrace]
    public var spatial: LottieSpatialEvaluationTrace?

    public init(
        keyframeIndex: Int,
        authoredStartFrame: Double,
        authoredEndFrame: Double,
        evaluatedStartFrame: Double,
        evaluatedEndFrame: Double,
        startValue: [Double],
        endValue: [Double],
        linearProgress: Double,
        timingProgress: [Double],
        interpolationSpace: LottieInterpolationSpace,
        isHold: Bool,
        timingCurves: [LottieTimingCurveTrace],
        spatial: LottieSpatialEvaluationTrace? = nil
    ) {
        self.keyframeIndex = keyframeIndex
        self.authoredStartFrame = authoredStartFrame
        self.authoredEndFrame = authoredEndFrame
        self.evaluatedStartFrame = evaluatedStartFrame
        self.evaluatedEndFrame = evaluatedEndFrame
        self.startValue = startValue
        self.endValue = endValue
        self.linearProgress = linearProgress
        self.timingProgress = timingProgress
        self.interpolationSpace = interpolationSpace
        self.isHold = isHold
        self.timingCurves = timingCurves
        self.spatial = spatial
    }
}

public enum LottieInterpolationSpace: String, Codable, Sendable, Equatable {
    case value
    case spatialArcLength
}

public struct LottieTimingCurveTrace: Codable, Sendable, Equatable {
    public var component: Int
    public var outX: Double
    public var outY: Double
    public var inX: Double
    public var inY: Double
    public var result: Double

    public init(component: Int, outX: Double, outY: Double, inX: Double, inY: Double, result: Double) {
        self.component = component
        self.outX = outX
        self.outY = outY
        self.inX = inX
        self.inY = inY
        self.result = result
    }
}

public struct LottieSpatialEvaluationTrace: Codable, Sendable, Equatable {
    public var outTangent: [Double]
    public var inTangent: [Double]
    public var controlPoint1: [Double]
    public var controlPoint2: [Double]
    public var curveSegments: Int
    public var segmentLength: Double
    public var distance: Double
    public var pointIndex: Int
    public var pointSegmentProgress: Double?

    public init(
        outTangent: [Double],
        inTangent: [Double],
        controlPoint1: [Double],
        controlPoint2: [Double],
        curveSegments: Int,
        segmentLength: Double,
        distance: Double,
        pointIndex: Int,
        pointSegmentProgress: Double?
    ) {
        self.outTangent = outTangent
        self.inTangent = inTangent
        self.controlPoint1 = controlPoint1
        self.controlPoint2 = controlPoint2
        self.curveSegments = curveSegments
        self.segmentLength = segmentLength
        self.distance = distance
        self.pointIndex = pointIndex
        self.pointSegmentProgress = pointSegmentProgress
    }
}
