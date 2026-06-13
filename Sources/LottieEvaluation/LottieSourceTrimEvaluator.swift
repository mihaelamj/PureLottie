//
//  LottieSourceTrimEvaluator.swift
//  PureLottie
//

import Foundation
import LottieModel

/// Lottie trim-path mode after resolving the authored `m` value.
public enum LottieSourceTrimMode: String, Codable, Sendable, Equatable {
    /// `m: 1`; every path receives the same normalized trim range.
    case parallel
    /// `m: 2`; paths are treated as one continuous length sequence.
    case sequential
}

/// lottie-web trim normalization evidence for one source frame.
public struct LottieSourceTrimNormalizationTrace: Codable, Sendable, Equatable {
    public var authoredStartPercent: Double
    public var authoredEndPercent: Double
    public var authoredOffsetDegrees: Double
    public var rawStartFraction: Double
    public var rawEndFraction: Double
    public var offsetTurns: Double
    public var normalizedStartFraction: Double
    public var normalizedEndFraction: Double
    public var swappedStartEnd: Bool
    public var isEmpty: Bool
    public var isFull: Bool

    public init(
        authoredStartPercent: Double,
        authoredEndPercent: Double,
        authoredOffsetDegrees: Double,
        rawStartFraction: Double,
        rawEndFraction: Double,
        offsetTurns: Double,
        normalizedStartFraction: Double,
        normalizedEndFraction: Double,
        swappedStartEnd: Bool,
        isEmpty: Bool,
        isFull: Bool
    ) {
        self.authoredStartPercent = authoredStartPercent
        self.authoredEndPercent = authoredEndPercent
        self.authoredOffsetDegrees = authoredOffsetDegrees
        self.rawStartFraction = rawStartFraction
        self.rawEndFraction = rawEndFraction
        self.offsetTurns = offsetTurns
        self.normalizedStartFraction = normalizedStartFraction
        self.normalizedEndFraction = normalizedEndFraction
        self.swappedStartEnd = swappedStartEnd
        self.isEmpty = isEmpty
        self.isFull = isFull
    }
}

/// Named approximation or compatibility constant used by trim evaluation.
public struct LottieSourceTrimApproximation: Codable, Sendable, Equatable {
    public var name: String
    public var value: Double
    public var evidence: String

    public init(name: String, value: Double, evidence: String) {
        self.name = name
        self.value = value
        self.evidence = evidence
    }
}

/// Original path length evidence before trimming.
public struct LottieSourceTrimPathLengthTrace: Codable, Sendable, Equatable {
    public var pathIndex: Int
    public var sourcePath: String
    public var jsonPath: String
    public var primitive: String
    public var isClosed: Bool
    public var totalLength: Double
    public var cubicSegmentLengths: [Double]

    public init(
        pathIndex: Int,
        sourcePath: String,
        jsonPath: String,
        primitive: String,
        isClosed: Bool,
        totalLength: Double,
        cubicSegmentLengths: [Double]
    ) {
        self.pathIndex = pathIndex
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.primitive = primitive
        self.isClosed = isClosed
        self.totalLength = totalLength
        self.cubicSegmentLengths = cubicSegmentLengths
    }
}

/// One original cubic segment interval selected by trim.
public struct LottieSourceTrimCubicSegmentTrace: Codable, Sendable, Equatable {
    public var cubicSegmentIndex: Int
    public var startLength: Double
    public var endLength: Double
    public var startPercent: Double
    public var endPercent: Double

    public init(
        cubicSegmentIndex: Int,
        startLength: Double,
        endLength: Double,
        startPercent: Double,
        endPercent: Double
    ) {
        self.cubicSegmentIndex = cubicSegmentIndex
        self.startLength = startLength
        self.endLength = endLength
        self.startPercent = startPercent
        self.endPercent = endPercent
    }
}

