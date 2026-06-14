//
//  LottieGeometryTrace.swift
//  PureLottie
//

import LottieEvaluation
import LottieModel
import PureLayer

/// Numeric geometry evidence for one Lottie import/render sample set.
public struct LottieGeometryTrace: Encodable, Equatable {
    public var scale: Double
    public var coordinateSemantics: [String]
    public var frames: [LottieGeometryFrameTrace]
}

/// Numeric geometry evidence for one source frame.
public struct LottieGeometryFrameTrace: Encodable, Equatable {
    public var sourceFrame: Double
    public var timeSeconds: Double
    public var expected: [LottieExpectedGeometry]
    public var actual: [PureLayerDrawGeometry]
    public var comparisons: [LottieGeometryComparison]
    public var unmatchedExpectedCount: Int
    public var unmatchedActualCount: Int
}

/// One Lottie-side geometry item after semantic evaluation.
public struct LottieExpectedGeometry: Encodable, Equatable {
    public var index: Int
    public var kind: String
    public var sourcePath: String
    public var jsonPath: String
    public var layerName: String
    public var layerIndex: Int?
    public var localFrame: Double
    public var opacity: Double
    public var transform: LottieTransformTrace
    public var compositionBounds: LottieGeometryBounds
    public var outputBounds: LottieGeometryBounds
}

/// One PureLayer draw-list geometry item after applying the compositor transform stack.
public struct PureLayerDrawGeometry: Encodable, Equatable {
    public var index: Int
    public var kind: String
    public var opacity: Double?
    public var lineWidth: Double?
    public var bounds: LottieGeometryBounds
}

/// A positional comparison between the Lottie-side item and the corresponding PureLayer draw item.
public struct LottieGeometryComparison: Encodable, Equatable {
    public var index: Int
    public var expectedKind: String
    public var actualKind: String?
    public var sourcePath: String
    public var expectedCompositionBounds: LottieGeometryBounds
    public var expectedOutputBounds: LottieGeometryBounds
    public var actualPureLayerBounds: LottieGeometryBounds?
    public var deltaToExpectedCompositionBounds: LottieGeometryBounds?
    public var deltaToExpectedOutputBounds: LottieGeometryBounds?
    public var matchesExpectedOutputBounds: Bool
}

/// A 2D bounds record with explicit min/max values for stable JSON/CSV output.
public struct LottieGeometryBounds: Encodable, Equatable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double
    public var width: Double
    public var height: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
        width = maxX - minX
        height = maxY - minY
    }

    init(_ rect: Rect) {
        self.init(minX: rect.minX, minY: rect.minY, maxX: rect.maxX, maxY: rect.maxY)
    }

    func scaled(by scale: Double) -> LottieGeometryBounds {
        LottieGeometryBounds(
            minX: minX * scale,
            minY: minY * scale,
            maxX: maxX * scale,
            maxY: maxY * scale
        )
    }

    func delta(from expected: LottieGeometryBounds) -> LottieGeometryBounds {
        LottieGeometryBounds(
            minX: minX - expected.minX,
            minY: minY - expected.minY,
            maxX: maxX - expected.maxX,
            maxY: maxY - expected.maxY
        )
    }

    func isClose(to other: LottieGeometryBounds, tolerance: Double = 0.0001) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(maxX - other.maxX) <= tolerance
            && abs(maxY - other.maxY) <= tolerance
    }
}

/// The evaluated layer transform values that positioned a Lottie geometry item.
public struct LottieTransformTrace: Encodable, Equatable {
    public var anchor: [Double]
    public var position: [Double]
    public var scale: [Double]
    public var rotationZDegrees: Double
    public var matrix: [Double]
}

/// Builds coordinate traces by comparing evaluated Lottie geometry with PureLayer draw-list geometry.
public struct LottieGeometryTraceBuilder {
    public init() {}

    public func trace(
        animation: LottieAnimation,
        renderRoot: Layer?,
        sourceFrames: [Double],
        scale: Double
    ) -> LottieGeometryTrace {
        trace(
            animation: animation,
            sourceFrames: sourceFrames,
            scale: scale,
            renderRoot: { _, _ in renderRoot }
        )
    }

