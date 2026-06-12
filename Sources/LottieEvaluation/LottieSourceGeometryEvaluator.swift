//
//  LottieSourceGeometryEvaluator.swift
//  PureLottie
//

import Foundation
import LottieModel

/// Lottie source-space geometry categories after primitive expansion.
public enum LottieSourceGeometryKind: String, Codable, Sendable, Equatable {
    case path
    case rectangle
    case ellipse
    case polygon
    case star
}

/// Authored/effective Lottie direction evidence for one geometry primitive.
public struct LottieSourceGeometryDirectionTrace: Codable, Sendable, Equatable {
    public var authoredValue: Int?
    public var effectiveValue: Int
    public var isReversed: Bool
    public var defaulted: Bool
    public var affectsContour: Bool
    public var interpretation: String

    public init(
        authoredValue: Int?,
        effectiveValue: Int,
        isReversed: Bool,
        defaulted: Bool,
        affectsContour: Bool,
        interpretation: String
    ) {
        self.authoredValue = authoredValue
        self.effectiveValue = effectiveValue
        self.isReversed = isReversed
        self.defaulted = defaulted
        self.affectsContour = affectsContour
        self.interpretation = interpretation
    }
}

/// One source field consumed while expanding a primitive.
public struct LottieSourceGeometryFieldTrace: Codable, Sendable, Equatable {
    public var field: String
    public var jsonPath: String
    public var value: [Double]?
    public var isAnimated: Bool
    public var propertyTrace: LottiePropertyEvaluationTrace?

    public init(
        field: String,
        jsonPath: String,
        value: [Double]?,
        isAnimated: Bool,
        propertyTrace: LottiePropertyEvaluationTrace?
    ) {
        self.field = field
        self.jsonPath = jsonPath
        self.value = value
        self.isAnimated = isAnimated
        self.propertyTrace = propertyTrace
    }
}

/// Compatibility constant or algorithm branch used to match lottie-web.
public struct LottieSourceGeometryConstant: Codable, Sendable, Equatable {
    public var name: String
    public var value: Double
    public var evidence: String

    public init(name: String, value: Double, evidence: String) {
        self.name = name
        self.value = value
        self.evidence = evidence
    }
}

/// Exact source-space bounds for the expanded cubic path.
public struct LottieSourceGeometryBounds: Codable, Sendable, Equatable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double {
        maxX - minX
    }

    public var height: Double {
        maxY - minY
    }

    public static let empty = LottieSourceGeometryBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)
}

/// Expanded Lottie source geometry before PureDraw/PureLayer lowering.
public struct LottieSourceGeometryTrace: Codable, Sendable, Equatable {
    public var kind: LottieSourceGeometryKind
    public var primitive: String
    public var sourcePath: String
    public var jsonPath: String
    public var sourceFrame: Double
    public var sourceFields: [LottieSourceGeometryFieldTrace]
    public var direction: LottieSourceGeometryDirectionTrace
    public var isClosed: Bool
    public var vertices: [[Double]]
    public var inTangents: [[Double]]
    public var outTangents: [[Double]]
    public var absoluteInTangents: [[Double]]
    public var absoluteOutTangents: [[Double]]
    public var bounds: LottieSourceGeometryBounds
    public var constants: [LottieSourceGeometryConstant]

    public init(
        kind: LottieSourceGeometryKind,
        primitive: String,
        sourcePath: String,
        jsonPath: String,
        sourceFrame: Double,
        sourceFields: [LottieSourceGeometryFieldTrace],
        direction: LottieSourceGeometryDirectionTrace,
        isClosed: Bool,
        vertices: [[Double]],
        inTangents: [[Double]],
        outTangents: [[Double]],
        absoluteInTangents: [[Double]],
        absoluteOutTangents: [[Double]],
        bounds: LottieSourceGeometryBounds,
        constants: [LottieSourceGeometryConstant]
    ) {
        self.kind = kind
        self.primitive = primitive
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.sourceFrame = sourceFrame
        self.sourceFields = sourceFields
        self.direction = direction
        self.isClosed = isClosed
        self.vertices = vertices
        self.inTangents = inTangents
        self.outTangents = outTangents
        self.absoluteInTangents = absoluteInTangents
        self.absoluteOutTangents = absoluteOutTangents
        self.bounds = bounds
        self.constants = constants
    }