/// One path-level trim interval selected from original source geometry.
public struct LottieSourceTrimSelectedSegmentTrace: Codable, Sendable, Equatable {
    public var pathIndex: Int
    public var sourcePath: String
    public var jsonPath: String
    public var sequenceOrdinal: Int
    public var startLength: Double
    public var endLength: Double
    public var startFraction: Double
    public var endFraction: Double
    public var globalStartLength: Double?
    public var globalEndLength: Double?
    public var cubicSegments: [LottieSourceTrimCubicSegmentTrace]

    public init(
        pathIndex: Int,
        sourcePath: String,
        jsonPath: String,
        sequenceOrdinal: Int,
        startLength: Double,
        endLength: Double,
        startFraction: Double,
        endFraction: Double,
        globalStartLength: Double?,
        globalEndLength: Double?,
        cubicSegments: [LottieSourceTrimCubicSegmentTrace]
    ) {
        self.pathIndex = pathIndex
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.sequenceOrdinal = sequenceOrdinal
        self.startLength = startLength
        self.endLength = endLength
        self.startFraction = startFraction
        self.endFraction = endFraction
        self.globalStartLength = globalStartLength
        self.globalEndLength = globalEndLength
        self.cubicSegments = cubicSegments
    }
}

/// Generated trim result path in Lottie Bezier terms.
public struct LottieSourceTrimResultPathTrace: Codable, Sendable, Equatable {
    public var pathIndex: Int
    public var sourcePath: String
    public var jsonPath: String
    public var selectedSegmentIndex: Int?
    public var isClosed: Bool
    public var vertices: [[Double]]
    public var inTangents: [[Double]]
    public var outTangents: [[Double]]

    public init(
        pathIndex: Int,
        sourcePath: String,
        jsonPath: String,
        selectedSegmentIndex: Int?,
        isClosed: Bool,
        vertices: [[Double]],
        inTangents: [[Double]],
        outTangents: [[Double]]
    ) {
        self.pathIndex = pathIndex
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.selectedSegmentIndex = selectedSegmentIndex
        self.isClosed = isClosed
        self.vertices = vertices
        self.inTangents = inTangents
        self.outTangents = outTangents
    }

    public var bezier: LottieBezier {
        LottieBezier(
            isClosed: isClosed,
            vertices: vertices,
            inTangents: inTangents,
            outTangents: outTangents
        )
    }
}

/// Complete trim-path source intent for one evaluated modifier.
public struct LottieSourceTrimTrace: Codable, Sendable, Equatable {
    public var sourcePath: String
    public var jsonPath: String
    public var sourceFrame: Double
    public var authoredMultiple: Int?
    public var mode: LottieSourceTrimMode
    public var normalization: LottieSourceTrimNormalizationTrace
    public var inputPaths: [LottieSourceTrimPathLengthTrace]
    public var totalLength: Double
    public var sequenceOrder: [String]
    public var selectedSegments: [LottieSourceTrimSelectedSegmentTrace]
    public var resultPaths: [LottieSourceTrimResultPathTrace]
    public var approximations: [LottieSourceTrimApproximation]

    public init(
        sourcePath: String,
        jsonPath: String,
        sourceFrame: Double,
        authoredMultiple: Int?,
        mode: LottieSourceTrimMode,
        normalization: LottieSourceTrimNormalizationTrace,
        inputPaths: [LottieSourceTrimPathLengthTrace],
        totalLength: Double,
        sequenceOrder: [String],
        selectedSegments: [LottieSourceTrimSelectedSegmentTrace],
        resultPaths: [LottieSourceTrimResultPathTrace],
        approximations: [LottieSourceTrimApproximation]
    ) {
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.sourceFrame = sourceFrame
        self.authoredMultiple = authoredMultiple
        self.mode = mode
        self.normalization = normalization
        self.inputPaths = inputPaths
        self.totalLength = totalLength
        self.sequenceOrder = sequenceOrder
        self.selectedSegments = selectedSegments
        self.resultPaths = resultPaths
        self.approximations = approximations
    }
}

/// Evaluates Lottie trim-path source semantics before backend lowering.
public struct LottieSourceTrimEvaluator: Sendable {
    public init() {}

