//
//  LottieSourceIntentRoundTripGate.swift
//  PureLottie
//

import Foundation
import LottieModel

/// One selected Lottie frame to prove in the source-intent round-trip gate.
public struct LottieSourceIntentRoundTripSelection: Sendable, Equatable {
    public var frame: Double
    public var rationale: String

    public init(frame: Double, rationale: String) {
        self.frame = frame
        self.rationale = rationale
    }
}

/// Deterministic evidence that selected RenderIR transform and timing facts
/// decompile back to the same source-intent facts before any rendering pass.
public struct LottieSourceIntentRoundTripReport: Codable, Sendable, Equatable, Validatable {
    public var schema: LottieSourceIntentRoundTripReportSchema
    public var source: LottieDecompiledSourceIntentSource
    public var frameCount: Int
    public var findingCount: Int
    public var lossCount: Int
    public var frames: [LottieSourceIntentRoundTripFrame]

    public init(
        schema: LottieSourceIntentRoundTripReportSchema = LottieSourceIntentRoundTripReportSchema(),
        source: LottieDecompiledSourceIntentSource,
        frames: [LottieSourceIntentRoundTripFrame]
    ) {
        self.schema = schema
        self.source = source
        self.frames = frames
        frameCount = frames.count
        findingCount = frames.flatMap(\.findings).count + frames.flatMap(\.layers).flatMap(\.findings).count
        lossCount = frames.flatMap(\.losses).count
    }
}

/// Schema marker for persisted source-intent round-trip evidence documents.
public struct LottieSourceIntentRoundTripReportSchema: Codable, Sendable, Equatable, Validatable {
    public var name: String
    public var version: Int

    public init(name: String = "purelottie.source-intent-round-trip-report", version: Int = 1) {
        self.name = name
        self.version = version
    }
}

/// Round-trip evidence for one selected source frame.
public struct LottieSourceIntentRoundTripFrame: Codable, Sendable, Equatable, Validatable {
    public var sourceFrame: Double
    public var rationale: String
    public var localTimeSeconds: Double?
    public var layerCount: Int
    public var lossCount: Int
    public var findingCount: Int
    public var layers: [LottieSourceIntentRoundTripLayer]
    public var losses: [LottieDecompiledSourceIntentLoss]
    public var findings: [LottieSourceIntentRoundTripFinding]

    public init(
        sourceFrame: Double,
        rationale: String,
        localTimeSeconds: Double?,
        layers: [LottieSourceIntentRoundTripLayer],
        losses: [LottieDecompiledSourceIntentLoss] = [],
        findings: [LottieSourceIntentRoundTripFinding] = []
    ) {
        self.sourceFrame = sourceFrame
        self.rationale = rationale
        self.localTimeSeconds = localTimeSeconds
        self.layers = layers
        self.losses = losses
        self.findings = findings
        layerCount = layers.count
        lossCount = losses.count
        findingCount = findings.count + layers.flatMap(\.findings).count
    }
}

/// Measured transform and timing facts for one layer before renderer handoff.
public struct LottieSourceIntentRoundTripLayer: Codable, Sendable, Equatable, Validatable {
    public var id: String
    public var name: String?
    public var sourcePath: String
    public var jsonPath: String
    public var timingMode: String?
    public var localFrame: Double
    public var decompiledLocalFrame: Double?
    public var opacity: Double
    public var decompiledOpacity: Double?
    public var position: [Double]
    public var decompiledPosition: [Double]
    public var scale: [Double]
    public var decompiledScale: [Double]
    public var rotationZDegrees: Double
    public var decompiledRotationZDegrees: Double?
    public var matrix: [Double]
    public var decompiledMatrix: [Double]
    public var matrixTranslation: [Double]
    public var decompiledMatrixTranslation: [Double]
    public var geometryCount: Int
    public var decompiledGeometryCount: Int
    public var styleCount: Int
    public var decompiledStyleCount: Int
    public var trimTraceCount: Int
    public var decompiledTrimTraceCount: Int
    public var maskCount: Int
    public var decompiledMaskCount: Int
    public var hasMatte: Bool
    public var decompiledHasMatte: Bool
    public var findings: [LottieSourceIntentRoundTripFinding]

    public init(
        id: String,
        name: String?,
        sourcePath: String,
        jsonPath: String,
        timingMode: String?,
        localFrame: Double,
        decompiledLocalFrame: Double?,
        opacity: Double,
        decompiledOpacity: Double?,
        position: [Double],
        decompiledPosition: [Double],
        scale: [Double],
        decompiledScale: [Double],
        rotationZDegrees: Double,
        decompiledRotationZDegrees: Double?,
        matrix: [Double],
        decompiledMatrix: [Double],
        matrixTranslation: [Double],
        decompiledMatrixTranslation: [Double],
        geometryCount: Int,
        decompiledGeometryCount: Int,
        styleCount: Int,
        decompiledStyleCount: Int,
        trimTraceCount: Int,
        decompiledTrimTraceCount: Int,
        maskCount: Int,
        decompiledMaskCount: Int,
        hasMatte: Bool,
        decompiledHasMatte: Bool,
        findings: [LottieSourceIntentRoundTripFinding] = []
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.timingMode = timingMode
        self.localFrame = localFrame
        self.decompiledLocalFrame = decompiledLocalFrame
        self.opacity = opacity
        self.decompiledOpacity = decompiledOpacity
        self.position = position
        self.decompiledPosition = decompiledPosition
        self.scale = scale
        self.decompiledScale = decompiledScale
        self.rotationZDegrees = rotationZDegrees
        self.decompiledRotationZDegrees = decompiledRotationZDegrees
        self.matrix = matrix
        self.decompiledMatrix = decompiledMatrix
        self.matrixTranslation = matrixTranslation
        self.decompiledMatrixTranslation = decompiledMatrixTranslation
        self.geometryCount = geometryCount
        self.decompiledGeometryCount = decompiledGeometryCount
        self.styleCount = styleCount
        self.decompiledStyleCount = decompiledStyleCount
        self.trimTraceCount = trimTraceCount
        self.decompiledTrimTraceCount = decompiledTrimTraceCount
        self.maskCount = maskCount
        self.decompiledMaskCount = decompiledMaskCount
        self.hasMatte = hasMatte
        self.decompiledHasMatte = decompiledHasMatte
        self.findings = findings
    }
}

/// A mismatch found while comparing RenderIR facts to decompiled source intent.
public struct LottieSourceIntentRoundTripFinding: Codable, Sendable, Equatable, Validatable {
    public var ruleID: String
    public var sourcePath: String
    public var jsonPath: String
    public var property: String
    public var expected: String
    public var actual: String
    public var reason: String

