import Foundation
import LottieEvaluation
import LottieImport
import LottieModel
import PureLayer

@main
struct LottieFrameDump {
    static func main() throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)

        let data = try Data(contentsOf: options.input)
        let document = try LottieSourceDocument.parse(data)
        let validator = LottieValidator()
        let validationErrors = validator.collectErrors(in: document)
        let validationEligible = validationErrors.isEmpty
        let animation = try document.decodeAnimation()

        let scene = validationEligible
            ? try LottieImporter().scene(from: data, validator: validator)
            : nil

        let size = LottieRenderSurface.pixelSize(width: animation.width, height: animation.height, scale: options.scale)
        let exporter = MovieExporter()
        let frameTiming = LottieArtifactFrameTiming.explicitSourceFrameList(
            source: .init(animation: animation),
            sourceFrames: options.frames
        )
        try frameTiming.validate()
        var dumpedFrames: [DumpFrameSummary] = []
        for sample in frameTiming.samples {
            let frame = sample.sourceFrame
            let fileName = Self.fileName(for: frame)
            let url = options.output.appendingPathComponent(fileName)
            let root = renderRoot(animation: animation, sourceFrame: frame, scale: options.scale)
            try exporter.writeScreenshot(of: root, size: size, at: 0, to: url)
            dumpedFrames.append(DumpFrameSummary(
                frame: frame,
                timeSeconds: sample.timeSeconds,
                file: fileName,
                rendered: true
            ))
        }

        let importFindings = scene?.report.findings ?? []
        let geometryTraceFiles = try {
            let trace = LottieGeometryTraceBuilder().trace(
                animation: animation,
                sourceFrames: options.frames,
                scale: options.scale
            ) { sourceFrame, _ in
                renderRoot(animation: animation, sourceFrame: sourceFrame, scale: options.scale)
            }
            return try writeGeometryTrace(trace, output: options.output)
        }()
        let report = importFindings.map { finding in
            "\(finding.disposition.rawValue)\t\(finding.feature)\t\(finding.path)"
        }
        .joined(separator: "\n")
        try report.write(
            to: options.output.appendingPathComponent("purelayer-import-report.tsv"),
            atomically: true,
            encoding: .utf8
        )
        try writeSummary(
            animation: animation,
            input: options.input,
            output: options.output,
            scale: options.scale,
            validationEligible: validationEligible,
            validationErrors: validationErrors,
            importFindings: importFindings,
            dumpedFrames: dumpedFrames,
            frameTiming: frameTiming,
            geometryTraceFiles: geometryTraceFiles
        )
    }

    private static func fileName(for frame: Double) -> String {
        "frame_\(String(format: "%07.2f", frame)).png"
    }

    private static func renderRoot(animation: LottieAnimation, sourceFrame: Double, scale: Double) -> Layer {
        let frame = LottieRenderIRBuilder(animation: animation).frame(at: sourceFrame)
        let tree = LottieRenderIRLowerer().lower(frame)
        return LottieRenderSurface.root(tree.root, width: animation.width, height: animation.height, scale: scale)
    }

    private static func writeSummary(
        animation: LottieAnimation,
        input: URL,
        output: URL,
        scale: Double,
        validationEligible: Bool,
        validationErrors: [ValidationError],
        importFindings: [ImportReport.Finding],
        dumpedFrames: [DumpFrameSummary],
        frameTiming: LottieArtifactFrameTiming,
        geometryTraceFiles: GeometryTraceFiles?
    ) throws {
        let renderFrames = optionsRenderFrames(animation: animation, input: input, dumpedFrames: dumpedFrames)
        let summary = DumpSummary(
            input: input.path,
            scale: scale,
            geometryTrace: geometryTraceFiles?.json,
            geometryCSV: geometryTraceFiles?.csv,
            composition: CompositionSummary(
                name: animation.name,
                width: animation.width,
                height: animation.height,
                frameRate: animation.frameRate,
                inPoint: animation.inPoint,
                outPoint: animation.outPoint,
                sourceFrameCount: max(animation.outPoint - animation.inPoint, 0),
                frameWindowSemantics: "Lottie uses a half-open root window: ip <= frame < op."
            ),
            validation: ValidationSummary(
                eligible: validationEligible,
                errorCount: validationErrors.count,
                errors: validationErrors.map(ValidationErrorSummary.init)
            ),
            importReport: ImportReportSummary(
                clean: importFindings.isEmpty,
                findingCount: importFindings.count,
                findings: importFindings.map(ImportFindingSummary.init)
            ),
            frames: dumpedFrames,
            frameTiming: frameTiming,
            renderIR: renderFrames
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(summary)
        try data.write(to: output.appendingPathComponent("oracle-summary.json"))
    }

    private static func writeGeometryTrace(_ trace: LottieGeometryTrace, output: URL) throws -> GeometryTraceFiles {
        let jsonFile = "purelayer-geometry.json"
        let csvFile = "purelayer-geometry.csv"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(trace)
        try json.write(to: output.appendingPathComponent(jsonFile))
        try geometryCSV(trace).write(
            to: output.appendingPathComponent(csvFile),
            atomically: true,
            encoding: .utf8
        )
        return GeometryTraceFiles(json: jsonFile, csv: csvFile)
    }

    private static func geometryCSV(_ trace: LottieGeometryTrace) -> String {
        var rows = [
            [
                "sourceFrame",
                "timeSeconds",
                "index",
                "sourcePath",
                "expectedMinX",
                "expectedMinY",
                "expectedMaxX",
                "expectedMaxY",
                "expectedOutputMinX",
                "expectedOutputMinY",
                "expectedOutputMaxX",
                "expectedOutputMaxY",
                "actualMinX",
                "actualMinY",
                "actualMaxX",
                "actualMaxY",
                "deltaOutputMinX",
                "deltaOutputMinY",
                "deltaOutputMaxX",
                "deltaOutputMaxY",
                "matchesExpectedOutput",
            ].joined(separator: ","),
        ]
        for frame in trace.frames {
            for comparison in frame.comparisons {
                rows.append([
                    number(frame.sourceFrame),
                    number(frame.timeSeconds),
                    "\(comparison.index)",
                    csv(comparison.sourcePath),
                    number(comparison.expectedCompositionBounds.minX),
                    number(comparison.expectedCompositionBounds.minY),
                    number(comparison.expectedCompositionBounds.maxX),
                    number(comparison.expectedCompositionBounds.maxY),
                    number(comparison.expectedOutputBounds.minX),
                    number(comparison.expectedOutputBounds.minY),
                    number(comparison.expectedOutputBounds.maxX),
                    number(comparison.expectedOutputBounds.maxY),
                    number(comparison.actualPureLayerBounds?.minX),
                    number(comparison.actualPureLayerBounds?.minY),
                    number(comparison.actualPureLayerBounds?.maxX),
                    number(comparison.actualPureLayerBounds?.maxY),
                    number(comparison.deltaToExpectedOutputBounds?.minX),
                    number(comparison.deltaToExpectedOutputBounds?.minY),
                    number(comparison.deltaToExpectedOutputBounds?.maxX),
                    number(comparison.deltaToExpectedOutputBounds?.maxY),
                    "\(comparison.matchesExpectedOutputBounds)",
                ].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.6f", value)
    }

    private static func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func optionsRenderFrames(
        animation: LottieAnimation,
        input: URL,
        dumpedFrames: [DumpFrameSummary]
    ) -> [RenderFrameSummary] {
        let builder = LottieRenderIRBuilder(animation: animation)
        return dumpedFrames.map { dumpedFrame in
            let renderFrame = builder.frame(at: dumpedFrame.frame)
            let evidenceContext = LottieBackendEvidenceContext(
                sourceFixture: input.path,
                expectedLottieWebFrameArtifact: "../reference/\(dumpedFrame.file)",
                pureLayerFrameArtifact: dumpedFrame.rendered ? dumpedFrame.file : nil
            )
            let backendReport = LottieRenderIRLowerer()
                .lower(renderFrame, evidenceContext: evidenceContext)
                .report
            return RenderFrameSummary(frame: renderFrame, backendReport: backendReport)
        }
    }
}

private struct Options {
    var input: URL
    var output: URL
    var frames: [Double]
    var scale: Double

    init(arguments: [String]) throws {
        var input: URL?
        var output: URL?
        var frames: [Double] = [0]
        var scale = 1.0

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--input":
                index += 1
                input = try URL(fileURLWithPath: Self.value(arguments, at: index, for: argument))
            case "--output":
                index += 1
                output = try URL(fileURLWithPath: Self.value(arguments, at: index, for: argument))
            case "--frames":
                index += 1
                frames = try Self.value(arguments, at: index, for: argument)
                    .split(separator: ",")
                    .map { value in
                        guard let frame = Double(value) else {
                            throw UsageError("Invalid frame '\(value)'")
                        }
                        return frame
                    }
            case "--scale":
                index += 1
                guard let parsed = try Double(Self.value(arguments, at: index, for: argument)), parsed > 0 else {
                    throw UsageError("Invalid scale")
                }
                scale = parsed
            default:
                throw UsageError("Unknown argument '\(argument)'")
            }
            index += 1
        }

        guard let input else { throw UsageError("Missing --input") }
        guard let output else { throw UsageError("Missing --output") }
        self.input = input
        self.output = output
        self.frames = frames
        self.scale = scale
    }

    private static func value(_ arguments: [String], at index: Int, for name: String) throws -> String {
        guard arguments.indices.contains(index) else {
            throw UsageError("Missing value for \(name)")
        }
        return arguments[index]
    }
}

private struct UsageError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct DumpSummary: Encodable {
    var input: String
    var scale: Double
    var geometryTrace: String?
    var geometryCSV: String?
    var composition: CompositionSummary
    var validation: ValidationSummary
    var importReport: ImportReportSummary
    var frames: [DumpFrameSummary]
    var frameTiming: LottieArtifactFrameTiming
    var renderIR: [RenderFrameSummary]
}

private struct GeometryTraceFiles {
    var json: String
    var csv: String
}

private struct CompositionSummary: Encodable {
    var name: String?
    var width: Double
    var height: Double
    var frameRate: Double
    var inPoint: Double
    var outPoint: Double
    var sourceFrameCount: Double
    var frameWindowSemantics: String
}

private struct ValidationSummary: Encodable {
    var eligible: Bool
    var errorCount: Int
    var errors: [ValidationErrorSummary]
}

private struct ValidationErrorSummary: Encodable {
    var ruleID: String
    var reason: String
    var path: String
    var range: SourceRangeSummary?
    var severity: String
    var phase: String
    var classification: String
    var evidence: String?

    init(_ error: ValidationError) {
        ruleID = error.ruleID
        reason = error.reason
        path = error.codingPath.description
        range = error.range.map(SourceRangeSummary.init)
        severity = error.severity.rawValue
        phase = error.phase.rawValue
        classification = error.classification.rawValue
        evidence = error.evidence
    }
}

private struct ImportReportSummary: Encodable {
    var clean: Bool
    var findingCount: Int
    var findings: [ImportFindingSummary]
}

private struct ImportFindingSummary: Encodable {
    var path: String
    var sourcePath: String?
    var sourceRange: SourceRangeSummary?
    var feature: String
    var disposition: String
    var evidence: BackendGapEvidenceSummary?

    init(_ finding: ImportReport.Finding) {
        path = finding.path
        sourcePath = finding.sourcePath
        sourceRange = finding.sourceRange.map(SourceRangeSummary.init)
        feature = finding.feature
        disposition = finding.disposition.rawValue
        evidence = finding.evidence.map(BackendGapEvidenceSummary.init)
    }
}

private struct BackendGapEvidenceSummary: Encodable {
    var owner: String
    var sourceFixture: String?
    var sourceFrame: Double
    var frameRate: Double
    var lottiePath: String
    var jsonPath: String?
    var sourceRange: SourceRangeSummary?
    var vmTrace: BackendVMTraceSummary?
    var renderNode: BackendRenderNodeSummary?
    var renderTerm: BackendRenderTermSummary?
    var layerGraphRecord: BackendLayerGraphRecordSummary?
    var expectedLottieWebFrameArtifact: String?
    var pureLayerFrameArtifact: String?

    init(_ evidence: LottieBackendGapEvidence) {
        owner = evidence.owner.rawValue
        sourceFixture = evidence.sourceFixture
        sourceFrame = evidence.sourceFrame
        frameRate = evidence.frameRate
        lottiePath = evidence.lottiePath
        jsonPath = evidence.jsonPath
        sourceRange = evidence.sourceRange.map(SourceRangeSummary.init)
        vmTrace = evidence.vmTrace.map(BackendVMTraceSummary.init)
        renderNode = evidence.renderNode.map(BackendRenderNodeSummary.init)
        renderTerm = evidence.renderTerm.map(BackendRenderTermSummary.init)
        layerGraphRecord = evidence.layerGraphRecord.map(BackendLayerGraphRecordSummary.init)
        expectedLottieWebFrameArtifact = evidence.expectedLottieWebFrameArtifact
        pureLayerFrameArtifact = evidence.pureLayerFrameArtifact
    }
}

private struct BackendLayerGraphRecordSummary: Encodable {
    var sourcePath: String
    var jsonPath: String
    var participation: String
    var renderOrder: Int?
    var maskCount: Int
    var matteMode: Int?
    var matteSourcePath: String?
    var matteTargetPath: String?
    var timingMode: String
    var timingInputFrame: Double
    var timingStartTime: Double
    var timingStretch: Double
    var timingFrameRate: Double
    var timingLocalFrame: Double
    var timingTimeRemapSeconds: Double?
    var timingTimeRemapPropertyPath: String?
    var precompositionAssetID: String?
    var precompositionPath: String?
    var precompositionLocalFrame: Double?
    var precompositionChildLayerCount: Int?
    var diagnosticRuleIDs: [String]

    init(_ record: LottieBackendGapEvidence.LayerGraphRecord) {
        sourcePath = record.sourcePath
        jsonPath = record.jsonPath
        participation = record.participation
        renderOrder = record.renderOrder
        maskCount = record.maskCount
        matteMode = record.matteMode
        matteSourcePath = record.matteSourcePath
        matteTargetPath = record.matteTargetPath
        timingMode = record.timingMode
        timingInputFrame = record.timingInputFrame
        timingStartTime = record.timingStartTime
        timingStretch = record.timingStretch
        timingFrameRate = record.timingFrameRate
        timingLocalFrame = record.timingLocalFrame
        timingTimeRemapSeconds = record.timingTimeRemapSeconds
        timingTimeRemapPropertyPath = record.timingTimeRemapPropertyPath
        precompositionAssetID = record.precompositionAssetID
        precompositionPath = record.precompositionPath
        precompositionLocalFrame = record.precompositionLocalFrame
        precompositionChildLayerCount = record.precompositionChildLayerCount
        diagnosticRuleIDs = record.diagnosticRuleIDs
    }
}

private struct BackendVMTraceSummary: Encodable {
    var nodeID: String?
    var instruction: String?
    var compositionStack: [String]
    var layerStack: [String]
    var transformStack: [String]
    var styleStack: [String]
    var matteStack: [String]
    var reason: String?

    init(_ trace: LottieBackendGapEvidence.VMTrace) {
        nodeID = trace.nodeID
        instruction = trace.instruction
        compositionStack = trace.compositionStack
        layerStack = trace.layerStack
        transformStack = trace.transformStack
        styleStack = trace.styleStack
        matteStack = trace.matteStack
        reason = trace.reason
    }
}

private struct BackendRenderNodeSummary: Encodable {
    var nodeID: String
    var kind: String
    var layerName: String
    var layerIndex: Int?
    var sourcePath: String
    var jsonPath: String
    var localFrame: Double
    var opacity: Double
    var explanation: String

    init(_ node: LottieBackendGapEvidence.RenderNode) {
        nodeID = node.nodeID
        kind = node.kind
        layerName = node.layerName
        layerIndex = node.layerIndex
        sourcePath = node.sourcePath
        jsonPath = node.jsonPath
        localFrame = node.localFrame
        opacity = node.opacity
        explanation = node.explanation
    }
}

private struct BackendRenderTermSummary: Encodable {
    var kind: String
    var sourcePath: String
    var jsonPath: String
    var values: [String: String]

    init(_ term: LottieBackendGapEvidence.RenderTerm) {
        kind = term.kind
        sourcePath = term.sourcePath
        jsonPath = term.jsonPath
        values = term.values
    }
}

private struct DumpFrameSummary: Encodable {
    var frame: Double
    var timeSeconds: Double
    var file: String
    var rendered: Bool
}

private struct RenderFrameSummary: Encodable {
    var frame: Double
    var nodeCount: Int
    var diagnosticCount: Int
    var diagnostics: [ValidationErrorSummary]
    var backendEvidenceFindingCount: Int
    var backendEvidenceFindings: [ImportFindingSummary]
    var nodes: [RenderNodeSummary]

    init(frame: LottieRenderFrame, backendReport: ImportReport) {
        self.frame = frame.sourceFrame
        nodeCount = frame.nodes.count
        diagnosticCount = frame.diagnostics.count
        diagnostics = frame.diagnostics.map(ValidationErrorSummary.init)
        backendEvidenceFindingCount = backendReport.findings.count
        backendEvidenceFindings = backendReport.findings.map(ImportFindingSummary.init)
        nodes = frame.nodes.map(RenderNodeSummary.init)
    }
}

private struct RenderNodeSummary: Encodable {
    var id: String
    var layerName: String
    var layerIndex: Int?
    var sourcePath: String
    var jsonPath: String
    var kind: String
    var localFrame: Double
    var opacity: Double
    var explanation: String
    var trace: TraceSummary
    var drawCount: Int
    var maskCount: Int
    var hasMatte: Bool

    init(_ node: LottieRenderNode) {
        id = node.id.description
        layerName = node.layerName
        layerIndex = node.layerIndex
        sourcePath = node.source.sourcePath
        jsonPath = node.source.jsonPath.description
        kind = node.kind.summaryKind
        localFrame = node.localFrame
        opacity = node.opacity
        explanation = node.explanation
        trace = TraceSummary(node.trace)
        drawCount = node.kind.drawCount
        maskCount = node.masks.count
        hasMatte = node.matte != nil
    }
}

private struct TraceSummary: Encodable {
    var nodeID: String
    var instruction: String
    var compositionStack: [String]
    var layerStack: [String]
    var transformStack: [String]
    var styleStack: [String]
    var matteStack: [String]
    var reason: String

    init(_ trace: LottieRenderTraceIdentity) {
        nodeID = trace.nodeID.description
        instruction = trace.instruction.rawValue
        compositionStack = trace.compositionStack
        layerStack = trace.layerStack
        transformStack = trace.transformStack
        styleStack = trace.styleStack
        matteStack = trace.matteStack
        reason = trace.reason
    }
}

private struct SourceRangeSummary: Encodable {
    var description: String
    var start: SourceLocationSummary
    var end: SourceLocationSummary

    init(_ range: SourceRange) {
        description = range.description
        start = SourceLocationSummary(range.start)
        end = SourceLocationSummary(range.end)
    }
}

private struct SourceLocationSummary: Encodable {
    var offset: Int
    var line: Int
    var column: Int

    init(_ location: SourceLocation) {
        offset = location.offset
        line = location.line
        column = location.column
    }
}

private extension LottieRenderNode.Kind {
    var summaryKind: String {
        switch self {
        case .shape:
            "shape"
        case .solid:
            "solid"
        case .null:
            "null"
        case .imagePlaceholder:
            "imagePlaceholder"
        case .textPlaceholder:
            "textPlaceholder"
        case .precompositionBoundary:
            "precompositionBoundary"
        case let .unsupportedLayer(rawType):
            "unsupportedLayer(\(rawType))"
        }
    }

    var drawCount: Int {
        switch self {
        case let .shape(shape):
            shape.draws.count
        default:
            0
        }
    }
}