    /// The trace as a Lottie-format Bezier path with relative in/out tangents.
    public var bezier: LottieBezier {
        LottieBezier(
            isClosed: isClosed,
            vertices: vertices,
            inTangents: inTangents,
            outTangents: outTangents
        )
    }
}

/// Expands modeled Lottie geometry into measurable source-space contours.
public struct LottieSourceGeometryEvaluator: Sendable {
    public let animation: LottieAnimation
    private let frameEvaluator: LottieFrameEvaluator

    public init(animation: LottieAnimation) {
        self.animation = animation
        frameEvaluator = LottieFrameEvaluator(animation: animation)
    }

    public func evaluate(
        _ geometry: LottieShapeProgram.Geometry,
        at sourceFrame: Double,
        sourcePath: String,
        jsonPath: JSONPath
    ) -> LottieEvaluationResult<LottieSourceGeometryTrace> {
        switch geometry {
        case let .path(path):
            evaluate(path, at: sourceFrame, sourcePath: sourcePath, jsonPath: jsonPath)
        case let .rectangle(rectangle):
            evaluate(rectangle, at: sourceFrame, sourcePath: sourcePath, jsonPath: jsonPath)
        case let .ellipse(ellipse):
            evaluate(ellipse, at: sourceFrame, sourcePath: sourcePath, jsonPath: jsonPath)
        case let .polystar(polystar):
            evaluate(polystar, at: sourceFrame, sourcePath: sourcePath, jsonPath: jsonPath)
        }
    }

    public func evaluate(
        _ path: ShapePath,
        at sourceFrame: Double,
        sourcePath: String,
        jsonPath: JSONPath
    ) -> LottieEvaluationResult<LottieSourceGeometryTrace> {
        let shape = frameEvaluator.evaluate(path.shape, at: sourceFrame, path: jsonPath.appending(.key("ks")))
        let bezier = shape.value ?? LottieBezier(isClosed: false, vertices: [], inTangents: [], outTangents: [])
        let absolute = absoluteVertices(from: bezier)
        let direction = directionTrace(
            authored: path.direction,
            defaultValue: 1,
            affectsContour: false,
            interpretation: "Raw `sh` Bezier vertices already carry authored order; lottie-web does not regenerate the path from `d`."
        )
        let trace = makeTrace(
            kind: .path,
            primitive: "sh",
            sourcePath: sourcePath,
            jsonPath: jsonPath,
            sourceFrame: sourceFrame,
            fields: [
                field("d", value: path.direction.map { [Double($0)] }, at: jsonPath.appending(.key("d"))),
                field("ks", value: nil, at: jsonPath.appending(.key("ks")), trace: shape.trace, animated: path.shape.isAnimated),
            ],
            direction: direction,
            points: absolute,
            isClosed: bezier.isClosed,
            constants: []
        )
        return LottieEvaluationResult(value: trace, diagnostics: shape.diagnostics, trace: shape.trace)
    }

    public func evaluate(
        _ rectangle: ShapeRectangle,
        at sourceFrame: Double,
        sourcePath: String,
        jsonPath: JSONPath
    ) -> LottieEvaluationResult<LottieSourceGeometryTrace> {
        let center = frameEvaluator.evaluate(rectangle.position, at: sourceFrame, path: jsonPath.appending(.key("p")))
        let size = frameEvaluator.evaluate(rectangle.size, at: sourceFrame, path: jsonPath.appending(.key("s")))
        let roundness = rectangle.roundness.map { value in
            frameEvaluator.evaluate(value, at: sourceFrame, path: jsonPath.appending(.key("r")))
        } ?? LottieEvaluationResult(value: 0)
        let points = rectanglePoints(
            center: center.value,
            size: size.value,
            roundness: roundness.value,
            direction: rectangle.direction
        )
        let direction = directionTrace(
            authored: rectangle.direction,
            defaultValue: 3,
            affectsContour: true,
            interpretation: "lottie-web rectangle branch uses `d == 1 || d == 2` for forward order; missing `d` follows the reversed branch."
        )
        let trace = makeTrace(
            kind: .rectangle,
            primitive: "rc",
            sourcePath: sourcePath,
            jsonPath: jsonPath,
            sourceFrame: sourceFrame,
            fields: [
                field("d", value: rectangle.direction.map { [Double($0)] }, at: jsonPath.appending(.key("d"))),
                field("p", value: center.value, at: jsonPath.appending(.key("p")), trace: center.trace, animated: rectangle.position.isAnimated),
                field("s", value: size.value, at: jsonPath.appending(.key("s")), trace: size.trace, animated: rectangle.size.isAnimated),
                field("r", value: [roundness.value], at: jsonPath.appending(.key("r")), trace: roundness.trace, animated: rectangle.roundness?.isAnimated == true),
            ],
            direction: direction,
            points: points,
            constants: [
                constant("roundCorner", Self.roundCorner, "lottie-web common.js roundCorner"),
                constant("radiusClamp", points.radiusClamp, "lottie-web uses min(width / 2, height / 2, r)"),
            ]
        )
        return LottieEvaluationResult(
            value: trace,
            diagnostics: center.diagnostics + size.diagnostics + roundness.diagnostics,
            trace: nil
        )
    }