    public func evaluate(
        trim: LottieRenderTrim,
        paths: [LottieSourceGeometryTrace],
        sourceFrame: Double
    ) -> LottieEvaluationResult<LottieSourceTrimTrace> {
        var diagnostics: [ValidationError] = []
        let mode = resolvedMode(for: trim, diagnostics: &diagnostics)
        let measuredPaths = paths.enumerated().map { offset, path in
            MeasuredPath(pathIndex: offset, source: path)
        }
        let totalLength = measuredPaths.reduce(0) { $0 + $1.totalLength }
        let normalization = Self.normalize(start: trim.start, end: trim.end, offset: trim.offset)

        let selection = selectedSegments(
            mode: mode,
            normalization: normalization,
            paths: measuredPaths,
            totalLength: totalLength
        )
        let resultPaths = resultPaths(
            for: selection.segments,
            in: measuredPaths,
            emptyPaths: normalization.isEmpty
        )

        let trace = LottieSourceTrimTrace(
            sourcePath: trim.source.sourcePath,
            jsonPath: trim.source.jsonPath.description,
            sourceFrame: sourceFrame,
            authoredMultiple: trim.multiple,
            mode: mode,
            normalization: normalization,
            inputPaths: measuredPaths.map(\.trace),
            totalLength: totalLength,
            sequenceOrder: selection.sequenceOrder,
            selectedSegments: selection.segments,
            resultPaths: resultPaths,
            approximations: [
                LottieSourceTrimApproximation(
                    name: "lottieWebDefaultCurveSegments",
                    value: Double(Self.defaultCurveSegments),
                    evidence: "lottie-web utils/common.js defaultCurveSegments = 150"
                ),
                LottieSourceTrimApproximation(
                    name: "lengthParameterization",
                    value: Double(Self.defaultCurveSegments),
                    evidence: "Cubic length is measured by lottie-web-style fixed polyline samples before mapping trim length to Bezier t."
                ),
                LottieSourceTrimApproximation(
                    name: "trimmedCubicRoundingDecimals",
                    value: 3,
                    evidence: "lottie-web bez.getNewSegment rounds generated control points to 0.001."
                ),
            ]
        )
        return LottieEvaluationResult(value: trace, diagnostics: diagnostics, trace: nil)
    }

    fileprivate static let defaultCurveSegments = 150
    fileprivate static let epsilon = 0.0000001

    private static func normalize(start: Double, end: Double, offset: Double) -> LottieSourceTrimNormalizationTrace {
        let rawStart = start / 100
        let rawEnd = end / 100
        var offsetTurns = offset.truncatingRemainder(dividingBy: 360) / 360
        if offsetTurns < 0 {
            offsetTurns += 1
        }
        var normalizedStart = shiftedClampedFraction(rawStart, offset: offsetTurns)
        var normalizedEnd = shiftedClampedFraction(rawEnd, offset: offsetTurns)
        var swapped = false
        if normalizedStart > normalizedEnd {
            swap(&normalizedStart, &normalizedEnd)
            swapped = true
        }
        return LottieSourceTrimNormalizationTrace(
            authoredStartPercent: start,
            authoredEndPercent: end,
            authoredOffsetDegrees: offset,
            rawStartFraction: rawStart,
            rawEndFraction: rawEnd,
            offsetTurns: offsetTurns,
            normalizedStartFraction: normalizedStart,
            normalizedEndFraction: normalizedEnd,
            swappedStartEnd: swapped,
            isEmpty: normalizedStart == normalizedEnd,
            isFull: (normalizedEnd == 1 && normalizedStart == 0) || (normalizedEnd == 0 && normalizedStart == 1)
        )
    }

    private static func shiftedClampedFraction(_ value: Double, offset: Double) -> Double {
        if value > 1 {
            return 1 + offset
        }
        if value < 0 {
            return offset
        }
        return value + offset
    }

