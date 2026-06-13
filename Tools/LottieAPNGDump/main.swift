import Foundation
import LottieEvaluation
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
        let animation = try LottieSourceDocument.parse(data).decodeAnimation()
        let scene = try LottieImporter().scene(from: data)
        let start = options.start ?? 0
        let end = options.end ?? scene.duration
        let sampleEnd = inclusiveSampleEnd(start: start, exclusiveEnd: end, fps: options.fps)
        let size = LottieRenderSurface.pixelSize(for: scene, scale: options.scale)
        let sourceFrames = Self.sourceFrames(animation: animation, start: start, end: sampleEnd, fps: options.fps)
        var renderIRFindings: [ImportReport.Finding] = []
        let framePNGs = try sourceFrames.map { sourceFrame in
            let frame = LottieRenderIRBuilder(animation: animation).frame(at: sourceFrame)
            let tree = LottieRenderIRLowerer().lower(frame)
            renderIRFindings.append(contentsOf: tree.report.findings)
            let root = LottieRenderSurface.root(tree.root, width: animation.width, height: animation.height, scale: options.scale)
            return try MovieExporter().screenshot(of: root, size: size, at: 0)
        }

        try Data(PNGSequenceEncoder.animatedPNG(from: framePNGs, frameDelay: 1 / options.fps)).write(to: options.output)
        let geometryTrace = LottieGeometryTraceBuilder().trace(
            animation: animation,
            sourceFrames: sourceFrames,
            scale: options.scale
        ) { sourceFrame, _ in
            let frame = LottieRenderIRBuilder(animation: animation).frame(at: sourceFrame)
            let tree = LottieRenderIRLowerer().lower(frame)
            return LottieRenderSurface.root(tree.root, width: animation.width, height: animation.height, scale: options.scale)
        }
        try writeGeometryTrace(geometryTrace, output: options.output)
        try writeReport(
            scene: scene,
            options: options,
            start: start,
            end: sampleEnd,
            size: size,
            frameCount: sourceFrames.count,
            renderIRFindings: renderIRFindings
        )
    }

    private static func inclusiveSampleEnd(start: Double, exclusiveEnd end: Double, fps: Double) -> Double {
        guard end > start, fps > 0 else { return start }
        return max(start, end - 1 / fps)
    }

    private static func sourceFrames(
        animation: LottieAnimation,
        start: Double,
        end: Double,
        fps: Double
    ) -> [Double] {
        sampleTimes(start: start, end: end, fps: fps).map { time in
            animation.inPoint + time * animation.frameRate
        }
    }

    private static func sampleTimes(start: Double, end: Double, fps: Double) -> [Double] {
        let frameCount = max(1, Int((max(0, end - start) * fps).rounded()) + 1)
        guard frameCount > 1 else { return [start] }
        return (0 ..< frameCount).map { index in
            let progress = Double(index) / Double(frameCount - 1)
            return start + (end - start) * progress
        }
    }

    private static func writeReport(
        scene: LottieScene,
        options: Options,
        start: Double,
        end: Double,
        size: PixelSize,
        frameCount: Int,
        renderIRFindings: [ImportReport.Finding]
    ) throws {
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
            importFindings: scene.report.findings.map(ImportFindingSummary.init),
            renderIRLoweringFindingCount: renderIRFindings.count,
            renderIRLoweringFindings: renderIRFindings.map(ImportFindingSummary.init),
            geometryTrace: options.output.deletingPathExtension().appendingPathExtension("geometry.json").path,
            geometryCSV: options.output.deletingPathExtension().appendingPathExtension("geometry.csv").path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        let reportURL = options.output
            .deletingPathExtension()
            .appendingPathExtension("report.json")
        try data.write(to: reportURL)
    }

    private static func writeGeometryTrace(_ trace: LottieGeometryTrace, output: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(trace)
        try json.write(to: output.deletingPathExtension().appendingPathExtension("geometry.json"))
        try geometryCSV(trace).write(
            to: output.deletingPathExtension().appendingPathExtension("geometry.csv"),
            atomically: true,
            encoding: .utf8
        )
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
    var renderIRLoweringFindingCount: Int
    var renderIRLoweringFindings: [ImportFindingSummary]
    var geometryTrace: String
    var geometryCSV: String
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

private enum PNGSequenceEncoder {
    struct Frame {
        var width: UInt32
        var height: UInt32
        var idat: [UInt8]
    }

    static func animatedPNG(from pngFrames: [[UInt8]], frameDelay: Double) throws -> [UInt8] {
        let frames = try pngFrames.map(Frame.init(png:))
        guard let first = frames.first else { return [] }
        guard frames.count > 1 else { return pngFrames[0] }
        guard frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw UsageError("All APNG frames must have the same dimensions")
        }

        let delayNumerator = UInt16(min(65535, max(0, Int((frameDelay * 1000).rounded()))))
        let delayDenominator: UInt16 = 1000
        var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        appendChunk(type: "IHDR", data: ihdr(width: first.width, height: first.height), to: &png)

        var actl: [UInt8] = []
        appendBigEndian(UInt32(frames.count), to: &actl)
        appendBigEndian(UInt32(0), to: &actl)
        appendChunk(type: "acTL", data: actl, to: &png)

        var sequence: UInt32 = 0
        for (index, frame) in frames.enumerated() {
            var fctl: [UInt8] = []
            appendBigEndian(sequence, to: &fctl)
            sequence += 1
            appendBigEndian(frame.width, to: &fctl)
            appendBigEndian(frame.height, to: &fctl)
            appendBigEndian(UInt32(0), to: &fctl)
            appendBigEndian(UInt32(0), to: &fctl)
            fctl.append(UInt8(delayNumerator >> 8))
            fctl.append(UInt8(delayNumerator & 0xFF))
            fctl.append(UInt8(delayDenominator >> 8))
            fctl.append(UInt8(delayDenominator & 0xFF))
            fctl.append(1)
            fctl.append(0)
            appendChunk(type: "fcTL", data: fctl, to: &png)

            if index == 0 {
                appendChunk(type: "IDAT", data: frame.idat, to: &png)
            } else {
                var fdat: [UInt8] = []
                appendBigEndian(sequence, to: &fdat)
                sequence += 1
                fdat.append(contentsOf: frame.idat)
                appendChunk(type: "fdAT", data: fdat, to: &png)
            }
        }

        appendChunk(type: "IEND", data: [], to: &png)
        return png
    }

    private static func ihdr(width: UInt32, height: UInt32) -> [UInt8] {
        var data: [UInt8] = []
        appendBigEndian(width, to: &data)
        appendBigEndian(height, to: &data)
        data.append(contentsOf: [8, 6, 0, 0, 0])
        return data
    }

    private static func appendChunk(type: String, data: [UInt8], to png: inout [UInt8]) {
        let typeBytes = Array(type.utf8)
        appendBigEndian(UInt32(data.count), to: &png)
        png.append(contentsOf: typeBytes)
        png.append(contentsOf: data)
        appendBigEndian(crc32(typeBytes + data), to: &png)
    }

    private static func appendBigEndian(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8((value >> 24) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                let mask = UInt32(bitPattern: -Int32(crc & 1))
                crc = (crc >> 1) ^ (0xEDB8_8320 & mask)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension PNGSequenceEncoder.Frame {
    init(png bytes: [UInt8]) throws {
        guard bytes.count >= 8,
              Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10]
        else {
            throw UsageError("Frame is not a PNG")
        }

        var width: UInt32?
        var height: UInt32?
        var idat: [UInt8] = []
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(Self.readUInt32(bytes, at: offset))
            guard offset + 12 + length <= bytes.count else {
                throw UsageError("Malformed PNG chunk")
            }
            let typeStart = offset + 4
            let dataStart = offset + 8
            let type = String(bytes: bytes[typeStart ..< typeStart + 4], encoding: .ascii)
            let data = Array(bytes[dataStart ..< dataStart + length])
            switch type {
            case "IHDR":
                guard length >= 13 else { throw UsageError("Malformed PNG IHDR") }
                width = Self.readUInt32(data, at: 0)
                height = Self.readUInt32(data, at: 4)
                guard data[8] == 8, data[9] == 6, data[10] == 0, data[11] == 0, data[12] == 0 else {
                    throw UsageError("Frame PNG must be 8-bit RGBA without interlace")
                }
            case "IDAT":
                idat.append(contentsOf: data)
            case "IEND":
                break
            default:
                break
            }
            offset += 12 + length
        }
        guard let width, let height, !idat.isEmpty else {
            throw UsageError("PNG frame is missing IHDR or IDAT")
        }
        self.width = width
        self.height = height
        self.idat = idat
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 |
            UInt32(bytes[offset + 1]) << 16 |
            UInt32(bytes[offset + 2]) << 8 |
            UInt32(bytes[offset + 3])
    }
}