    public init(
        ruleID: String,
        sourcePath: String,
        jsonPath: String,
        property: String,
        expected: String,
        actual: String,
        reason: String
    ) {
        self.ruleID = ruleID
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.property = property
        self.expected = expected
        self.actual = actual
        self.reason = reason
    }
}

/// Builds reportable proof that Lottie transform and timing facts survive the
/// RenderIR -> source-intent decompiler edge exactly within a numeric tolerance.
public struct LottieSourceIntentTransformTimingRoundTripGate: Sendable {
    public var tolerance: Double

    public init(tolerance: Double = 0.000001) {
        self.tolerance = tolerance
    }

    public func report(
        animation: LottieAnimation,
        source: LottieDecompiledSourceIntentSource,
        selectedFrames: [LottieSourceIntentRoundTripSelection]
    ) -> LottieSourceIntentRoundTripReport {
        let builder = LottieRenderIRBuilder(animation: animation)
        let renderFrames = selectedFrames.map { builder.frame(at: $0.frame) }
        let decompiled = LottieSourceIntentDecompiler().decompile(frames: renderFrames, source: source)
        let frames = zip(selectedFrames.indices, selectedFrames).map { index, selection in
            frameReport(
                renderFrame: renderFrames[index],
                decompiledFrame: decompiled.frames[index],
                selection: selection,
                frameOffset: index
            )
        }
        return LottieSourceIntentRoundTripReport(source: decompiled.source, frames: frames)
    }

    private func frameReport(
        renderFrame: LottieRenderFrame,
        decompiledFrame: LottieDecompiledSourceIntentFrame,
        selection: LottieSourceIntentRoundTripSelection,
        frameOffset: Int
    ) -> LottieSourceIntentRoundTripFrame {
        var frameFindings: [LottieSourceIntentRoundTripFinding] = []
        let layers = renderFrame.nodes.map { node -> LottieSourceIntentRoundTripLayer in
            guard let layer = decompiledFrame.visibleLayers.first(where: { $0.id == node.id.description }) else {
                frameFindings.append(finding(
                    ruleID: "lottie.round-trip.layer.missing",
                    node: node,
                    property: "layer",
                    expected: node.id.description,
                    actual: "missing",
                    reason: "RenderIR layer did not survive decompilation."
                ))
                return missingLayerReport(for: node, timingMode: timingMode(for: node, in: renderFrame))
            }
            return layerReport(node: node, decompiledLayer: layer, timingMode: timingMode(for: node, in: renderFrame))
        }

        return LottieSourceIntentRoundTripFrame(
            sourceFrame: selection.frame,
            rationale: selection.rationale,
            localTimeSeconds: decompiledFrame.localTimeSeconds,
            layers: layers,
            losses: decompiledFrame.losses + featureLosses(renderFrame, frameOffset: frameOffset),
            findings: frameFindings
        )
    }

    private func layerReport(
        node: LottieRenderNode,
        decompiledLayer layer: LottieSourceIntentLayer,
        timingMode: String?
    ) -> LottieSourceIntentRoundTripLayer {
        let findings = layerFindings(node: node, layer: layer)
        return LottieSourceIntentRoundTripLayer(
            id: node.id.description,
            name: node.layerName,
            sourcePath: node.source.sourcePath,
            jsonPath: node.source.jsonPath.description,
            timingMode: timingMode,
            localFrame: node.localFrame,
            decompiledLocalFrame: layer.localFrame,
            opacity: node.opacity,
            decompiledOpacity: layer.opacity,
            position: node.transform.local.position,
            decompiledPosition: layer.transform.position,
            scale: node.transform.local.scale,
            decompiledScale: layer.transform.scale,
            rotationZDegrees: node.transform.local.rotationZDegrees,
            decompiledRotationZDegrees: layer.transform.rotationZDegrees,
            matrix: node.transform.local.matrix.values,
            decompiledMatrix: layer.transform.matrix.values,
            matrixTranslation: translation(from: node.transform.local.matrix.values),
            decompiledMatrixTranslation: translation(from: layer.transform.matrix.values),
            geometryCount: geometryFragments(in: node).count,
            decompiledGeometryCount: layer.geometry.count,
            styleCount: shapeDraws(in: node).count,
            decompiledStyleCount: layer.styles.count,
            trimTraceCount: trimTraces(in: node).count,
            decompiledTrimTraceCount: layer.trimTraces?.count ?? 0,
            maskCount: node.masks.count,
            decompiledMaskCount: layer.masks.count,
            hasMatte: node.matte != nil,
            decompiledHasMatte: layer.matte != nil,
            findings: findings
        )
    }

    private func missingLayerReport(
        for node: LottieRenderNode,
        timingMode: String?
    ) -> LottieSourceIntentRoundTripLayer {
        LottieSourceIntentRoundTripLayer(
            id: node.id.description,
            name: node.layerName,
            sourcePath: node.source.sourcePath,
            jsonPath: node.source.jsonPath.description,
            timingMode: timingMode,
            localFrame: node.localFrame,
            decompiledLocalFrame: nil,
            opacity: node.opacity,
            decompiledOpacity: nil,
            position: node.transform.local.position,
            decompiledPosition: [],
            scale: node.transform.local.scale,
            decompiledScale: [],
            rotationZDegrees: node.transform.local.rotationZDegrees,
            decompiledRotationZDegrees: nil,
            matrix: node.transform.local.matrix.values,
            decompiledMatrix: [],
            matrixTranslation: translation(from: node.transform.local.matrix.values),
            decompiledMatrixTranslation: [],
            geometryCount: geometryFragments(in: node).count,
            decompiledGeometryCount: 0,
            styleCount: shapeDraws(in: node).count,
            decompiledStyleCount: 0,
            trimTraceCount: trimTraces(in: node).count,
            decompiledTrimTraceCount: 0,
            maskCount: node.masks.count,
            decompiledMaskCount: 0,
            hasMatte: node.matte != nil,
            decompiledHasMatte: false,
            findings: []
        )
    }

    private func layerFindings(
        node: LottieRenderNode,
        layer: LottieSourceIntentLayer
    ) -> [LottieSourceIntentRoundTripFinding] {
        var findings: [LottieSourceIntentRoundTripFinding] = []
        compare(node.localFrame, layer.localFrame, property: "localFrame", node: node, findings: &findings)
        compare(node.opacity, layer.opacity, property: "opacity", node: node, findings: &findings)
        compare(node.transform.local.position, layer.transform.position, property: "position", node: node, findings: &findings)
        compare(node.transform.local.scale, layer.transform.scale, property: "scale", node: node, findings: &findings)
        compare(
            node.transform.local.rotationZDegrees,
            layer.transform.rotationZDegrees,
            property: "rotationZDegrees",
            node: node,
            findings: &findings
        )
        compare(
            node.transform.local.matrix.values,
            layer.transform.matrix.values,
            property: "matrix",
            node: node,
            findings: &findings
        )
        compare(
            translation(from: node.transform.local.matrix.values),
            translation(from: layer.transform.matrix.values),
            property: "matrixTranslation",
            node: node,
            findings: &findings
        )
        compareFeatureFacts(node: node, layer: layer, findings: &findings)
        return findings
    }