    private func resolvedMode(for trim: LottieRenderTrim, diagnostics: inout [ValidationError]) -> LottieSourceTrimMode {
        switch trim.multiple {
        case 2:
            return .sequential
        case nil, 1:
            return .parallel
        default:
            diagnostics.append(ValidationError(
                ruleID: "lottie.evaluation.trim.mode",
                reason: "Trim path mode `m` must be 1 or 2 before source trim evaluation.",
                at: trim.source.jsonPath.appending(.key("m")),
                severity: .warning,
                phase: .semantic,
                classification: .gap,
                evidence: trim.source.sourcePath
            ))
            return .parallel
        }
    }

    private func selectedSegments(
        mode: LottieSourceTrimMode,
        normalization: LottieSourceTrimNormalizationTrace,
        paths: [MeasuredPath],
        totalLength: Double
    ) -> (segments: [LottieSourceTrimSelectedSegmentTrace], sequenceOrder: [String]) {
        guard !normalization.isEmpty else {
            return ([], paths.map(\.source.sourcePath))
        }
        switch mode {
        case .parallel:
            return parallelSegments(normalization: normalization, paths: paths)
        case .sequential:
            return sequentialSegments(normalization: normalization, paths: paths, totalLength: totalLength)
        }
    }

    private func parallelSegments(
        normalization: LottieSourceTrimNormalizationTrace,
        paths: [MeasuredPath]
    ) -> (segments: [LottieSourceTrimSelectedSegmentTrace], sequenceOrder: [String]) {
        var selected: [LottieSourceTrimSelectedSegmentTrace] = []
        for path in paths {
            for range in lengthRanges(
                startFraction: normalization.normalizedStartFraction,
                endFraction: normalization.normalizedEndFraction,
                length: path.totalLength
            ) {
                guard range.end > range.start else { continue }
                selected.append(selectedSegment(
                    path: path,
                    sequenceOrdinal: path.pathIndex,
                    range: range,
                    globalStartLength: nil,
                    globalEndLength: nil
                ))
            }
        }
        return (selected, paths.map(\.source.sourcePath))
    }

    private func sequentialSegments(
        normalization: LottieSourceTrimNormalizationTrace,
        paths: [MeasuredPath],
        totalLength: Double
    ) -> (segments: [LottieSourceTrimSelectedSegmentTrace], sequenceOrder: [String]) {
        var selected: [LottieSourceTrimSelectedSegmentTrace] = []
        var addedLength = 0.0
        let orderedPaths = Array(paths.reversed())
        for (ordinal, path) in orderedPaths.enumerated() {
            let edges = shapeEdges(
                startFraction: normalization.normalizedStartFraction,
                endFraction: normalization.normalizedEndFraction,
                shapeLength: path.totalLength,
                addedLength: addedLength,
                totalLength: totalLength
            )
            for edge in edges {
                for range in lengthRanges(startFraction: edge.start, endFraction: edge.end, length: path.totalLength) {
                    guard range.end > range.start else { continue }
                    selected.append(selectedSegment(
                        path: path,
                        sequenceOrdinal: ordinal,
                        range: range,
                        globalStartLength: addedLength + range.start,
                        globalEndLength: addedLength + range.end
                    ))
                }
            }
            addedLength += path.totalLength
        }
        return (selected, orderedPaths.map(\.source.sourcePath))
    }

    private func shapeEdges(
        startFraction: Double,
        endFraction: Double,
        shapeLength: Double,
        addedLength: Double,
        totalLength: Double
    ) -> [(start: Double, end: Double)] {
        guard shapeLength > 0, totalLength > 0 else { return [(0, 0)] }
        let segments = fractionRanges(startFraction: startFraction, endFraction: endFraction)
        var shapeSegments: [(start: Double, end: Double)] = []
        for segment in segments {
            if !(segment.end * totalLength < addedLength || segment.start * totalLength > addedLength + shapeLength) {
                let shapeStart: Double = if segment.start * totalLength <= addedLength {
                    0
                } else {
                    (segment.start * totalLength - addedLength) / shapeLength
                }
                let shapeEnd: Double = if segment.end * totalLength >= addedLength + shapeLength {
                    1
                } else {
                    (segment.end * totalLength - addedLength) / shapeLength
                }
                shapeSegments.append((shapeStart, shapeEnd))
            }
        }
        return shapeSegments.isEmpty ? [(0, 0)] : shapeSegments
    }