    public func evaluate(
        _ ellipse: ShapeEllipse,
        at sourceFrame: Double,
        sourcePath: String,
        jsonPath: JSONPath
    ) -> LottieEvaluationResult<LottieSourceGeometryTrace> {
        let center = frameEvaluator.evaluate(ellipse.position, at: sourceFrame, path: jsonPath.appending(.key("p")))
        let size = frameEvaluator.evaluate(ellipse.size, at: sourceFrame, path: jsonPath.appending(.key("s")))
        let points = ellipsePoints(center: center.value, size: size.value, direction: ellipse.direction)
        let direction = directionTrace(
            authored: ellipse.direction,
            defaultValue: 1,
            affectsContour: true,
            interpretation: "lottie-web ellipse uses clockwise order unless `d == 3`; the first vertex stays at noon."
        )
        let trace = makeTrace(
            kind: .ellipse,
            primitive: "el",
            sourcePath: sourcePath,
            jsonPath: jsonPath,
            sourceFrame: sourceFrame,
            fields: [
                field("d", value: ellipse.direction.map { [Double($0)] }, at: jsonPath.appending(.key("d"))),
                field("p", value: center.value, at: jsonPath.appending(.key("p")), trace: center.trace, animated: ellipse.position.isAnimated),
                field("s", value: size.value, at: jsonPath.appending(.key("s")), trace: size.trace, animated: ellipse.size.isAnimated),
            ],
            direction: direction,
            points: points,
            constants: [
                constant("roundCorner", Self.roundCorner, "lottie-web common.js roundCorner"),
            ]
        )
        return LottieEvaluationResult(value: trace, diagnostics: center.diagnostics + size.diagnostics, trace: nil)
    }