    public func trace(
        animation: LottieAnimation,
        sourceFrames: [Double],
        scale: Double,
        renderRoot: (Double, Double) -> Layer?
    ) -> LottieGeometryTrace {
        let builder = LottieRenderIRBuilder(animation: animation)
        let compositor = Compositor()
        let frames = sourceFrames.map { sourceFrame in
            let timeSeconds = max(0, (sourceFrame - animation.inPoint) / animation.frameRate)
            let renderFrame = builder.frame(at: sourceFrame)
            let expected = expectedGeometries(in: renderFrame, scale: scale)
            let root = renderRoot(sourceFrame, timeSeconds)
            let actual = root.map { actualGeometries(in: compositor.drawList(for: $0, at: timeSeconds)) } ?? []
            return LottieGeometryFrameTrace(
                sourceFrame: sourceFrame,
                timeSeconds: timeSeconds,
                expected: expected,
                actual: actual,
                comparisons: comparisons(expected: expected, actual: actual),
                unmatchedExpectedCount: max(0, expected.count - actual.count),
                unmatchedActualCount: max(0, actual.count - expected.count)
            )
        }
        return LottieGeometryTrace(
            scale: scale,
            coordinateSemantics: [
                "expected.compositionBounds are evaluated Lottie composition-space points after layer and shape transforms.",
                "expected.outputBounds are expected.compositionBounds multiplied by the requested render scale.",
                "actual.bounds are PureLayer draw-list bounds after the compositor transform stack, in the output surface coordinate space.",
                "deltaToExpectedOutputBounds must be approximately zero for a correctly placed scaled export.",
            ],
            frames: frames
        )
    }

    private func comparisons(
        expected: [LottieExpectedGeometry],
        actual: [PureLayerDrawGeometry]
    ) -> [LottieGeometryComparison] {
        expected.enumerated().map { offset, expectedGeometry in
            let actualGeometry = actual.indices.contains(offset) ? actual[offset] : nil
            let deltaToComposition = actualGeometry?.bounds.delta(from: expectedGeometry.compositionBounds)
            let deltaToOutput = actualGeometry?.bounds.delta(from: expectedGeometry.outputBounds)
            return LottieGeometryComparison(
                index: offset,
                expectedKind: expectedGeometry.kind,
                actualKind: actualGeometry?.kind,
                sourcePath: expectedGeometry.sourcePath,
                expectedCompositionBounds: expectedGeometry.compositionBounds,
                expectedOutputBounds: expectedGeometry.outputBounds,
                actualPureLayerBounds: actualGeometry?.bounds,
                deltaToExpectedCompositionBounds: deltaToComposition,
                deltaToExpectedOutputBounds: deltaToOutput,
                matchesExpectedOutputBounds: actualGeometry?.bounds.isClose(to: expectedGeometry.outputBounds) ?? false
            )
        }
    }

    private func expectedGeometries(in frame: LottieRenderFrame, scale: Double) -> [LottieExpectedGeometry] {
        var result: [LottieExpectedGeometry] = []
        for node in frame.nodes {
            result.append(contentsOf: expectedGeometries(in: node, scale: scale, startIndex: result.count))
        }
        return result
    }

    private func expectedGeometries(
        in node: LottieRenderNode,
        scale: Double,
        startIndex: Int
    ) -> [LottieExpectedGeometry] {
        let layerTransform = affine(for: node.transform.worldMatrix)
        let transformTrace = LottieTransformTrace(
            anchor: node.transform.local.anchor,
            position: node.transform.local.position,
            scale: node.transform.local.scale,
            rotationZDegrees: node.transform.local.rotationZDegrees,
            matrix: node.transform.worldMatrix.values
        )

        switch node.kind {
        case let .shape(shape):
            var geometries: [LottieExpectedGeometry] = []
            for draw in shape.draws {
                for run in pathRuns(for: draw) {
                    var path = run.path
                    if case .stroke = draw.style, let trim = run.trim, !isIdentity(trim) {
                        path = path.trimmedForStroke(from: fraction(trim.start), to: fraction(trim.end))
                    }
                    guard !path.isEmpty else { continue }
                    let compositionBounds = LottieGeometryBounds(path.applying(layerTransform).boundingBox)
                    geometries.append(LottieExpectedGeometry(
                        index: startIndex + geometries.count,
                        kind: draw.style.geometryKind,
                        sourcePath: draw.source.sourcePath,
                        jsonPath: draw.source.jsonPath.description,
                        layerName: node.layerName,
                        layerIndex: node.layerIndex,
                        localFrame: node.localFrame,
                        opacity: node.opacity,
                        transform: transformTrace,
                        compositionBounds: compositionBounds,
                        outputBounds: compositionBounds.scaled(by: scale)
                    ))
                }
            }
            return geometries
        case let .solid(solid):
            let rect = Rect(x: 0, y: 0, width: solid.width, height: solid.height)
            let compositionBounds = LottieGeometryBounds(rect.applying(layerTransform))
            return [
                LottieExpectedGeometry(
                    index: startIndex,
                    kind: "solid",
                    sourcePath: node.source.sourcePath,
                    jsonPath: node.source.jsonPath.description,
                    layerName: node.layerName,
                    layerIndex: node.layerIndex,
                    localFrame: node.localFrame,
                    opacity: node.opacity,
                    transform: transformTrace,
                    compositionBounds: compositionBounds,
                    outputBounds: compositionBounds.scaled(by: scale)
                ),
            ]
        default:
            return []
        }
    }