    private func lengthRanges(startFraction: Double, endFraction: Double, length: Double) -> [(start: Double, end: Double)] {
        fractionRanges(startFraction: startFraction, endFraction: endFraction).map {
            (max(0, min(length, $0.start * length)), max(0, min(length, $0.end * length)))
        }
    }

    private func fractionRanges(startFraction: Double, endFraction: Double) -> [(start: Double, end: Double)] {
        if endFraction <= 1 {
            return [(startFraction, endFraction)]
        }
        if startFraction >= 1 {
            return [(startFraction - 1, endFraction - 1)]
        }
        return [(startFraction, 1), (0, endFraction - 1)]
    }

    private func selectedSegment(
        path: MeasuredPath,
        sequenceOrdinal: Int,
        range: (start: Double, end: Double),
        globalStartLength: Double?,
        globalEndLength: Double?
    ) -> LottieSourceTrimSelectedSegmentTrace {
        let cubicSegments = path.cubicSegments(in: range)
        return LottieSourceTrimSelectedSegmentTrace(
            pathIndex: path.pathIndex,
            sourcePath: path.source.sourcePath,
            jsonPath: path.source.jsonPath,
            sequenceOrdinal: sequenceOrdinal,
            startLength: range.start,
            endLength: range.end,
            startFraction: path.totalLength == 0 ? 0 : range.start / path.totalLength,
            endFraction: path.totalLength == 0 ? 0 : range.end / path.totalLength,
            globalStartLength: globalStartLength,
            globalEndLength: globalEndLength,
            cubicSegments: cubicSegments
        )
    }

    private func resultPaths(
        for selectedSegments: [LottieSourceTrimSelectedSegmentTrace],
        in measuredPaths: [MeasuredPath],
        emptyPaths: Bool
    ) -> [LottieSourceTrimResultPathTrace] {
        if emptyPaths {
            return measuredPaths.map { path in
                LottieSourceTrimResultPathTrace(
                    pathIndex: path.pathIndex,
                    sourcePath: path.source.sourcePath,
                    jsonPath: path.source.jsonPath,
                    selectedSegmentIndex: nil,
                    isClosed: false,
                    vertices: [],
                    inTangents: [],
                    outTangents: []
                )
            }
        }
        var activeSegments = selectedSegments
        if LottieFaultInjector.isActive(.droppedTrimSegment), !activeSegments.isEmpty {
            activeSegments.removeLast()
        }
        return activeSegments.enumerated().compactMap { offset, selected -> LottieSourceTrimResultPathTrace? in
            guard let path = measuredPaths.first(where: { $0.pathIndex == selected.pathIndex }) else { return nil }
            let bezier = path.resultPath(for: selected)
            return LottieSourceTrimResultPathTrace(
                pathIndex: path.pathIndex,
                sourcePath: path.source.sourcePath,
                jsonPath: path.source.jsonPath,
                selectedSegmentIndex: offset,
                isClosed: bezier.isClosed,
                vertices: bezier.vertices,
                inTangents: bezier.inTangents,
                outTangents: bezier.outTangents
            )
        }
    }
}

private struct MeasuredPath: Equatable {
    let pathIndex: Int
    let source: LottieSourceGeometryTrace
    let segments: [MeasuredCubicSegment]
    let totalLength: Double

    init(pathIndex: Int, source: LottieSourceGeometryTrace) {
        self.pathIndex = pathIndex
        self.source = source
        segments = Self.segments(from: source)
        totalLength = segments.reduce(0) { $0 + $1.length }
    }

    var trace: LottieSourceTrimPathLengthTrace {
        LottieSourceTrimPathLengthTrace(
            pathIndex: pathIndex,
            sourcePath: source.sourcePath,
            jsonPath: source.jsonPath,
            primitive: source.primitive,
            isClosed: source.isClosed,
            totalLength: totalLength,
            cubicSegmentLengths: segments.map(\.length)
        )
    }