    public func evaluate(
        _ polystar: ShapePolystar,
        at sourceFrame: Double,
        sourcePath: String,
        jsonPath: JSONPath
    ) -> LottieEvaluationResult<LottieSourceGeometryTrace> {
        var diagnostics: [ValidationError] = []
        let points = requiredScalar(polystar.points, key: "pt", label: "polystar points", sourceFrame: sourceFrame, jsonPath: jsonPath, diagnostics: &diagnostics)
        let position = requiredVector(polystar.position, key: "p", label: "polystar position", sourceFrame: sourceFrame, jsonPath: jsonPath, diagnostics: &diagnostics)
        let rotation = optionalScalar(polystar.rotation, key: "r", defaultValue: 0, sourceFrame: sourceFrame, jsonPath: jsonPath)
        let outerRadius = requiredScalar(polystar.outerRadius, key: "or", label: "polystar outer radius", sourceFrame: sourceFrame, jsonPath: jsonPath, diagnostics: &diagnostics)
        let outerRoundness = optionalScalar(polystar.outerRoundness, key: "os", defaultValue: 0, sourceFrame: sourceFrame, jsonPath: jsonPath)
        let innerRadius = optionalScalar(polystar.innerRadius, key: "ir", defaultValue: 0, sourceFrame: sourceFrame, jsonPath: jsonPath)
        let innerRoundness = optionalScalar(polystar.innerRoundness, key: "is", defaultValue: 0, sourceFrame: sourceFrame, jsonPath: jsonPath)
        diagnostics
            .append(contentsOf: points.diagnostics + position.diagnostics + rotation.diagnostics + outerRadius.diagnostics + outerRoundness.diagnostics + innerRadius
                .diagnostics + innerRoundness.diagnostics)

        let kind: LottieSourceGeometryKind
        switch polystar.starType {
        case 1:
            kind = .star
        case 2:
            kind = .polygon
        default:
            kind = .star
            diagnostics.append(diagnostic(
                ruleID: "lottie.evaluation.geometry.polystar-type",
                reason: "Polystar `sy` must be 1 for star or 2 for polygon before source geometry evaluation.",
                path: jsonPath.appending(.key("sy")),
                classification: .gap
            ))
        }

        let generated: GeneratedPoints
        switch kind {
        case .star:
            if polystar.innerRadius == nil {
                diagnostics.append(diagnostic(
                    ruleID: "lottie.evaluation.geometry.polystar-inner-radius",
                    reason: "Star polystar geometry requires `ir` before source geometry evaluation.",
                    path: jsonPath.appending(.key("ir")),
                    classification: .gap
                ))
            }
            generated = starPoints(
                points: points.value,
                position: position.value,
                rotationDegrees: rotation.value,
                outerRadius: outerRadius.value,
                outerRoundnessPercent: outerRoundness.value,
                innerRadius: innerRadius.value,
                innerRoundnessPercent: innerRoundness.value,
                direction: polystar.direction
            )
        case .polygon:
            generated = polygonPoints(
                points: points.value,
                position: position.value,
                rotationDegrees: rotation.value,
                outerRadius: outerRadius.value,
                outerRoundnessPercent: outerRoundness.value,
                direction: polystar.direction
            )
        case .path, .rectangle, .ellipse:
            generated = GeneratedPoints(points: [], radiusClamp: 0)
        }

        if polystar.points != nil, generated.points.isEmpty {
            diagnostics.append(diagnostic(
                ruleID: "lottie.evaluation.geometry.polystar-points",
                reason: "Polystar `pt` must floor to enough points to produce a closed source path.",
                path: jsonPath.appending(.key("pt")),
                classification: .gap
            ))
        }

        let direction = directionTrace(
            authored: polystar.direction,
            defaultValue: 1,
            affectsContour: true,
            interpretation: "lottie-web polystar advances angle by `d == 3 ? -1 : 1` while keeping the first vertex at rotation - 90 degrees."
        )
        let trace = makeTrace(
            kind: kind,
            primitive: "sr",
            sourcePath: sourcePath,
            jsonPath: jsonPath,
            sourceFrame: sourceFrame,
            fields: [
                field("sy", value: polystar.starType.map { [Double($0)] }, at: jsonPath.appending(.key("sy"))),
                field("d", value: polystar.direction.map { [Double($0)] }, at: jsonPath.appending(.key("d"))),
                field("pt", value: [points.value], at: jsonPath.appending(.key("pt")), trace: points.trace, animated: polystar.points?.isAnimated == true),
                field("p", value: position.value, at: jsonPath.appending(.key("p")), trace: position.trace, animated: polystar.position?.isAnimated == true),
                field("r", value: [rotation.value], at: jsonPath.appending(.key("r")), trace: rotation.trace, animated: polystar.rotation?.isAnimated == true),
                field("or", value: [outerRadius.value], at: jsonPath.appending(.key("or")), trace: outerRadius.trace, animated: polystar.outerRadius?.isAnimated == true),
                field("os", value: [outerRoundness.value], at: jsonPath.appending(.key("os")), trace: outerRoundness.trace, animated: polystar.outerRoundness?.isAnimated == true),
                field("ir", value: [innerRadius.value], at: jsonPath.appending(.key("ir")), trace: innerRadius.trace, animated: polystar.innerRadius?.isAnimated == true),
                field("is", value: [innerRoundness.value], at: jsonPath.appending(.key("is")), trace: innerRoundness.trace, animated: polystar.innerRoundness?.isAnimated == true),
            ],
            direction: direction,
            points: generated,
            constants: [
                constant("rotationOffsetRadians", -.pi / 2, "lottie-web starts stars and polygons at -PI/2 before authored rotation"),
                constant("roundnessPercentScale", 0.01, "lottie-web PropertyFactory scales os/is by 0.01"),
                constant("pointsFloor", floor(points.value), "lottie-web floors pt before generating star/polygon vertices"),
            ]
        )
        return LottieEvaluationResult(value: trace, diagnostics: diagnostics, trace: nil)
    }

    // MARK: Primitive Generation

    private static let roundCorner = 0.5519