    private func actualGeometries(in drawList: DrawList) -> [PureLayerDrawGeometry] {
        var collector = DrawListGeometryCollector()
        return collector.collect(drawList.commands)
    }

    private struct PathRun: Equatable {
        var path: Path
        var trim: LottieRenderTrim?
    }

    private func pathRuns(for draw: LottieRenderShapeDraw) -> [PathRun] {
        var runs: [PathRun] = []
        for fragment in draw.fragments {
            guard let path = path(for: fragment), !path.isEmpty else { continue }
            let trim = trim(in: fragment.modifiers)
            if let last = runs.last, last.trim == trim {
                var merged = last.path
                merged.addPath(path)
                runs[runs.count - 1] = PathRun(path: merged, trim: trim)
            } else {
                runs.append(PathRun(path: path, trim: trim))
            }
        }
        return runs
    }

    private func trim(in modifiers: [LottieRenderShapeModifier]) -> LottieRenderTrim? {
        modifiers.compactMap { modifier -> LottieRenderTrim? in
            if case let .trim(trim) = modifier { return trim }
            return nil
        }
        .last
    }

    private func isIdentity(_ trim: LottieRenderTrim) -> Bool {
        abs(trim.start) <= 0.0001
            && abs(trim.end - 100) <= 0.0001
            && abs(trim.offset) <= 0.0001
    }

    private func fraction(_ percent: Double) -> Double {
        min(max(percent / 100, 0), 1)
    }

    private func path(for fragment: LottieRenderGeometryFragment) -> Path? {
        var path = Path()
        PathBuilder.path(from: fragment.sourceGeometry.bezier, into: &path)
        guard !path.isEmpty else { return nil }
        return path.applying(affine(for: fragment.transformStack))
    }

    private func affine(for transformStack: [LottieRenderShapeTransform]) -> AffineTransform {
        transformStack.reduce(.identity) { result, transform in
            result.concatenating(affine(for: transform))
        }
    }

    private func affine(for transform: LottieRenderShapeTransform) -> AffineTransform {
        AffineTransform.translation(
            x: -transform.anchor.scalar(0),
            y: -transform.anchor.scalar(1)
        )
        .concatenating(.scale(
            x: transform.scale.scalar(0, default: 100) / 100,
            y: transform.scale.scalar(1, default: 100) / 100
        ))
        .concatenating(.rotation(angle: transform.rotationDegrees * .pi / 180))
        .concatenating(.translation(
            x: transform.position.scalar(0),
            y: transform.position.scalar(1)
        ))
    }

    private func affine(for matrix: LottieTransformMatrix) -> AffineTransform {
        let values = matrix.values
        return AffineTransform(
            a: values[0],
            b: values[1],
            c: values[4],
            d: values[5],
            tx: values[12],
            ty: values[13]
        )
    }
}

private extension Path {
    func trimmedForStroke(from start: Double, to end: Double) -> Path {
        let lower = min(max(start, 0), 1)
        let upper = min(max(end, 0), 1)
        guard upper > lower else { return Path() }
        guard lower > 0 || upper < 1 else { return self }

        let box = boundingBox
        let diagonal = (box.width * box.width + box.height * box.height).squareRoot()
        let polylines = subdivided(maxSegmentLength: max(diagonal / 512, 0.05)).toPolylines()
        let runs = polylines.map { polyline in
            guard polyline.isClosed,
                  let first = polyline.points.first,
                  let last = polyline.points.last,
                  first != last
            else {
                return polyline.points
            }
            return polyline.points + [first]
        }

        var total = 0.0
        for points in runs {
            for index in points.indices.dropLast() {
                total += distance(points[index], points[index + 1])
            }
        }
        guard total > 0 else { return Path() }

        let window = (lower: lower * total, upper: upper * total)
        var trimmed = Path()
        var traversed = 0.0
        var emittedThrough: Double?

        for points in runs {
            for index in points.indices.dropLast() {
                let segmentStart = points[index]
                let segmentEnd = points[index + 1]
                let length = distance(segmentStart, segmentEnd)
                guard length > 0 else { continue }
                let from = max(window.lower, traversed)
                let to = min(window.upper, traversed + length)
                if from < to {
                    let head = lerp(segmentStart, segmentEnd, (from - traversed) / length)
                    let tail = lerp(segmentStart, segmentEnd, (to - traversed) / length)
                    if emittedThrough != from {
                        trimmed.move(to: head)
                    }
                    trimmed.addLine(to: tail)
                    emittedThrough = to
                }
                traversed += length
            }
            emittedThrough = nil
        }
        return trimmed
    }