    func cubicSegments(in range: (start: Double, end: Double)) -> [LottieSourceTrimCubicSegmentTrace] {
        var result: [LottieSourceTrimCubicSegmentTrace] = []
        var added = 0.0
        for segment in segments {
            let segmentStart = added
            let segmentEnd = added + segment.length
            let selectedStart = max(range.start, segmentStart)
            let selectedEnd = min(range.end, segmentEnd)
            if selectedEnd > selectedStart, segment.length > 0 {
                result.append(LottieSourceTrimCubicSegmentTrace(
                    cubicSegmentIndex: segment.index,
                    startLength: selectedStart - segmentStart,
                    endLength: selectedEnd - segmentStart,
                    startPercent: (selectedStart - segmentStart) / segment.length,
                    endPercent: (selectedEnd - segmentStart) / segment.length
                ))
            }
            added = segmentEnd
        }
        return result
    }

    func resultPath(for selected: LottieSourceTrimSelectedSegmentTrace) -> LottieBezier {
        let selectedCubicSegments = selected.cubicSegments.compactMap { trace -> CubicSegment? in
            guard let segment = segments.first(where: { $0.index == trace.cubicSegmentIndex }) else { return nil }
            return segment.subsegment(startPercent: trace.startPercent, endPercent: trace.endPercent)
        }
        guard !selectedCubicSegments.isEmpty else {
            return LottieBezier(isClosed: false, vertices: [], inTangents: [], outTangents: [])
        }
        if selected.startLength <= LottieSourceTrimEvaluator.epsilon,
           abs(selected.endLength - totalLength) <= LottieSourceTrimEvaluator.epsilon
        {
            return source.bezier
        }
        return LottieBezier(segments: selectedCubicSegments)
    }

    private static func segments(from source: LottieSourceGeometryTrace) -> [MeasuredCubicSegment] {
        let vertices = source.vertices
        guard !vertices.isEmpty else { return [] }
        let segmentCount = source.isClosed ? vertices.count : max(vertices.count - 1, 0)
        return (0 ..< segmentCount).map { index in
            let from = index
            let to = index == vertices.count - 1 ? 0 : index + 1
            let start = vertices[from]
            let end = vertices[to]
            let control1 = source.absoluteOutTangents.indices.contains(from) ? source.absoluteOutTangents[from] : start
            let control2 = source.absoluteInTangents.indices.contains(to) ? source.absoluteInTangents[to] : end
            return MeasuredCubicSegment(
                index: index,
                cubic: CubicSegment(start: start, control1: control1, control2: control2, end: end)
            )
        }
    }
}

private struct MeasuredCubicSegment: Equatable {
    let index: Int
    let cubic: CubicSegment
    let samples: [LengthSample]
    let length: Double

    init(index: Int, cubic: CubicSegment) {
        self.index = index
        self.cubic = cubic
        samples = cubic.lengthSamples(count: LottieSourceTrimEvaluator.defaultCurveSegments)
        length = samples.last?.length ?? 0
    }

    func subsegment(startPercent: Double, endPercent: Double) -> CubicSegment {
        let t0 = parameter(forLengthPercent: startPercent)
        let t1 = parameter(forLengthPercent: endPercent)
        return cubic.subsegment(from: t0, to: t1).rounded(toPlaces: 3)
    }

    private func parameter(forLengthPercent percent: Double) -> Double {
        guard let last = samples.last, last.length > 0 else { return max(0, min(1, percent)) }
        let targetLength = max(0, min(1, percent)) * last.length
        if targetLength <= 0 { return 0 }
        if targetLength >= last.length { return 1 }
        for index in 0 ..< max(samples.count - 1, 0) {
            let current = samples[index]
            let next = samples[index + 1]
            if current.length <= targetLength, next.length >= targetLength {
                let span = next.length - current.length
                let progress = span == 0 ? 0 : (targetLength - current.length) / span
                return current.percent + (next.percent - current.percent) * progress
            }
        }
        return 1
    }
}