    private func rectanglePoints(center: [Double], size: [Double], roundness: Double, direction: Int?) -> GeneratedPoints {
        let x = center.component(0) ?? 0
        let y = center.component(1) ?? 0
        let halfWidth = (size.component(0) ?? 0) / 2
        let halfHeight = (size.component(1) ?? 0) / 2
        let right = x + halfWidth
        let left = x - halfWidth
        let top = y - halfHeight
        let bottom = y + halfHeight
        let radius = min(halfWidth, halfHeight, roundness)
        let cPoint = radius * (1 - Self.roundCorner)
        let forward = direction == 1 || direction == 2

        if forward {
            if radius == 0 {
                return GeneratedPoints(points: [
                    point(right, top, out: [right, top], in: [right, top]),
                    point(right, bottom, out: [right, bottom], in: [right, bottom]),
                    point(left, bottom, out: [left, bottom], in: [left, bottom]),
                    point(left, top, out: [left, top], in: [left, top]),
                ], radiusClamp: radius)
            }
            return GeneratedPoints(points: [
                point(right, top + radius, out: [right, top + cPoint], in: [right, top + radius]),
                point(right, bottom - radius, out: [right, bottom - radius], in: [right, bottom - cPoint]),
                point(right - radius, bottom, out: [right - cPoint, bottom], in: [right - radius, bottom]),
                point(left + radius, bottom, out: [left + radius, bottom], in: [left + cPoint, bottom]),
                point(left, bottom - radius, out: [left, bottom - cPoint], in: [left, bottom - radius]),
                point(left, top + radius, out: [left, top + radius], in: [left, top + cPoint]),
                point(left + radius, top, out: [left + cPoint, top], in: [left + radius, top]),
                point(right - radius, top, out: [right - radius, top], in: [right - cPoint, top]),
            ], radiusClamp: radius)
        }

        if radius == 0 {
            return GeneratedPoints(points: [
                point(right, top, out: [right, top], in: [right, top]),
                point(left, top, out: [left, top], in: [left, top]),
                point(left, bottom, out: [left, bottom], in: [left, bottom]),
                point(right, bottom, out: [right, bottom], in: [right, bottom]),
            ], radiusClamp: radius)
        }
        return GeneratedPoints(points: [
            point(right, top + radius, out: [right, top + radius], in: [right, top + cPoint]),
            point(right - radius, top, out: [right - cPoint, top], in: [right - radius, top]),
            point(left + radius, top, out: [left + radius, top], in: [left + cPoint, top]),
            point(left, top + radius, out: [left, top + cPoint], in: [left, top + radius]),
            point(left, bottom - radius, out: [left, bottom - radius], in: [left, bottom - cPoint]),
            point(left + radius, bottom, out: [left + cPoint, bottom], in: [left + radius, bottom]),
            point(right - radius, bottom, out: [right - radius, bottom], in: [right - cPoint, bottom]),
            point(right, bottom - radius, out: [right, bottom - cPoint], in: [right, bottom - radius]),
        ], radiusClamp: radius)
    }

    private func ellipsePoints(center: [Double], size: [Double], direction: Int?) -> GeneratedPoints {
        let x = center.component(0) ?? 0
        let y = center.component(1) ?? 0
        let radiusX = (size.component(0) ?? 0) / 2
        let radiusY = (size.component(1) ?? 0) / 2
        let clockwise = direction != 3
        let sideX = clockwise ? x + radiusX : x - radiusX
        let oppositeX = clockwise ? x - radiusX : x + radiusX
        let controlX = radiusX * Self.roundCorner
        let controlY = radiusY * Self.roundCorner
        return GeneratedPoints(points: [
            point(x, y - radiusY, out: [clockwise ? x + controlX : x - controlX, y - radiusY], in: [clockwise ? x - controlX : x + controlX, y - radiusY]),
            point(sideX, y, out: [sideX, y + controlY], in: [sideX, y - controlY]),
            point(x, y + radiusY, out: [clockwise ? x - controlX : x + controlX, y + radiusY], in: [clockwise ? x + controlX : x - controlX, y + radiusY]),
            point(oppositeX, y, out: [oppositeX, y - controlY], in: [oppositeX, y + controlY]),
        ], radiusClamp: 0)
    }

