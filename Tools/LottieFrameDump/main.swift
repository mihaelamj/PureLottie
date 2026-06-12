import Foundation
import LottieImport
import LottieModel
import PureLayer

@main
struct LottieFrameDump {
    static func main() throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)

        let data = try Data(contentsOf: options.input)
        let animation = try LottieAnimation.decode(from: data)
        let scene = LottieImporter().scene(from: animation)
        let size = PixelSize(
            width: max(1, Int((scene.width * options.scale).rounded())),
            height: max(1, Int((scene.height * options.scale).rounded()))
        )

        let exporter = MovieExporter()
        for frame in options.frames {
            let time = max(0, (frame - animation.inPoint) / animation.frameRate)
            let url = options.output.appendingPathComponent(Self.fileName(for: frame))
            try exporter.writeScreenshot(of: scene.root, size: size, at: time, to: url)
        }

        let report = scene.report.findings.map { finding in
            "\(finding.disposition.rawValue)\t\(finding.feature)\t\(finding.path)"
        }
        .joined(separator: "\n")
        try report.write(
            to: options.output.appendingPathComponent("purelayer-import-report.tsv"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func fileName(for frame: Double) -> String {
        "frame_\(String(format: "%07.2f", frame)).png"
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