    private func compareFeatureFacts(
        node: LottieRenderNode,
        layer: LottieSourceIntentLayer,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        compareGeometryFacts(node: node, layer: layer, findings: &findings)
        compareStyleFacts(node: node, layer: layer, findings: &findings)
        compareTrimTraceFacts(node: node, layer: layer, findings: &findings)
        compareMaskFacts(node: node, layer: layer, findings: &findings)
        compareMatteFacts(node: node, layer: layer, findings: &findings)
    }

    private func compareGeometryFacts(
        node: LottieRenderNode,
        layer: LottieSourceIntentLayer,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        let fragments = geometryFragments(in: node)
        compare(fragments.count, layer.geometry.count, property: "geometry.count", node: node, findings: &findings)
        for index in 0 ..< min(fragments.count, layer.geometry.count) {
            let fragment = fragments[index]
            let geometry = layer.geometry[index]
            compare(fragment.source.sourcePath, geometry.provenance.sourcePath, property: "geometry[\(index)].sourcePath", node: node, findings: &findings)
            compare(fragment.source.jsonPath.description, geometry.provenance.jsonPath, property: "geometry[\(index)].jsonPath", node: node, findings: &findings)
            compareGeometryPayload(fragment.geometry, geometry, index: index, node: node, findings: &findings)
            compare(
                fragment.transformStack.count,
                geometry.transformStack.count,
                property: "geometry[\(index)].transformStack.count",
                node: node,
                findings: &findings
            )
            compare(
                fragment.modifiers.count,
                geometry.modifiers.count,
                property: "geometry[\(index)].modifiers.count",
                node: node,
                findings: &findings
            )
            compareModifiers(fragment.modifiers, geometry.modifiers, geometryIndex: index, node: node, findings: &findings)
        }
    }

    private func compareGeometryPayload(
        _ expected: LottieRenderGeometry,
        _ actual: LottieSourceIntentGeometry,
        index: Int,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        switch expected {
        case let .path(path):
            compare("path", actual.kind.rawValue, property: "geometry[\(index)].kind", node: node, findings: &findings)
            compare("sh", actual.primitive, property: "geometry[\(index)].primitive", node: node, findings: &findings)
            comparePath(path, actual.path, property: "geometry[\(index)].path", node: node, findings: &findings)
        case let .rectangle(center, size, roundness):
            compare("rectangle", actual.kind.rawValue, property: "geometry[\(index)].kind", node: node, findings: &findings)
            compare("rc", actual.primitive, property: "geometry[\(index)].primitive", node: node, findings: &findings)
            compare(center, actual.parameters["center"] ?? [], property: "geometry[\(index)].parameters.center", node: node, findings: &findings)
            compare(size, actual.parameters["size"] ?? [], property: "geometry[\(index)].parameters.size", node: node, findings: &findings)
            compare([roundness], actual.parameters["roundness"] ?? [], property: "geometry[\(index)].parameters.roundness", node: node, findings: &findings)
        case let .ellipse(center, size):
            compare("ellipse", actual.kind.rawValue, property: "geometry[\(index)].kind", node: node, findings: &findings)
            compare("el", actual.primitive, property: "geometry[\(index)].primitive", node: node, findings: &findings)
            compare(center, actual.parameters["center"] ?? [], property: "geometry[\(index)].parameters.center", node: node, findings: &findings)
            compare(size, actual.parameters["size"] ?? [], property: "geometry[\(index)].parameters.size", node: node, findings: &findings)
        }
    }

    private func compareModifiers(
        _ expected: [LottieRenderShapeModifier],
        _ actual: [LottieSourceIntentModifier],
        geometryIndex: Int,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        for index in 0 ..< min(expected.count, actual.count) {
            switch expected[index] {
            case let .trim(trim):
                compare("trim", actual[index].kind.rawValue, property: "geometry[\(geometryIndex)].modifiers[\(index)].kind", node: node, findings: &findings)
                compare(trim.start, actual[index].trim?.start, property: "geometry[\(geometryIndex)].modifiers[\(index)].trim.start", node: node, findings: &findings)
                compare(trim.end, actual[index].trim?.end, property: "geometry[\(geometryIndex)].modifiers[\(index)].trim.end", node: node, findings: &findings)
                compare(trim.offset, actual[index].trim?.offset, property: "geometry[\(geometryIndex)].modifiers[\(index)].trim.offset", node: node, findings: &findings)
                compare(trim.multiple, actual[index].trim?.multiple, property: "geometry[\(geometryIndex)].modifiers[\(index)].trim.multiple", node: node, findings: &findings)
                compare(
                    trim.isAnimated,
                    actual[index].trim?.isAnimated,
                    property: "geometry[\(geometryIndex)].modifiers[\(index)].trim.isAnimated",
                    node: node,
                    findings: &findings
                )
            }
        }
    }

    private func compareStyleFacts(
        node: LottieRenderNode,
        layer: LottieSourceIntentLayer,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        let draws = shapeDraws(in: node)
        compare(draws.count, layer.styles.count, property: "styles.count", node: node, findings: &findings)
        for index in 0 ..< min(draws.count, layer.styles.count) {
            let draw = draws[index]
            let style = layer.styles[index]
            compare(draw.source.sourcePath, style.provenance.sourcePath, property: "styles[\(index)].sourcePath", node: node, findings: &findings)
            compare(draw.source.jsonPath.description, style.provenance.jsonPath, property: "styles[\(index)].jsonPath", node: node, findings: &findings)
            switch draw.style {
            case let .fill(fill):
                compare("fill", style.kind.rawValue, property: "styles[\(index)].kind", node: node, findings: &findings)
                compare(fill.color, style.color ?? [], property: "styles[\(index)].color", node: node, findings: &findings)
                compare(fill.opacity, style.opacity, property: "styles[\(index)].opacity", node: node, findings: &findings)
                compare(fill.fillRule, style.fillRule, property: "styles[\(index)].fillRule", node: node, findings: &findings)
                compare(fill.blendMode, style.blendMode, property: "styles[\(index)].blendMode", node: node, findings: &findings)
            case let .stroke(stroke):
                compare("stroke", style.kind.rawValue, property: "styles[\(index)].kind", node: node, findings: &findings)
                compare(stroke.color, style.color ?? [], property: "styles[\(index)].color", node: node, findings: &findings)
                compare(stroke.opacity, style.opacity, property: "styles[\(index)].opacity", node: node, findings: &findings)
                compare(stroke.width, style.width, property: "styles[\(index)].width", node: node, findings: &findings)
                compare(stroke.lineCap, style.lineCap, property: "styles[\(index)].lineCap", node: node, findings: &findings)
                compare(stroke.lineJoin, style.lineJoin, property: "styles[\(index)].lineJoin", node: node, findings: &findings)
                compare(stroke.miterLimit, style.miterLimit, property: "styles[\(index)].miterLimit", node: node, findings: &findings)
                compare(stroke.blendMode, style.blendMode, property: "styles[\(index)].blendMode", node: node, findings: &findings)
                compareDashes(stroke.dashPattern, style.dashPattern, styleIndex: index, node: node, findings: &findings)
            }
        }
    }

