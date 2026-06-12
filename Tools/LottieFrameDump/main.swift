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

        var dumpedFrames: [DumpFrameSummary] = []
        if let scene {
            let size = PixelSize(
                width: max(1, Int((scene.width * options.scale).rounded())),
                height: max(1, Int((scene.height * options.scale).rounded()))
            )
            let exporter = MovieExporter()
            for frame in options.frames {
                let time = max(0, (frame - animation.inPoint) / animation.frameRate)
                let fileName = Self.fileName(for: frame)
                let url = options.output.appendingPathComponent(fileName)
                try exporter.writeScreenshot(of: scene.root, size: size, at: time, to: url)
                dumpedFrames.append(DumpFrameSummary(
                    frame: frame,
                    timeSeconds: time,
                    file: fileName,
                    rendered: true
                ))
            }
        } else {
            dumpedFrames = options.frames.map { frame in
                DumpFrameSummary(
                    frame: frame,
                    timeSeconds: max(0, (frame - animation.inPoint) / animation.frameRate),
                    file: Self.fileName(for: frame),
                    rendered: false
                )
            }
        }

        let importFindings = scene?.report.findings ?? []
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
            dumpedFrames: dumpedFrames
        )
    }

    private static func fileName(for frame: Double) -> String {
        "frame_\(String(format: "%07.2f", frame)).png"
    }

    private static func writeSummary(
        animation: LottieAnimation,
        input: URL,
        output: URL,
        scale: Double,
        validationEligible: Bool,
        validationErrors: [ValidationError],
        importFindings: [ImportReport.Finding],
        dumpedFrames: [DumpFrameSummary]
    ) throws {
        let renderFrames = optionsRenderFrames(animation: animation, frames: dumpedFrames.map(\.frame))
        let summary = DumpSummary(
            input: input.path,
            scale: scale,
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
            renderIR: renderFrames
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(summary)
        try data.write(to: output.appendingPathComponent("oracle-summary.json"))
    }

    private static func optionsRenderFrames(animation: LottieAnimation, frames: [Double]) -> [RenderFrameSummary] {
        let builder = LottieRenderIRBuilder(animation: animation)
        return frames.map { frame in
            let renderFrame = builder.frame(at: frame)
            return RenderFrameSummary(frame: renderFrame)
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
    var composition: CompositionSummary
    var validation: ValidationSummary
    var importReport: ImportReportSummary
    var frames: [DumpFrameSummary]
    var renderIR: [RenderFrameSummary]
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

    init(_ finding: ImportReport.Finding) {
        path = finding.path
        sourcePath = finding.sourcePath
        sourceRange = finding.sourceRange.map(SourceRangeSummary.init)
        feature = finding.feature
        disposition = finding.disposition.rawValue
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
    var nodes: [RenderNodeSummary]

    init(frame: LottieRenderFrame) {
        self.frame = frame.sourceFrame
        nodeCount = frame.nodes.count
        diagnosticCount = frame.diagnostics.count
        diagnostics = frame.diagnostics.map(ValidationErrorSummary.init)
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
