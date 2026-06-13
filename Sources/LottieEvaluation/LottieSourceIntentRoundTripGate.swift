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
                selection: selection
            )
        }
        return LottieSourceIntentRoundTripReport(source: decompiled.source, frames: frames)
    }

    private func frameReport(
        renderFrame: LottieRenderFrame,
        decompiledFrame: LottieDecompiledSourceIntentFrame,
        selection: LottieSourceIntentRoundTripSelection
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
            losses: decompiledFrame.losses,
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
        return findings
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