    private func compareDashes(
        _ expected: [LottieRenderStrokeDash],
        _ actual: [LottieSourceIntentStrokeDash],
        styleIndex: Int,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        compare(expected.count, actual.count, property: "styles[\(styleIndex)].dashPattern.count", node: node, findings: &findings)
        for index in 0 ..< min(expected.count, actual.count) {
            compare(expected[index].name, actual[index].name, property: "styles[\(styleIndex)].dashPattern[\(index)].name", node: node, findings: &findings)
            compare(expected[index].type, actual[index].type, property: "styles[\(styleIndex)].dashPattern[\(index)].type", node: node, findings: &findings)
            compare(expected[index].value, actual[index].value, property: "styles[\(styleIndex)].dashPattern[\(index)].value", node: node, findings: &findings)
            compare(expected[index].isAnimated, actual[index].isAnimated, property: "styles[\(styleIndex)].dashPattern[\(index)].isAnimated", node: node, findings: &findings)
        }
    }

    private func compareTrimTraceFacts(
        node: LottieRenderNode,
        layer: LottieSourceIntentLayer,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        let expected = trimTraces(in: node)
        let actual = layer.trimTraces ?? []
        compare(expected.count, actual.count, property: "trimTraces.count", node: node, findings: &findings)
        for index in 0 ..< min(expected.count, actual.count) {
            compare(expected[index].sourcePath, actual[index].sourcePath, property: "trimTraces[\(index)].sourcePath", node: node, findings: &findings)
            compare(expected[index].jsonPath, actual[index].jsonPath, property: "trimTraces[\(index)].jsonPath", node: node, findings: &findings)
            compare(expected[index].authoredMultiple, actual[index].authoredMultiple, property: "trimTraces[\(index)].authoredMultiple", node: node, findings: &findings)
            compare(expected[index].mode.rawValue, actual[index].mode.rawValue, property: "trimTraces[\(index)].mode", node: node, findings: &findings)
            compare(
                expected[index].normalization.normalizedStartFraction,
                actual[index].normalization.normalizedStartFraction,
                property: "trimTraces[\(index)].normalizedStartFraction",
                node: node,
                findings: &findings
            )
            compare(
                expected[index].normalization.normalizedEndFraction,
                actual[index].normalization.normalizedEndFraction,
                property: "trimTraces[\(index)].normalizedEndFraction",
                node: node,
                findings: &findings
            )
            compare(
                expected[index].normalization.offsetTurns,
                actual[index].normalization.offsetTurns,
                property: "trimTraces[\(index)].offsetTurns",
                node: node,
                findings: &findings
            )
            compare(expected[index].inputPaths.count, actual[index].inputPaths.count, property: "trimTraces[\(index)].inputPaths.count", node: node, findings: &findings)
            compare(
                expected[index].selectedSegments.count,
                actual[index].selectedSegments.count,
                property: "trimTraces[\(index)].selectedSegments.count",
                node: node,
                findings: &findings
            )
            compare(expected[index].resultPaths.count, actual[index].resultPaths.count, property: "trimTraces[\(index)].resultPaths.count", node: node, findings: &findings)
            compare(
                expected[index].selectedSegments.map(\.startFraction),
                actual[index].selectedSegments.map(\.startFraction),
                property: "trimTraces[\(index)].selectedSegments.startFraction",
                node: node,
                findings: &findings
            )
            compare(
                expected[index].selectedSegments.map(\.endFraction),
                actual[index].selectedSegments.map(\.endFraction),
                property: "trimTraces[\(index)].selectedSegments.endFraction",
                node: node,
                findings: &findings
            )
        }
    }

    private func compareMaskFacts(
        node: LottieRenderNode,
        layer: LottieSourceIntentLayer,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        compare(node.masks.count, layer.masks.count, property: "masks.count", node: node, findings: &findings)
        for index in 0 ..< min(node.masks.count, layer.masks.count) {
            let mask = node.masks[index]
            let decompiled = layer.masks[index]
            compare(mask.source.sourcePath, decompiled.provenance.sourcePath, property: "masks[\(index)].sourcePath", node: node, findings: &findings)
            compare(mask.source.jsonPath.description, decompiled.provenance.jsonPath, property: "masks[\(index)].jsonPath", node: node, findings: &findings)
            compare(mask.name, decompiled.name, property: "masks[\(index)].name", node: node, findings: &findings)
            compare(mask.mode, decompiled.mode, property: "masks[\(index)].mode", node: node, findings: &findings)
            compare(mask.isInverted, decompiled.inverted, property: "masks[\(index)].inverted", node: node, findings: &findings)
            compare(mask.opacity, decompiled.opacity, property: "masks[\(index)].opacity", node: node, findings: &findings)
            comparePath(mask.path, decompiled.path, property: "masks[\(index)].path", node: node, findings: &findings)
        }
    }

    private func compareMatteFacts(
        node: LottieRenderNode,
        layer: LottieSourceIntentLayer,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        compare(node.matte != nil, layer.matte != nil, property: "matte.present", node: node, findings: &findings)
        guard let matte = node.matte, let decompiled = layer.matte else { return }
        compare(matte.mode, decompiled.mode, property: "matte.mode", node: node, findings: &findings)
        compare(matte.sourceLayerIndex, decompiled.sourceLayerIndex, property: "matte.sourceLayerIndex", node: node, findings: &findings)
        compare(matte.sourcePath, decompiled.sourcePath, property: "matte.sourcePath", node: node, findings: &findings)
        compare(matte.isExplicitSource, decompiled.explicitSource, property: "matte.explicitSource", node: node, findings: &findings)
    }

    private func compare(
        _ expected: Int,
        _ actual: Int,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        guard expected != actual else { return }
        findings.append(finding(
            ruleID: "lottie.round-trip.feature.count",
            node: node,
            property: property,
            expected: String(expected),
            actual: String(actual),
            reason: "Decompiled source intent changed a measured feature count."
        ))
    }