    private func polygonPoints(
        points: Double,
        position: [Double],
        rotationDegrees: Double,
        outerRadius: Double,
        outerRoundnessPercent: Double,
        direction: Int?
    ) -> GeneratedPoints {
        let count = Int(floor(points))
        guard count >= 2 else { return GeneratedPoints(points: [], radiusClamp: 0) }
        let angleStep = (2 * Double.pi) / Double(count)
        let roundness = outerRoundnessPercent * 0.01
        let perimSegment = (2 * Double.pi * outerRadius) / Double(count * 4)
        let generated = (0 ..< count).map { index -> AbsolutePoint in
            starPoint(
                radius: outerRadius,
                roundness: roundness,
                perimSegment: perimSegment,
                angle: -.pi / 2 + rotationDegrees * .pi / 180 + angleStep * Double(index) * directionMultiplier(direction),
                position: position,
                direction: direction
            )
        }
        return GeneratedPoints(points: generated, radiusClamp: 0)
    }

    private func starPoints(
        points: Double,
        position: [Double],
        rotationDegrees: Double,
        outerRadius: Double,
        outerRoundnessPercent: Double,
        innerRadius: Double,
        innerRoundnessPercent: Double,
        direction: Int?
    ) -> GeneratedPoints {
        let count = Int(floor(points)) * 2
        guard count >= 4 else { return GeneratedPoints(points: [], radiusClamp: 0) }
        let angleStep = (2 * Double.pi) / Double(count)
        let outerRoundness = outerRoundnessPercent * 0.01
        let innerRoundness = innerRoundnessPercent * 0.01
        let outerPerimSegment = (2 * Double.pi * outerRadius) / Double(count * 2)
        let innerPerimSegment = (2 * Double.pi * innerRadius) / Double(count * 2)
        let generated = (0 ..< count).map { index -> AbsolutePoint in
            let isOuter = index.isMultiple(of: 2)
            return starPoint(
                radius: isOuter ? outerRadius : innerRadius,
                roundness: isOuter ? outerRoundness : innerRoundness,
                perimSegment: isOuter ? outerPerimSegment : innerPerimSegment,
                angle: -.pi / 2 + rotationDegrees * .pi / 180 + angleStep * Double(index) * directionMultiplier(direction),
                position: position,
                direction: direction
            )
        }
        return GeneratedPoints(points: generated, radiusClamp: 0)
    }

    private func starPoint(
        radius: Double,
        roundness: Double,
        perimSegment: Double,
        angle: Double,
        position: [Double],
        direction: Int?
    ) -> AbsolutePoint {
        let rawX = radius * cos(angle)
        let rawY = radius * sin(angle)
        let length = sqrt(rawX * rawX + rawY * rawY)
        let normalX = length == 0 ? 0 : rawY / length
        let normalY = length == 0 ? 0 : -rawX / length
        let x = rawX + (position.component(0) ?? 0)
        let y = rawY + (position.component(1) ?? 0)
        let tangentScale = perimSegment * roundness * directionMultiplier(direction)
        return point(
            x,
            y,
            out: [x - normalX * tangentScale, y - normalY * tangentScale],
            in: [x + normalX * tangentScale, y + normalY * tangentScale]
        )
    }

    // MARK: Trace Assembly

    private func makeTrace(
        kind: LottieSourceGeometryKind,
        primitive: String,
        sourcePath: String,
        jsonPath: JSONPath,
        sourceFrame: Double,
        fields: [LottieSourceGeometryFieldTrace],
        direction: LottieSourceGeometryDirectionTrace,
        points: GeneratedPoints,
        isClosed: Bool = true,
        constants: [LottieSourceGeometryConstant]
    ) -> LottieSourceGeometryTrace {
        let vertices = points.points.map(\.vertex)
        let inTangents = points.points.map { relative($0.inControl, to: $0.vertex) }
        let outTangents = points.points.map { relative($0.outControl, to: $0.vertex) }
        let absoluteInTangents = points.points.map(\.inControl)
        let absoluteOutTangents = points.points.map(\.outControl)
        return LottieSourceGeometryTrace(
            kind: kind,
            primitive: primitive,
            sourcePath: sourcePath,
            jsonPath: jsonPath.description,
            sourceFrame: sourceFrame,
            sourceFields: fields,
            direction: direction,
            isClosed: isClosed,
            vertices: vertices,
            inTangents: inTangents,
            outTangents: outTangents,
            absoluteInTangents: absoluteInTangents,
            absoluteOutTangents: absoluteOutTangents,
            bounds: bounds(vertices: vertices, inTangents: inTangents, outTangents: outTangents, closed: isClosed),
            constants: constants
        )
    }