private struct LengthSample: Equatable {
    let percent: Double
    let length: Double
}

private struct CubicSegment: Equatable {
    var start: [Double]
    var control1: [Double]
    var control2: [Double]
    var end: [Double]

    func lengthSamples(count: Int) -> [LengthSample] {
        guard count > 1 else { return [LengthSample(percent: 0, length: 0)] }
        var result: [LengthSample] = []
        var cumulative = 0.0
        var previous: [Double]?
        for offset in 0 ..< count {
            let percent = Double(offset) / Double(count - 1)
            let point = point(at: percent)
            if let previous {
                cumulative += distance(previous, point)
            }
            result.append(LengthSample(percent: percent, length: cumulative))
            previous = point
        }
        return result
    }

    func subsegment(from t0: Double, to t1: Double) -> CubicSegment {
        CubicSegment(
            start: blossom(t0, t0, t0),
            control1: blossom(t0, t0, t1),
            control2: blossom(t0, t1, t1),
            end: blossom(t1, t1, t1)
        )
    }

    func rounded(toPlaces places: Int) -> CubicSegment {
        CubicSegment(
            start: start.rounded(toPlaces: places),
            control1: control1.rounded(toPlaces: places),
            control2: control2.rounded(toPlaces: places),
            end: end.rounded(toPlaces: places)
        )
    }

    private func point(at t: Double) -> [Double] {
        let mt = 1 - t
        return [
            mt * mt * mt * start.component(0)
                + 3 * mt * mt * t * control1.component(0)
                + 3 * mt * t * t * control2.component(0)
                + t * t * t * end.component(0),
            mt * mt * mt * start.component(1)
                + 3 * mt * mt * t * control1.component(1)
                + 3 * mt * t * t * control2.component(1)
                + t * t * t * end.component(1),
        ]
    }

    private func blossom(_ a: Double, _ b: Double, _ c: Double) -> [Double] {
        let ua = 1 - a
        let ub = 1 - b
        let uc = 1 - c
        return [
            ua * ub * uc * start.component(0)
                + (a * ub * uc + ua * b * uc + ua * ub * c) * control1.component(0)
                + (a * b * uc + a * ub * c + ua * b * c) * control2.component(0)
                + a * b * c * end.component(0),
            ua * ub * uc * start.component(1)
                + (a * ub * uc + ua * b * uc + ua * ub * c) * control1.component(1)
                + (a * b * uc + a * ub * c + ua * b * c) * control2.component(1)
                + a * b * c * end.component(1),
        ]
    }
}

private extension LottieBezier {
    init(segments: [CubicSegment]) {
        var vertices: [[Double]] = []
        var inTangents: [[Double]] = []
        var outTangents: [[Double]] = []
        for segment in segments {
            if vertices.isEmpty {
                vertices.append(segment.start)
                inTangents.append([0, 0])
                outTangents.append(segment.control1.relative(to: segment.start))
            } else {
                outTangents[vertices.count - 1] = segment.control1.relative(to: vertices[vertices.count - 1])
            }
            vertices.append(segment.end)
            inTangents.append(segment.control2.relative(to: segment.end))
            outTangents.append([0, 0])
        }
        self.init(isClosed: false, vertices: vertices, inTangents: inTangents, outTangents: outTangents)
    }
}

private extension [Double] {
    func component(_ index: Int) -> Double {
        if indices.contains(index) { return self[index] }
        return last ?? 0
    }

    func rounded(toPlaces places: Int) -> [Double] {
        let scale = pow(10, Double(places))
        return map { ($0 * scale).rounded() / scale }
    }

    func relative(to origin: [Double]) -> [Double] {
        [
            component(0) - origin.component(0),
            component(1) - origin.component(1),
        ]
    }
}

private func distance(_ lhs: [Double], _ rhs: [Double]) -> Double {
    let dx = lhs.component(0) - rhs.component(0)
    let dy = lhs.component(1) - rhs.component(1)
    return sqrt(dx * dx + dy * dy)
}