    private func compare(
        _ expected: String,
        _ actual: String,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        guard expected != actual else { return }
        findings.append(finding(
            ruleID: "lottie.round-trip.feature.string",
            node: node,
            property: property,
            expected: expected,
            actual: actual,
            reason: "Decompiled source intent changed a measured source feature string."
        ))
    }

    private func compare(
        _ expected: Bool,
        _ actual: Bool,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        guard expected != actual else { return }
        findings.append(finding(
            ruleID: "lottie.round-trip.feature.boolean",
            node: node,
            property: property,
            expected: String(expected),
            actual: String(actual),
            reason: "Decompiled source intent changed a measured source feature flag."
        ))
    }

    private func compare(
        _ expected: Double,
        _ actual: Double,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        guard expected.isFinite, actual.isFinite, abs(expected - actual) > tolerance else { return }
        findings.append(finding(
            ruleID: "lottie.round-trip.transform-timing.value",
            node: node,
            property: property,
            expected: String(expected),
            actual: String(actual),
            reason: "Decompiled source intent changed a measured transform/timing scalar."
        ))
    }

    private func compare(
        _ expected: Double,
        _ actual: Double?,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        guard let actual else {
            appendOptionalFinding(expected: String(expected), actual: "nil", property: property, node: node, findings: &findings)
            return
        }
        compare(expected, actual, property: property, node: node, findings: &findings)
    }

    private func compare(
        _ expected: Double?,
        _ actual: Double?,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        switch (expected, actual) {
        case let (expected?, actual?):
            compare(expected, actual, property: property, node: node, findings: &findings)
        case (nil, nil):
            return
        case let (expected?, nil):
            appendOptionalFinding(expected: String(expected), actual: "nil", property: property, node: node, findings: &findings)
        case let (nil, actual?):
            appendOptionalFinding(expected: "nil", actual: String(actual), property: property, node: node, findings: &findings)
        }
    }

    private func compare(
        _ expected: Int?,
        _ actual: Int?,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        compareOptional(expected.map(String.init), actual.map(String.init), property: property, node: node, findings: &findings)
    }

    private func compare(
        _ expected: String?,
        _ actual: String?,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        compareOptional(expected, actual, property: property, node: node, findings: &findings)
    }

    private func compare(
        _ expected: Bool,
        _ actual: Bool?,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        compareOptional(String(expected), actual.map(String.init), property: property, node: node, findings: &findings)
    }

    private func compare(
        _ expected: Bool?,
        _ actual: Bool?,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        compareOptional(expected.map(String.init), actual.map(String.init), property: property, node: node, findings: &findings)
    }

    private func compareOptional(
        _ expected: String?,
        _ actual: String?,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        guard expected != actual else { return }
        appendOptionalFinding(
            expected: expected ?? "nil",
            actual: actual ?? "nil",
            property: property,
            node: node,
            findings: &findings
        )
    }

    private func appendOptionalFinding(
        expected: String,
        actual: String,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        findings.append(finding(
            ruleID: "lottie.round-trip.feature.optional",
            node: node,
            property: property,
            expected: expected,
            actual: actual,
            reason: "Decompiled source intent changed optional measured source feature evidence."
        ))
    }

    private func compare(
        _ expected: [Double],
        _ actual: [Double],
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        guard expected.count == actual.count else {
            findings.append(finding(
                ruleID: "lottie.round-trip.transform-timing.vector-count",
                node: node,
                property: property,
                expected: "\(expected)",
                actual: "\(actual)",
                reason: "Decompiled source intent changed a measured vector arity."
            ))
            return
        }
        for index in expected.indices where abs(expected[index] - actual[index]) > tolerance {
            findings.append(finding(
                ruleID: "lottie.round-trip.transform-timing.vector-value",
                node: node,
                property: "\(property)[\(index)]",
                expected: String(expected[index]),
                actual: String(actual[index]),
                reason: "Decompiled source intent changed a measured transform/timing vector."
            ))
        }
    }

    private func comparePath(
        _ expected: LottieBezier?,
        _ actual: LottieSourceIntentPath?,
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        switch (expected, actual) {
        case let (expected?, actual?):
            compare(expected.isClosed, actual.closed, property: "\(property).closed", node: node, findings: &findings)
            compareNested(expected.vertices, actual.vertices, property: "\(property).vertices", node: node, findings: &findings)
            compareNested(expected.inTangents, actual.inTangents, property: "\(property).inTangents", node: node, findings: &findings)
            compareNested(expected.outTangents, actual.outTangents, property: "\(property).outTangents", node: node, findings: &findings)
        case (nil, nil):
            return
        case (.some, nil):
            appendOptionalFinding(expected: "path", actual: "nil", property: property, node: node, findings: &findings)
        case (nil, .some):
            appendOptionalFinding(expected: "nil", actual: "path", property: property, node: node, findings: &findings)
        }
    }

    private func compareNested(
        _ expected: [[Double]],
        _ actual: [[Double]],
        property: String,
        node: LottieRenderNode,
        findings: inout [LottieSourceIntentRoundTripFinding]
    ) {
        compare(expected.count, actual.count, property: "\(property).count", node: node, findings: &findings)
        for index in 0 ..< min(expected.count, actual.count) {
            compare(expected[index], actual[index], property: "\(property)[\(index)]", node: node, findings: &findings)
        }
    }

    private func finding(
        ruleID: String,
        node: LottieRenderNode,
        property: String,
        expected: String,
        actual: String,
        reason: String
    ) -> LottieSourceIntentRoundTripFinding {
        LottieSourceIntentRoundTripFinding(
            ruleID: ruleID,
            sourcePath: node.source.sourcePath,
            jsonPath: node.source.jsonPath.description,
            property: property,
            expected: expected,
            actual: actual,
            reason: reason
        )
    }

    private func timingMode(for node: LottieRenderNode, in frame: LottieRenderFrame) -> String? {
        frame.layerGraph.records.first { $0.sourcePath == node.source.sourcePath }?.timing.mode.rawValue
    }

    private func featureLosses(
        _ frame: LottieRenderFrame,
        frameOffset: Int
    ) -> [LottieDecompiledSourceIntentLoss] {
        frame.nodes.indices.flatMap { nodeOffset in
            nodeFeatureLosses(
                frame.nodes[nodeOffset],
                modelPath: "$.frames[\(frameOffset)].visibleLayers[\(nodeOffset)]"
            )
        }
    }

    private func nodeFeatureLosses(
        _ node: LottieRenderNode,
        modelPath: String
    ) -> [LottieDecompiledSourceIntentLoss] {
        trimApproximationLosses(node, modelPath: modelPath)
            + styleBackendLosses(node, modelPath: modelPath)
            + maskBackendLosses(node, modelPath: modelPath)
            + matteBackendLosses(node, modelPath: modelPath)
    }