    private func absoluteVertices(from bezier: LottieBezier) -> GeneratedPoints {
        let points = bezier.vertices.indices.map { index -> AbsolutePoint in
            let vertex = bezier.vertices[index]
            let inTangent = bezier.inTangents.indices.contains(index) ? bezier.inTangents[index] : []
            let outTangent = bezier.outTangents.indices.contains(index) ? bezier.outTangents[index] : []
            return point(
                vertex.component(0) ?? 0,
                vertex.component(1) ?? 0,
                out: [
                    (vertex.component(0) ?? 0) + (outTangent.component(0) ?? 0),
                    (vertex.component(1) ?? 0) + (outTangent.component(1) ?? 0),
                ],
                in: [
                    (vertex.component(0) ?? 0) + (inTangent.component(0) ?? 0),
                    (vertex.component(1) ?? 0) + (inTangent.component(1) ?? 0),
                ]
            )
        }
        return GeneratedPoints(points: points, radiusClamp: 0)
    }

    private func directionTrace(
        authored: Int?,
        defaultValue: Int,
        affectsContour: Bool,
        interpretation: String
    ) -> LottieSourceGeometryDirectionTrace {
        let effective = authored ?? defaultValue
        return LottieSourceGeometryDirectionTrace(
            authoredValue: authored,
            effectiveValue: effective,
            isReversed: effective == 3,
            defaulted: authored == nil,
            affectsContour: affectsContour,
            interpretation: interpretation
        )
    }

    private func field(
        _ key: String,
        value: [Double]?,
        at path: JSONPath,
        trace: LottiePropertyEvaluationTrace? = nil,
        animated: Bool = false
    ) -> LottieSourceGeometryFieldTrace {
        LottieSourceGeometryFieldTrace(
            field: key,
            jsonPath: path.description,
            value: value,
            isAnimated: animated,
            propertyTrace: trace
        )
    }

    private func constant(_ name: String, _ value: Double, _ evidence: String) -> LottieSourceGeometryConstant {
        LottieSourceGeometryConstant(name: name, value: value, evidence: evidence)
    }

    // MARK: Property Helpers

    private func requiredScalar(
        _ property: AnimatedDouble?,
        key: String,
        label: String,
        sourceFrame: Double,
        jsonPath: JSONPath,
        diagnostics: inout [ValidationError]
    ) -> LottieEvaluationResult<Double> {
        guard let property else {
            diagnostics.append(missingField(key: key, label: label, jsonPath: jsonPath))
            return LottieEvaluationResult(value: 0)
        }
        return frameEvaluator.evaluate(property, at: sourceFrame, path: jsonPath.appending(.key(key)))
    }

    private func optionalScalar(
        _ property: AnimatedDouble?,
        key: String,
        defaultValue: Double,
        sourceFrame: Double,
        jsonPath: JSONPath
    ) -> LottieEvaluationResult<Double> {
        guard let property else {
            return LottieEvaluationResult(value: defaultValue)
        }
        return frameEvaluator.evaluate(property, at: sourceFrame, path: jsonPath.appending(.key(key)))
    }

    private func requiredVector(
        _ property: AnimatedVector?,
        key: String,
        label: String,
        sourceFrame: Double,
        jsonPath: JSONPath,
        diagnostics: inout [ValidationError]
    ) -> LottieEvaluationResult<[Double]> {
        guard let property else {
            diagnostics.append(missingField(key: key, label: label, jsonPath: jsonPath))
            return LottieEvaluationResult(value: [])
        }
        return frameEvaluator.evaluate(property, at: sourceFrame, path: jsonPath.appending(.key(key)))
    }

    private func missingField(key: String, label: String, jsonPath: JSONPath) -> ValidationError {
        diagnostic(
            ruleID: "lottie.evaluation.geometry.required-field",
            reason: "Required \(label) field `\(key)` is missing before source geometry evaluation.",
            path: jsonPath.appending(.key(key)),
            classification: .gap
        )
    }

