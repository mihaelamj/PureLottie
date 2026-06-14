import Foundation
import LottieEvaluation
import LottieImport
import LottieModel
import PureLayer

/// Renders a Lottie file to an animated GIF using PureLayer's own engine
/// (`GIFEncoder` via the extended compositor, so shape blend modes apply). GIF
/// animates in macOS Quick Look and Finder thumbnails, unlike APNG.
///
/// By default frames are composited over an opaque white background: GIF has only
/// 1-bit transparency, so an opacity fade on a transparent canvas would flicker
/// on and off at the 50% threshold; an opaque background turns the fade into a
/// smooth colour blend. Pass `--background none` to keep 1-bit transparency, or
/// `--background RRGGBB` for another backdrop.
@main
struct LottieGIFDump {
    static func main() throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        try FileManager.default.createDirectory(
            at: options.output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let animation = try LottieAnimation.decode(from: Data(contentsOf: options.input))
        let size = LottieRenderSurface.pixelSize(width: animation.width, height: animation.height, scale: options.scale)
        let start = options.start ?? animation.inPoint
        let end = options.end ?? animation.outPoint
        let frameStep = max(1.0, animation.frameRate / options.fps)

        let compositor = Compositor(extensions: .extended)
        let backend = SoftwareBackend()
        var frames: [Image] = []
        var sourceFrame = start
        while sourceFrame < end {
            let frame = LottieRenderIRBuilder(animation: animation).frame(at: sourceFrame)
            let tree = LottieRenderIRLowerer().lower(frame)
            let root = LottieRenderSurface.root(tree.root, width: animation.width, height: animation.height, scale: options.scale)
            if let background = options.background { root.backgroundColor = background }
            try frames.append(backend.render(compositor.drawList(for: root, at: 0), size: size))
            sourceFrame += frameStep
        }
        guard !frames.isEmpty else { throw UsageError("No frames sampled in [\(start), \(end))") }

        let gif = GIFEncoder.encodeAnimated(frames, frameDelay: options.fps > 0 ? 1 / options.fps : 0.1)
        try Data(gif).write(to: options.output)
        FileHandle.standardError.write(Data("wrote \(frames.count) frames to \(options.output.path)\n".utf8))
    }
}

private struct UsageError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) {
        self.description = description
    }
}

private struct Options {
    var input: URL
    var output: URL
    var fps: Double
    var scale: Double
    var start: Double?
    var end: Double?
    var background: Color?

    init(arguments: [String]) throws {
        var input: URL?
        var output: URL?
        var fps = 12.0
        var scale = 1.0
        var start: Double?
        var end: Double?
        var background: Color? = Color(red: 1, green: 1, blue: 1, alpha: 1)

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
            case "--background":
                index += 1
                background = try Self.background(arguments, at: index, for: argument)
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
        self.background = background
    }

    private static func value(_ arguments: [String], at index: Int, for flag: String) throws -> String {
        guard index < arguments.count else { throw UsageError("Missing value for \(flag)") }
        return arguments[index]
    }

    private static func double(_ arguments: [String], at index: Int, for flag: String) throws -> Double {
        guard let value = try Double(value(arguments, at: index, for: flag)) else {
            throw UsageError("Invalid number for \(flag)")
        }
        return value
    }

    private static func positiveDouble(_ arguments: [String], at index: Int, for flag: String) throws -> Double {
        let value = try double(arguments, at: index, for: flag)
        guard value > 0 else { throw UsageError("\(flag) must be positive") }
        return value
    }

    /// `none` -> transparent (1-bit GIF transparency); `RRGGBB` -> that opaque colour.
    private static func background(_ arguments: [String], at index: Int, for flag: String) throws -> Color? {
        let raw = try value(arguments, at: index, for: flag)
        if raw.lowercased() == "none" { return nil }
        guard raw.count == 6, let rgb = Int(raw, radix: 16) else {
            throw UsageError("--background expects 'none' or a six-digit RRGGBB hex")
        }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