    private func trimApproximationLosses(
        _ node: LottieRenderNode,
        modelPath: String
    ) -> [LottieDecompiledSourceIntentLoss] {
        trimTraces(in: node).enumerated().flatMap { trimIndex, trace in
            trace.approximations.enumerated().map { approximationIndex, approximation in
                LottieDecompiledSourceIntentLoss(
                    kind: .approximation,
                    reconstructability: .reconstructedWithLoss,
                    phase: "semantic",
                    classification: "approximate",
                    modelPath: "\(modelPath).trimTraces[\(trimIndex)].approximations[\(approximationIndex)]",
                    sourcePath: trace.sourcePath,
                    jsonPath: trace.jsonPath,
                    ruleID: "lottie.round-trip.trim.approximation",
                    reason: "Trim source intent uses a documented lottie-web compatibility approximation that must remain explicit before backend lowering.",
                    evidence: "\(approximation.name)=\(approximation.value); \(approximation.evidence)"
                )
            }
        }
    }

    private func styleBackendLosses(
        _ node: LottieRenderNode,
        modelPath: String
    ) -> [LottieDecompiledSourceIntentLoss] {
        shapeDraws(in: node).enumerated().flatMap { styleIndex, draw in
            switch draw.style {
            case let .fill(fill):
                return fill.blendMode.map { blendMode in
                    backendLoss(
                        modelPath: "\(modelPath).styles[\(styleIndex)].blendMode",
                        source: draw.source,
                        ruleID: "lottie.round-trip.style.fill-blend-mode-loss",
                        feature: "fill blend mode",
                        evidence: "blendMode=\(blendMode)"
                    )
                }.map { [$0] } ?? []
            case let .stroke(stroke):
                var losses: [LottieDecompiledSourceIntentLoss] = []
                if let blendMode = stroke.blendMode {
                    losses.append(backendLoss(
                        modelPath: "\(modelPath).styles[\(styleIndex)].blendMode",
                        source: draw.source,
                        ruleID: "lottie.round-trip.style.stroke-blend-mode-loss",
                        feature: "stroke blend mode",
                        evidence: "blendMode=\(blendMode)"
                    ))
                }
                if let lineCap = stroke.lineCap {
                    losses.append(backendLoss(
                        modelPath: "\(modelPath).styles[\(styleIndex)].lineCap",
                        source: draw.source,
                        ruleID: "lottie.round-trip.style.stroke-line-cap-loss",
                        feature: "stroke line cap",
                        evidence: "lineCap=\(lineCap)"
                    ))
                }
                if let lineJoin = stroke.lineJoin {
                    losses.append(backendLoss(
                        modelPath: "\(modelPath).styles[\(styleIndex)].lineJoin",
                        source: draw.source,
                        ruleID: "lottie.round-trip.style.stroke-line-join-loss",
                        feature: "stroke line join",
                        evidence: "lineJoin=\(lineJoin)"
                    ))
                }
                if let miterLimit = stroke.miterLimit {
                    losses.append(backendLoss(
                        modelPath: "\(modelPath).styles[\(styleIndex)].miterLimit",
                        source: draw.source,
                        ruleID: "lottie.round-trip.style.stroke-miter-limit-loss",
                        feature: "stroke miter limit",
                        evidence: "miterLimit=\(miterLimit)"
                    ))
                }
                if !stroke.dashPattern.isEmpty {
                    losses.append(backendLoss(
                        modelPath: "\(modelPath).styles[\(styleIndex)].dashPattern",
                        source: draw.source,
                        ruleID: "lottie.round-trip.style.stroke-dash-loss",
                        feature: "stroke dash pattern",
                        evidence: "dashCount=\(stroke.dashPattern.count)"
                    ))
                }
                return losses
            }
        }
    }

    private func maskBackendLosses(
        _ node: LottieRenderNode,
        modelPath: String
    ) -> [LottieDecompiledSourceIntentLoss] {
        var losses: [LottieDecompiledSourceIntentLoss] = []
        if node.masks.count > 1 {
            losses.append(backendLoss(
                modelPath: "\(modelPath).masks",
                source: node.source,
                ruleID: "lottie.round-trip.mask.multiple-loss",
                feature: "multiple masks",
                evidence: "maskCount=\(node.masks.count)"
            ))
        }
        for maskIndex in node.masks.indices {
            let mask = node.masks[maskIndex]
            if mask.mode != "a", mask.mode != "n" {
                losses.append(backendLoss(
                    modelPath: "\(modelPath).masks[\(maskIndex)].mode",
                    source: mask.source,
                    ruleID: "lottie.round-trip.mask.mode-loss",
                    feature: "mask mode",
                    evidence: "mode=\(mask.mode)"
                ))
            }
            if mask.isInverted {
                losses.append(backendLoss(
                    modelPath: "\(modelPath).masks[\(maskIndex)].inverted",
                    source: mask.source,
                    ruleID: "lottie.round-trip.mask.inverted-loss",
                    feature: "inverted mask",
                    evidence: "inverted=true"
                ))
            }
            if mask.path == nil {
                losses.append(backendLoss(
                    modelPath: "\(modelPath).masks[\(maskIndex)].path",
                    source: mask.source,
                    ruleID: "lottie.round-trip.mask.path-loss",
                    feature: "mask path",
                    evidence: "pathEvaluated=false"
                ))
            }
        }
        return losses
    }

    private func matteBackendLosses(
        _ node: LottieRenderNode,
        modelPath: String
    ) -> [LottieDecompiledSourceIntentLoss] {
        guard let matte = node.matte else { return [] }
        var losses: [LottieDecompiledSourceIntentLoss] = []
        if matte.mode != 1 {
            losses.append(backendLoss(
                modelPath: "\(modelPath).matte.mode",
                source: node.source,
                ruleID: "lottie.round-trip.matte.mode-loss",
                feature: "track matte mode",
                evidence: "mode=\(matte.mode); sourcePath=\(matte.sourcePath ?? "")"
            ))
        }
        if matte.sourcePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            losses.append(backendLoss(
                modelPath: "\(modelPath).matte.sourcePath",
                source: node.source,
                ruleID: "lottie.round-trip.matte.source-loss",
                feature: "track matte source",
                evidence: "sourceLayerIndex=\(matte.sourceLayerIndex.map(String.init) ?? "")"
            ))
        }
        return losses
    }

    private func backendLoss(
        modelPath: String,
        source: LottieRenderSource,
        ruleID: String,
        feature: String,
        evidence: String
    ) -> LottieDecompiledSourceIntentLoss {
        LottieDecompiledSourceIntentLoss(
            kind: .unsupported,
            reconstructability: .notReconstructable,
            phase: "lowering",
            classification: "reported",
            modelPath: modelPath,
            sourcePath: source.sourcePath,
            jsonPath: source.jsonPath.description,
            sourceRange: source.sourceRange?.description,
            ruleID: ruleID,
            reason: "\(feature) is preserved as source intent but is not yet an exact PureLayer backend operation.",
            evidence: evidence
        )
    }

    private func shapeDraws(in node: LottieRenderNode) -> [LottieRenderShapeDraw] {
        guard case let .shape(shape) = node.kind else { return [] }
        return shape.draws
    }

    private func geometryFragments(in node: LottieRenderNode) -> [LottieRenderGeometryFragment] {
        shapeDraws(in: node).flatMap(\.fragments)
    }

    private func trimTraces(in node: LottieRenderNode) -> [LottieSourceTrimTrace] {
        shapeDraws(in: node).flatMap(\.trimTraces)
    }

    private func translation(from matrix: [Double]) -> [Double] {
        guard matrix.count == 16 else { return [] }
        return [matrix[12], matrix[13], matrix[14]]
    }
}