    private func distance(_ left: Point, _ right: Point) -> Double {
        let x = right.x - left.x
        let y = right.y - left.y
        return (x * x + y * y).squareRoot()
    }

    private func lerp(_ left: Point, _ right: Point, _ fraction: Double) -> Point {
        Point(
            x: left.x + (right.x - left.x) * fraction,
            y: left.y + (right.y - left.y) * fraction
        )
    }
}

private struct DrawListGeometryCollector {
    private var currentTransform = AffineTransform.identity
    private var transformStack: [AffineTransform] = []
    private var geometries: [PureLayerDrawGeometry] = []

    mutating func collect(_ commands: [DrawList.Command]) -> [PureLayerDrawGeometry] {
        for command in commands {
            switch command {
            case let .fillQuad(frame: frame, color: _, opacity: opacity):
                append(kind: "fillQuad", bounds: frame.applying(currentTransform), opacity: opacity)
            case let .fillRoundedQuad(frame: frame, cornerRadius: _, continuous: _, color: _, opacity: opacity):
                append(kind: "fillRoundedQuad", bounds: frame.applying(currentTransform), opacity: opacity)
            case let .strokeRoundedQuad(frame: frame, cornerRadius: _, continuous: _, lineWidth: lineWidth, color: _, opacity: opacity):
                append(kind: "strokeRoundedQuad", bounds: frame.applying(currentTransform), opacity: opacity, lineWidth: lineWidth)
            case let .image(_, destination: destination, opacity: opacity):
                append(kind: "image", bounds: destination.applying(currentTransform), opacity: opacity)
            case let .fillPath(path, color: _, opacity: opacity, rule: _):
                append(kind: "fillPath", bounds: path.applying(currentTransform).boundingBox, opacity: opacity)
            case let .strokePath(path, color: _, style: style, opacity: opacity):
                append(kind: "strokePath", bounds: path.applying(currentTransform).boundingBox, opacity: opacity, lineWidth: style.lineWidth)
            case let .gradient(frame: frame, cornerRadius: _, continuous: _, _):
                append(kind: "gradient", bounds: frame.applying(currentTransform), opacity: nil)
            case let .text(_, font: _, fontSize: _, color: _, position: position, opacity: opacity):
                append(kind: "text", bounds: Rect(x: position.x, y: position.y, width: 0, height: 0).applying(currentTransform), opacity: opacity)
            case .pushClip,
                 .pushRoundedClip,
                 .pushClipPath,
                 .popClip,
                 .beginTransparencyLayer,
                 .endTransparencyLayer,
                 .pushShadow,
                 .dropShadow,
                 .popShadow,
                 .pushMask,
                 .popMask,
                 .pushBlendMode,
                 .popBlendMode,
                 .transform3D:
                continue
            case let .pushTransform(transform):
                transformStack.append(currentTransform)
                currentTransform = currentTransform.concatenating(transform)
            case .popTransform:
                currentTransform = transformStack.popLast() ?? .identity
            }
        }
        return geometries
    }

    private mutating func append(kind: String, bounds: Rect, opacity: Double?, lineWidth: Double? = nil) {
        geometries.append(PureLayerDrawGeometry(
            index: geometries.count,
            kind: kind,
            opacity: opacity,
            lineWidth: lineWidth,
            bounds: LottieGeometryBounds(bounds)
        ))
    }
}

private extension LottieRenderShapeStyle {
    var geometryKind: String {
        switch self {
        case .fill:
            "fillPath"
        case .stroke:
            "strokePath"
        }
    }
}

private extension [Double] {
    func scalar(_ index: Int, default defaultValue: Double = 0) -> Double {
        if indices.contains(index) { return self[index] }
        return last ?? defaultValue
    }
}