    private func diagnostic(ruleID: String, reason: String, path: JSONPath, classification: FeatureClassification) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: reason,
            at: path,
            severity: .warning,
            phase: .semantic,
            classification: classification
        )
    }

    // MARK: Bounds

    private func bounds(vertices: [[Double]], inTangents: [[Double]], outTangents: [[Double]], closed: Bool) -> LottieSourceGeometryBounds {
        guard !vertices.isEmpty else { return .empty }
        var candidates = vertices
        let segmentCount = closed ? vertices.count : max(vertices.count - 1, 0)
        for segment in 0 ..< segmentCount {
            let from = segment
            let to = segment == vertices.count - 1 ? 0 : segment + 1
            let p0 = vertices[from]
            let p1 = [
                (p0.component(0) ?? 0) + (outTangents.indices.contains(from) ? (outTangents[from].component(0) ?? 0) : 0),
                (p0.component(1) ?? 0) + (outTangents.indices.contains(from) ? (outTangents[from].component(1) ?? 0) : 0),
            ]
            let p3 = vertices[to]
            let p2 = [
                (p3.component(0) ?? 0) + (inTangents.indices.contains(to) ? (inTangents[to].component(0) ?? 0) : 0),
                (p3.component(1) ?? 0) + (inTangents.indices.contains(to) ? (inTangents[to].component(1) ?? 0) : 0),
            ]
            for t in cubicExtrema(p0: p0, p1: p1, p2: p2, p3: p3) {
                candidates.append(cubicPoint(p0: p0, p1: p1, p2: p2, p3: p3, t: t))
            }
        }
        let xs = candidates.map { $0.component(0) ?? 0 }
        let ys = candidates.map { $0.component(1) ?? 0 }
        return LottieSourceGeometryBounds(
            minX: xs.min() ?? 0,
            minY: ys.min() ?? 0,
            maxX: xs.max() ?? 0,
            maxY: ys.max() ?? 0
        )
    }

    private func cubicExtrema(p0: [Double], p1: [Double], p2: [Double], p3: [Double]) -> [Double] {
        var roots: [Double] = []
        roots.append(contentsOf: cubicExtrema1D(p0: p0.component(0) ?? 0, p1: p1.component(0) ?? 0, p2: p2.component(0) ?? 0, p3: p3.component(0) ?? 0))
        roots.append(contentsOf: cubicExtrema1D(p0: p0.component(1) ?? 0, p1: p1.component(1) ?? 0, p2: p2.component(1) ?? 0, p3: p3.component(1) ?? 0))
        return Array(Set(roots)).filter { $0 > 0 && $0 < 1 }.sorted()
    }

    private func cubicExtrema1D(p0: Double, p1: Double, p2: Double, p3: Double) -> [Double] {
        let a = -p0 + 3 * p1 - 3 * p2 + p3
        let b = 2 * (p0 - 2 * p1 + p2)
        let c = p1 - p0
        if abs(a) < 0.0000001 {
            guard abs(b) > 0.0000001 else { return [] }
            return [-c / b]
        }
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return [] }
        let root = sqrt(discriminant)
        return [(-b + root) / (2 * a), (-b - root) / (2 * a)]
    }

    private func cubicPoint(p0: [Double], p1: [Double], p2: [Double], p3: [Double], t: Double) -> [Double] {
        let mt = 1 - t
        return [
            mt * mt * mt * (p0.component(0) ?? 0)
                + 3 * mt * mt * t * (p1.component(0) ?? 0)
                + 3 * mt * t * t * (p2.component(0) ?? 0)
                + t * t * t * (p3.component(0) ?? 0),
            mt * mt * mt * (p0.component(1) ?? 0)
                + 3 * mt * mt * t * (p1.component(1) ?? 0)
                + 3 * mt * t * t * (p2.component(1) ?? 0)
                + t * t * t * (p3.component(1) ?? 0),
        ]
    }

    // MARK: Point Helpers

    private func point(_ x: Double, _ y: Double, out: [Double], in inControl: [Double]) -> AbsolutePoint {
        AbsolutePoint(vertex: [x, y], inControl: inControl, outControl: out)
    }

    private func relative(_ point: [Double], to vertex: [Double]) -> [Double] {
        [
            (point.component(0) ?? 0) - (vertex.component(0) ?? 0),
            (point.component(1) ?? 0) - (vertex.component(1) ?? 0),
        ]
    }

    private func directionMultiplier(_ direction: Int?) -> Double {
        direction == 3 ? -1 : 1
    }
}

private struct AbsolutePoint: Equatable {
    var vertex: [Double]
    var inControl: [Double]
    var outControl: [Double]
}

private struct GeneratedPoints: Equatable {
    var points: [AbsolutePoint]
    var radiusClamp: Double
}

private extension [Double] {
    func component(_ index: Int) -> Double? {
        if indices.contains(index) { return self[index] }
        return last
    }
}