public final class LottieSourceIntentRoundTripReportValidator {
    private var defaultValidations: [LottieSourceIntentRoundTripAnyValidation]
    private var customValidations: [LottieSourceIntentRoundTripAnyValidation]

    public init() {
        defaultValidations = LottieSourceIntentRoundTripBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [LottieSourceIntentRoundTripAnyValidation],
        customValidations: [LottieSourceIntentRoundTripAnyValidation]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieSourceIntentRoundTripReportValidator {
        LottieSourceIntentRoundTripReportValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieSourceIntentRoundTripReport, some Validatable>) -> Self {
        customValidations.append(LottieSourceIntentRoundTripAnyValidation(validation))
        return self
    }

    @discardableResult
    public func validating(
        _ validation: KeyPath<LottieSourceIntentRoundTripBuiltinValidation.Type, Validation<LottieSourceIntentRoundTripReport, some Validatable>>
    ) -> Self {
        validating(LottieSourceIntentRoundTripBuiltinValidation.self[keyPath: validation])
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    public func validate(_ report: LottieSourceIntentRoundTripReport) throws {
        let errors = collectErrors(in: report)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    public func collectErrors(in report: LottieSourceIntentRoundTripReport) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(report, at: JSONPath(), in: report, errors: &errors)
        visit(report.schema, at: JSONPath([.key("schema")]), in: report, errors: &errors)
        visit(report.source, at: JSONPath([.key("source")]), in: report, errors: &errors)
        for frameIndex in report.frames.indices {
            let frame = report.frames[frameIndex]
            let framePath = JSONPath([.key("frames"), .index(frameIndex)])
            visit(frame, at: framePath, in: report, errors: &errors)
            for layerIndex in frame.layers.indices {
                let layer = frame.layers[layerIndex]
                let layerPath = framePath.appending(.key("layers")).appending(.index(layerIndex))
                visit(layer, at: layerPath, in: report, errors: &errors)
                for findingIndex in layer.findings.indices {
                    visit(
                        layer.findings[findingIndex],
                        at: layerPath.appending(.key("findings")).appending(.index(findingIndex)),
                        in: report,
                        errors: &errors
                    )
                }
            }
            for lossIndex in frame.losses.indices {
                visit(
                    frame.losses[lossIndex],
                    at: framePath.appending(.key("losses")).appending(.index(lossIndex)),
                    in: report,
                    errors: &errors
                )
            }
            for findingIndex in frame.findings.indices {
                visit(
                    frame.findings[findingIndex],
                    at: framePath.appending(.key("findings")).appending(.index(findingIndex)),
                    in: report,
                    errors: &errors
                )
            }
        }
        return errors
    }

    private var activeValidations: [LottieSourceIntentRoundTripAnyValidation] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in report: LottieSourceIntentRoundTripReport,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: report))
        }
    }
}

public enum LottieSourceIntentRoundTripBuiltinValidation {
    fileprivate static var defaultValidations: [LottieSourceIntentRoundTripAnyValidation] {
        [
            LottieSourceIntentRoundTripAnyValidation(schemaNameAndVersionAreSupported),
            LottieSourceIntentRoundTripAnyValidation(sourceIdentityIsPresent),
            LottieSourceIntentRoundTripAnyValidation(reportAggregatesMatchFrames),
            LottieSourceIntentRoundTripAnyValidation(framesArePresentUniqueAndExplained),
            LottieSourceIntentRoundTripAnyValidation(frameAggregatesMatchContents),
            LottieSourceIntentRoundTripAnyValidation(layersArePathBearing),
            LottieSourceIntentRoundTripAnyValidation(layerFeatureCountsAreNonNegative),
            LottieSourceIntentRoundTripAnyValidation(findingsArePathBearing),
            LottieSourceIntentRoundTripAnyValidation(lossesArePathBearing),
        ]
    }

    public static var schemaNameAndVersionAreSupported:
        Validation<LottieSourceIntentRoundTripReport, LottieSourceIntentRoundTripReportSchema>
    {
        Validation(
            ruleID: "lottie.round-trip.schema.supported",
            description: "Round-trip report schema name is purelottie.source-intent-round-trip-report and version is 1",
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.name != "purelottie.source-intent-round-trip-report" {
                errors.append(error("lottie.round-trip.schema.name", at: context.codingPath.appending(.key("name"))))
            }
            if context.subject.version != 1 {
                errors.append(error("lottie.round-trip.schema.version", at: context.codingPath.appending(.key("version"))))
            }
            return errors
        }
    }

    public static var sourceIdentityIsPresent:
        Validation<LottieSourceIntentRoundTripReport, LottieDecompiledSourceIntentSource>
    {
        Validation(
            ruleID: "lottie.round-trip.source.identity",
            description: "Round-trip report source identity is present"
        ) { context in
            context.subject.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [error("lottie.round-trip.source.identity.present", at: context.codingPath.appending(.key("identity")))]
                : []
        }
    }

    public static var reportAggregatesMatchFrames:
        Validation<LottieSourceIntentRoundTripReport, LottieSourceIntentRoundTripReport>
    {
        Validation(
            ruleID: "lottie.round-trip.report.aggregates",
            description: "Round-trip report aggregate counts match frame contents"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.frameCount != context.subject.frames.count {
                errors.append(error("lottie.round-trip.report.frame-count", at: context.codingPath.appending(.key("frameCount"))))
            }
            let findingCount = context.subject.frames.flatMap(\.findings).count
                + context.subject.frames.flatMap(\.layers).flatMap(\.findings).count
            if context.subject.findingCount != findingCount {
                errors.append(error("lottie.round-trip.report.finding-count", at: context.codingPath.appending(.key("findingCount"))))
            }
            let lossCount = context.subject.frames.flatMap(\.losses).count
            if context.subject.lossCount != lossCount {
                errors.append(error("lottie.round-trip.report.loss-count", at: context.codingPath.appending(.key("lossCount"))))
            }
            return errors
        }
    }

