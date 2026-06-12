import Foundation
import LottieImport
import LottieModel
import PureLayer

@main
struct LottieAPNGDump {
    static func main() throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        try FileManager.default.createDirectory(
            at: options.output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try Data(contentsOf: options.input)
        let scene = try LottieImporter().scene(from: data)
        let start = options.start ?? 0
        let end = options.end ?? scene.duration
        let size = PixelSize(
            width: max(1, Int((scene.width * options.scale).rounded())),
            height: max(1, Int((scene.height * options.scale).rounded()))
        )

        try MovieExporter().writeAnimatedPNG(
            of: scene.root,
            size: size,
            from: start,
            to: end,
            fps: options.fps,
            to: options.output
        )
        try writeReport(scene: scene, options: options, start: start, end: end, size: size)
    }

    private static func writeReport(
        scene: LottieScene,
        options: Options,
        start: Double,
        end: Double,
        size: PixelSize
    ) throws {
        let frameCount = max(1, Int((max(0, end - start) * options.fps).rounded()) + 1)
        let report = APNGReport(
            input: options.input.path,
            output: options.output.path,
            width: scene.width,
            height: scene.height,
            pixelWidth: size.width,
            pixelHeight: size.height,
            frameRate: scene.frameRate,
            startSeconds: start,
            endSeconds: end,
            fps: options.fps,
            generatedFrameCount: frameCount,
            importFindingCount: scene.report.findings.count,
            importFindings: scene.report.findings.map(ImportFindingSummary.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        let reportURL = options.output
            .deletingPathExtension()
            .appendingPathExtension("report.json")
        try data.write(to: reportURL)
    }
}

private struct Options {
    var input: URL
    var output: URL
    var fps: Double
    var scale: Double
    var start: Double?
    var end: Double?

    init(arguments: [String]) throws {
        var input: URL?
        var output: URL?
        var fps = 12.0
        var scale = 1.0
        var start: Double?
        var end: Double?

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
            case "--fps":
                index += 1
                fps = try Self.positiveDouble(arguments, at: index, for: argument)
            case "--scale":
                index += 1
                scale = try Self.positiveDouble(arguments, at: index, for: argument)
            case "--from":
                index += 1
                start = try Self.double(arguments, at: index, for: argument)
            case "--to":
                index += 1
                end = try Self.double(arguments, at: index, for: argument)
            default:
                throw UsageError("Unknown argument '\(argument)'")
            }
            index += 1
        }

        guard let input else { throw UsageError("Missing --input") }
        guard let output else { throw UsageError("Missing --output") }
        self.input = input
        self.output = output
        self.fps = fps
        self.scale = scale
        self.start = start
        self.end = end
    }

    private static func value(_ arguments: [String], at index: Int, for name: String) throws -> String {
        guard arguments.indices.contains(index) else {
            throw UsageError("Missing value for \(name)")
        }
        return arguments[index]
    }

    private static func double(_ arguments: [String], at index: Int, for name: String) throws -> Double {
        let rawValue = try value(arguments, at: index, for: name)
        guard let parsed = Double(rawValue) else {
            throw UsageError("Invalid number '\(rawValue)' for \(name)")
        }
        return parsed
    }

    private static func positiveDouble(_ arguments: [String], at index: Int, for name: String) throws -> Double {
        let parsed = try double(arguments, at: index, for: name)
        guard parsed > 0 else {
            throw UsageError("\(name) must be positive")
        }
        return parsed
    }
}

private struct UsageError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct APNGReport: Encodable {
    var input: String
    var output: String
    var width: Double
    var height: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var frameRate: Double
    var startSeconds: Double
    var endSeconds: Double
    var fps: Double
    var generatedFrameCount: Int
    var importFindingCount: Int
    var importFindings: [ImportFindingSummary]
}

private struct ImportFindingSummary: Encodable {
    var path: String
    var sourcePath: String?
    var feature: String
    var disposition: String

    init(_ finding: ImportReport.Finding) {
        path = finding.path
        sourcePath = finding.sourcePath
        feature = finding.feature
        disposition = finding.disposition.rawValue
    }
}