    public static var framesArePresentUniqueAndExplained:
        Validation<LottieSourceIntentRoundTripReport, LottieSourceIntentRoundTripReport>
    {
        Validation(
            ruleID: "lottie.round-trip.frames.explained",
            description: "Round-trip report contains unique selected frames with rationales"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.frames.isEmpty {
                errors.append(error("lottie.round-trip.frames.present", at: context.codingPath.appending(.key("frames"))))
            }
            var seen: Set<Double> = []
            for frameIndex in context.subject.frames.indices {
                let frame = context.subject.frames[frameIndex]
                let framePath = context.codingPath.appending(.key("frames")).appending(.index(frameIndex))
                if frame.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append(error("lottie.round-trip.frame.rationale", at: framePath.appending(.key("rationale"))))
                }
                if seen.contains(frame.sourceFrame) {
                    errors.append(error("lottie.round-trip.frame.duplicate", at: framePath.appending(.key("sourceFrame"))))
                }
                seen.insert(frame.sourceFrame)
            }
            return errors
        }
    }

    public static var frameAggregatesMatchContents:
        Validation<LottieSourceIntentRoundTripReport, LottieSourceIntentRoundTripFrame>
    {
        Validation(
            ruleID: "lottie.round-trip.frame.aggregates",
            description: "Round-trip frame aggregate counts match layer finding and loss contents"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.layerCount != context.subject.layers.count {
                errors.append(error("lottie.round-trip.frame.layer-count", at: context.codingPath.appending(.key("layerCount"))))
            }
            let findingCount = context.subject.findings.count + context.subject.layers.flatMap(\.findings).count
            if context.subject.findingCount != findingCount {
                errors.append(error("lottie.round-trip.frame.finding-count", at: context.codingPath.appending(.key("findingCount"))))
            }
            if context.subject.lossCount != context.subject.losses.count {
                errors.append(error("lottie.round-trip.frame.loss-count", at: context.codingPath.appending(.key("lossCount"))))
            }
            return errors
        }
    }

    public static var layersArePathBearing:
        Validation<LottieSourceIntentRoundTripReport, LottieSourceIntentRoundTripLayer>
    {
        Validation(
            ruleID: "lottie.round-trip.layer.path-bearing",
            description: "Round-trip layer records contain source and JSON paths"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error("lottie.round-trip.layer.source-path", at: context.codingPath.appending(.key("sourcePath"))))
            }
            if context.subject.jsonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error("lottie.round-trip.layer.json-path", at: context.codingPath.appending(.key("jsonPath"))))
            }
            return errors
        }
    }

    public static var findingsArePathBearing:
        Validation<LottieSourceIntentRoundTripReport, LottieSourceIntentRoundTripFinding>
    {
        Validation(
            ruleID: "lottie.round-trip.finding.path-bearing",
            description: "Round-trip findings contain rule id source/json paths and a reason"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.ruleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error("lottie.round-trip.finding.rule-id", at: context.codingPath.appending(.key("ruleID"))))
            }
            if context.subject.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error("lottie.round-trip.finding.source-path", at: context.codingPath.appending(.key("sourcePath"))))
            }
            if context.subject.jsonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error("lottie.round-trip.finding.json-path", at: context.codingPath.appending(.key("jsonPath"))))
            }
            if context.subject.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error("lottie.round-trip.finding.reason", at: context.codingPath.appending(.key("reason"))))
            }
            return errors
        }
    }

    public static var layerFeatureCountsAreNonNegative:
        Validation<LottieSourceIntentRoundTripReport, LottieSourceIntentRoundTripLayer>
    {
        Validation(
            ruleID: "lottie.round-trip.layer.feature-counts",
            description: "Round-trip layer feature-family counts are nonnegative"
        ) { context in
            [
                ("geometryCount", context.subject.geometryCount),
                ("decompiledGeometryCount", context.subject.decompiledGeometryCount),
                ("styleCount", context.subject.styleCount),
                ("decompiledStyleCount", context.subject.decompiledStyleCount),
                ("trimTraceCount", context.subject.trimTraceCount),
                ("decompiledTrimTraceCount", context.subject.decompiledTrimTraceCount),
                ("maskCount", context.subject.maskCount),
                ("decompiledMaskCount", context.subject.decompiledMaskCount),
            ].compactMap { name, value in
                value >= 0
                    ? nil
                    : error("lottie.round-trip.layer.feature-count", at: context.codingPath.appending(.key(name)))
            }
        }
    }

    public static var lossesArePathBearing:
        Validation<LottieSourceIntentRoundTripReport, LottieDecompiledSourceIntentLoss>
    {
        Validation(
            ruleID: "lottie.round-trip.loss.path-bearing",
            description: "Round-trip embedded decompiler losses contain rule id model path source/json path and reason"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.ruleID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                errors.append(error("lottie.round-trip.loss.rule-id", at: context.codingPath.appending(.key("ruleID"))))
            }
            if context.subject.modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error("lottie.round-trip.loss.model-path", at: context.codingPath.appending(.key("modelPath"))))
            }
            if context.subject.sourcePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                errors.append(error("lottie.round-trip.loss.source-path", at: context.codingPath.appending(.key("sourcePath"))))
            }
            if context.subject.jsonPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                errors.append(error("lottie.round-trip.loss.json-path", at: context.codingPath.appending(.key("jsonPath"))))
            }
            if context.subject.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error("lottie.round-trip.loss.reason", at: context.codingPath.appending(.key("reason"))))
            }
            return errors
        }
    }

    private static func error(_ ruleID: String, at path: JSONPath) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "Failed to satisfy: Source-intent round-trip report is deterministic and path-bearing",
            at: path,
            phase: .semantic,
            classification: .gap
        )
    }
}

private struct LottieSourceIntentRoundTripAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, LottieSourceIntentRoundTripReport) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<LottieSourceIntentRoundTripReport, Subject>) {
        ruleID = validation.ruleID
        description = validation.description
        applyClosure = { subject, path, document in
            guard let subject = subject as? Subject else { return [] }
            return validation.apply(to: subject, at: path, in: document)
        }
    }

    func apply(
        to subject: any Validatable,
        at path: JSONPath,
        in document: LottieSourceIntentRoundTripReport
    ) -> [ValidationError] {
        applyClosure(subject, path, document)
    }
}

public extension LottieSourceIntentRoundTripReport {
    @discardableResult
    func validate(
        using validator: LottieSourceIntentRoundTripReportValidator = LottieSourceIntentRoundTripReportValidator()
    ) throws -> Self {
        try validator.validate(self)
        return self
    }
}
