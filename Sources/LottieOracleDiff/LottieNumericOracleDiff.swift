import Foundation
import LottieEvaluation
import LottieModel

public enum LottieNumericOracleDiffCommand {
    public static func run(arguments: [String]) throws -> Int32 {
        let options = try LottieNumericOracleDiffOptions(arguments: arguments)
        let differ = LottieNumericOracleDiffer()
        let report = try differ.report(
            manifestURL: options.manifestURL,
            toleranceURL: options.toleranceURL,
            selectedFixtureID: options.fixtureID
        )
        try FileManager.default.createDirectory(at: options.outputURL, withIntermediateDirectories: true)
        try differ.write(report, to: options.outputURL)
        return report.summary.failedComparisons == 0 ? 0 : 1
    }
}

public struct LottieNumericOracleDiffOptions: Sendable, Equatable {
    public var manifestURL: URL
    public var toleranceURL: URL
    public var outputURL: URL
    public var fixtureID: String?

    public init(arguments: [String], workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws {
        var manifestURL = workingDirectory.appendingPathComponent("Tools/LottieOracle/oracle-fixtures.json")
        var toleranceURL = workingDirectory.appendingPathComponent("Tools/LottieOracle/oracle-tolerances.json")
        var outputURL = workingDirectory.appendingPathComponent("Tools/LottieOracle/artifacts/numeric-diff")
        var fixtureID: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--manifest":
                index += 1
                manifestURL = try Self.url(arguments, at: index, for: argument, relativeTo: workingDirectory)
            case "--tolerances":
                index += 1
                toleranceURL = try Self.url(arguments, at: index, for: argument, relativeTo: workingDirectory)
            case "--output":
                index += 1
                outputURL = try Self.url(arguments, at: index, for: argument, relativeTo: workingDirectory)
            case "--fixture":
                index += 1
                fixtureID = try Self.value(arguments, at: index, for: argument)
            case "--all":
                fixtureID = nil
            case "--help", "-h":
                throw LottieNumericOracleDiffUsage.requested
            default:
                throw LottieNumericOracleDiffUsage.invalid("Unknown argument '\(argument)'")
            }
            index += 1
        }

        self.manifestURL = manifestURL.standardizedFileURL
        self.toleranceURL = toleranceURL.standardizedFileURL
        self.outputURL = outputURL.standardizedFileURL
        self.fixtureID = fixtureID
    }

    private static func url(_ arguments: [String], at index: Int, for name: String, relativeTo base: URL) throws -> URL {
        let rawValue = try value(arguments, at: index, for: name)
        let url = URL(fileURLWithPath: rawValue, relativeTo: base)
        return url.standardizedFileURL
    }

    private static func value(_ arguments: [String], at index: Int, for name: String) throws -> String {
        guard arguments.indices.contains(index) else {
            throw LottieNumericOracleDiffUsage.invalid("Missing value for \(name)")
        }
        return arguments[index]
    }
}

public enum LottieNumericOracleDiffUsage: Error, CustomStringConvertible, Sendable, Equatable {
    case requested
    case invalid(String)

    public var description: String {
        switch self {
        case .requested:
            """
            Usage: swift run LottieNumericOracleDiff [--all] [--fixture fixture-id] [--manifest path] [--tolerances path] [--output path]

            Compares committed lottie-web numeric intent traces against PureLottie RenderIR/source-intent facts.
            Writes numeric-oracle-diff.json and numeric-oracle-diff.md.
            Exits 1 when any numeric comparison fails.
            """
        case let .invalid(message):
            message
        }
    }
}

public struct LottieNumericOracleDiffer: Sendable {
    public init() {}

    public func report(
        manifestURL: URL,
        toleranceURL: URL,
        selectedFixtureID: String? = nil
    ) throws -> LottieNumericOracleDiffReport {
        let manifestRoot = manifestURL.deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode(
            [LottieNumericOracleFixture].self,
            from: Data(contentsOf: manifestURL)
        )
        let selectedFixtures: [LottieNumericOracleFixture]
        if let selectedFixtureID {
            guard let fixture = fixtures.first(where: { $0.id == selectedFixtureID }) else {
                throw LottieNumericOracleDiffError.unknownFixture(selectedFixtureID)
            }
            selectedFixtures = [fixture]
        } else {
            selectedFixtures = fixtures
        }

        let tolerances = try LottieOracleToleranceLedger.decodeValidated(from: Data(contentsOf: toleranceURL))
        let fixtureReports = try selectedFixtures.map { fixture in
            try report(fixture: fixture, manifestRoot: manifestRoot, tolerances: tolerances)
        }
        let comparisons = fixtureReports.flatMap(\.comparisons)
        return LottieNumericOracleDiffReport(
            fixtureCount: fixtureReports.count,
            summary: LottieNumericOracleDiffReport.Summary(
                comparedFields: comparisons.count,
                passedComparisons: comparisons.filter { $0.result == .pass }.count,
                failedComparisons: comparisons.filter { $0.result == .fail }.count,
                witnessedComparisons: comparisons.filter { $0.witness.status == .witnessed }.count,
                assertedComparisons: comparisons.filter { $0.witness.status == .asserted }.count,
                blockedComparisons: comparisons.filter { $0.witness.status == .blocked }.count
            ),
            fixtures: fixtureReports
        )
    }

    public func write(_ report: LottieNumericOracleDiffReport, to outputURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: outputURL.appendingPathComponent("numeric-oracle-diff.json"))
        try markdown(report).write(
            to: outputURL.appendingPathComponent("numeric-oracle-diff.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    public func markdown(_ report: LottieNumericOracleDiffReport) -> String {
        let rows = report.fixtures
            .flatMap(\.comparisons)
            .map { comparison in
                "| \(comparison.fixtureID) | \(format(comparison.frame)) | \(comparison.field) | \(comparison.result.rawValue) | \(comparison.witness.status.rawValue) | \(comparison.toleranceID) | \(format(comparison.expectedValue)) | \(format(comparison.actualValue)) | \(format(comparison.delta)) | \(comparison.expectedPath) | \(comparison.actualPath) |"
            }
            .joined(separator: "\n")
        let coverage = witnessCoverage(report.summary)

        return """
        # Numeric Oracle Diff

        ## Summary

        - Fixtures: \(report.fixtureCount)
        - Compared fields: \(report.summary.comparedFields)
        - Passed: \(report.summary.passedComparisons)
        - Failed: \(report.summary.failedComparisons)
        - Witnessed comparisons: \(report.summary.witnessedComparisons)
        - Asserted comparisons: \(report.summary.assertedComparisons)
        - Blocked comparisons: \(report.summary.blockedComparisons)
        - Witnessed coverage: \(coverage)

        ## Comparisons

        | Fixture | Frame | Field | Result | Witness | Tolerance | Expected | Actual | Delta | Expected path | Actual path |
        | --- | ---: | --- | --- | --- | --- | ---: | ---: | ---: | --- | --- |
        \(rows)

        """
    }

    private func witnessCoverage(_ summary: LottieNumericOracleDiffReport.Summary) -> String {
        guard summary.comparedFields > 0 else { return "0/0 (n/a)" }
        let percent = Double(summary.witnessedComparisons) / Double(summary.comparedFields) * 100
        return "\(summary.witnessedComparisons)/\(summary.comparedFields) (\(String(format: "%.1f", percent))%)"
    }

    private func report(
        fixture: LottieNumericOracleFixture,
        manifestRoot: URL,
        tolerances: LottieOracleToleranceLedger
    ) throws -> LottieNumericOracleDiffFixtureReport {
        let lottieURL = fixture.url(for: fixture.lottie, relativeTo: manifestRoot)
        let intentURL = fixture.url(for: fixture.lottieWebIntent, relativeTo: manifestRoot)
        let animation = try LottieAnimation.decode(from: Data(contentsOf: lottieURL))
        let intent = try LottieWebIntentTrace.decodeValidated(from: Data(contentsOf: intentURL))
        let builder = LottieRenderIRBuilder(animation: animation)
        let witness = fixture.witness

        var comparisons: [LottieNumericOracleDiffComparison] = []
        for frameIndex in intent.frames.indices {
            let webFrame = intent.frames[frameIndex]
            let renderFrame = builder.frame(at: webFrame.frame)
            try comparisons.append(contentsOf: compareDimensions(
                fixture: fixture,
                expectedWidth: intent.width,
                expectedHeight: intent.height,
                webFrame: webFrame,
                renderFrame: renderFrame,
                tolerances: tolerances
            ))
            try comparisons.append(contentsOf: compareLayers(
                fixture: fixture,
                frameIndex: frameIndex,
                webFrame: webFrame,
                renderFrame: renderFrame,
                tolerances: tolerances
            ))
            try comparisons.append(contentsOf: compareMasks(
                fixture: fixture,
                frameIndex: frameIndex,
                webFrame: webFrame,
                renderFrame: renderFrame,
                tolerances: tolerances
            ))
            try comparisons.append(contentsOf: comparePrecompositions(
                fixture: fixture,
                frameIndex: frameIndex,
                webFrame: webFrame,
                renderFrame: renderFrame,
                tolerances: tolerances
            ))
            try comparisons.append(contentsOf: compareTrims(
                fixture: fixture,
                frameIndex: frameIndex,
                webFrame: webFrame,
                renderFrame: renderFrame,
                tolerances: tolerances
            ))
        }
        return LottieNumericOracleDiffFixtureReport(
            id: fixture.id,
            source: fixture.lottie,
            lottieWebIntent: fixture.lottieWebIntent,
            semanticStatus: fixture.semanticStatus,
            witness: witness,
            selectedFrames: intent.frames.map(\.frame),
            result: comparisons.contains { $0.result == .fail } ? .fail : .pass,
            comparisons: comparisons
        )
    }

    private func compareDimensions(
        fixture: LottieNumericOracleFixture,
        expectedWidth: Double,
        expectedHeight: Double,
        webFrame: LottieWebIntentTrace.Frame,
        renderFrame: LottieRenderFrame,
        tolerances: LottieOracleToleranceLedger
    ) throws -> [LottieNumericOracleDiffComparison] {
        try [
            numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "composition.width",
                expectedPath: "$.width",
                actualPath: "RenderIR.width",
                expected: expectedWidth,
                actual: renderFrame.width,
                toleranceID: "bounds.css-pixel.absolute",
                tolerances: tolerances
            ),
            numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "composition.height",
                expectedPath: "$.height",
                actualPath: "RenderIR.height",
                expected: expectedHeight,
                actual: renderFrame.height,
                toleranceID: "bounds.css-pixel.absolute",
                tolerances: tolerances
            ),
        ]
    }

    private func compareLayers(
        fixture: LottieNumericOracleFixture,
        frameIndex: Int,
        webFrame: LottieWebIntentTrace.Frame,
        renderFrame: LottieRenderFrame,
        tolerances: LottieOracleToleranceLedger
    ) throws -> [LottieNumericOracleDiffComparison] {
        var comparisons: [LottieNumericOracleDiffComparison] = []
        let nodesByName = Dictionary(grouping: renderFrame.nodes, by: \.layerName)
        for layerIndex in webFrame.layers.indices {
            let layer = webFrame.layers[layerIndex]
            guard let node = nodesByName[layer.name]?.first else {
                if layer.hasZeroLayerElementBounds {
                    continue
                }
                try comparisons.append(missingActual(
                    fixture: fixture,
                    frame: webFrame.frame,
                    field: "layer.opacity",
                    expectedPath: "$.frames[\(frameIndex)].layers[\(layerIndex)].opacity",
                    actualPath: "RenderIR.nodes[layerName=\(layer.name)].opacity",
                    expected: layer.opacity,
                    toleranceID: "opacity.unit-interval.absolute",
                    tolerances: tolerances
                ))
                continue
            }

            try comparisons.append(numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "layer.opacity",
                expectedPath: "$.frames[\(frameIndex)].layers[\(layerIndex)].opacity",
                actualPath: "\(node.source.sourcePath).opacity",
                expected: layer.opacity,
                actual: node.opacity,
                toleranceID: "opacity.unit-interval.absolute",
                tolerances: tolerances
            ))

            guard fixture.hasDirectTranslationComparison, layer.matrix.indices.contains(13) else {
                continue
            }
            try comparisons.append(numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "layer.translation.x",
                expectedPath: "$.frames[\(frameIndex)].layers[\(layerIndex)].matrix[12]",
                actualPath: "\(node.source.sourcePath).transform.worldMatrix[12]",
                expected: layer.matrix[12],
                actual: node.transform.worldMatrix.values[12],
                toleranceID: "matrix.translation.css-pixel.absolute",
                tolerances: tolerances
            ))
            try comparisons.append(numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "layer.translation.y",
                expectedPath: "$.frames[\(frameIndex)].layers[\(layerIndex)].matrix[13]",
                actualPath: "\(node.source.sourcePath).transform.worldMatrix[13]",
                expected: layer.matrix[13],
                actual: node.transform.worldMatrix.values[13],
                toleranceID: "matrix.translation.css-pixel.absolute",
                tolerances: tolerances
            ))
        }
        return comparisons
    }

    private func compareMasks(
        fixture: LottieNumericOracleFixture,
        frameIndex: Int,
        webFrame: LottieWebIntentTrace.Frame,
        renderFrame: LottieRenderFrame,
        tolerances: LottieOracleToleranceLedger
    ) throws -> [LottieNumericOracleDiffComparison] {
        var comparisons: [LottieNumericOracleDiffComparison] = []
        for (maskIndex, mask) in webFrame.masks.enumerated() {
            let node = renderFrame.nodes.first { $0.layerIndex == mask.layerInd }
            let renderMask = node?.masks.first { $0.name == mask.name && $0.mode == mask.mode }
            try comparisons.append(numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "mask.opacity",
                expectedPath: "$.frames[\(frameIndex)].masks[\(maskIndex)].opacity",
                actualPath: renderMask?.source.sourcePath.appending(".opacity")
                    ?? "RenderIR.nodes[layerInd=\(mask.layerInd)].masks[\(maskIndex)].opacity",
                expected: mask.opacity,
                actual: renderMask?.opacity,
                toleranceID: "opacity.unit-interval.absolute",
                tolerances: tolerances
            ))
        }
        return comparisons
    }

    private func comparePrecompositions(
        fixture: LottieNumericOracleFixture,
        frameIndex: Int,
        webFrame: LottieWebIntentTrace.Frame,
        renderFrame: LottieRenderFrame,
        tolerances: LottieOracleToleranceLedger
    ) throws -> [LottieNumericOracleDiffComparison] {
        var comparisons: [LottieNumericOracleDiffComparison] = []
        for (precompositionIndex, precomposition) in webFrame.precompositions.enumerated() {
            guard let renderedFrame = precomposition.renderedFrame else {
                continue
            }
            let node = renderFrame.nodes.first { candidate in
                guard candidate.layerIndex == precomposition.layerInd else { return false }
                if case .precompositionBoundary = candidate.kind { return true }
                return false
            }
            try comparisons.append(numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "precomposition.renderedFrame",
                expectedPath: "$.frames[\(frameIndex)].precompositions[\(precompositionIndex)].renderedFrame",
                actualPath: node.map { "\($0.source.sourcePath).localFrame" }
                    ?? "RenderIR.nodes[layerInd=\(precomposition.layerInd)].localFrame",
                expected: renderedFrame,
                actual: node?.localFrame,
                toleranceID: "frame.source-frame.absolute",
                tolerances: tolerances
            ))
        }
        return comparisons
    }

    private func compareTrims(
        fixture: LottieNumericOracleFixture,
        frameIndex: Int,
        webFrame: LottieWebIntentTrace.Frame,
        renderFrame: LottieRenderFrame,
        tolerances: LottieOracleToleranceLedger
    ) throws -> [LottieNumericOracleDiffComparison] {
        var comparisons: [LottieNumericOracleDiffComparison] = []
        for trimIndex in webFrame.trims.indices {
            let trim = webFrame.trims[trimIndex]
            let trace = renderFrame.trimTraces(forLayerIndex: trim.layerInd).first
            let actualPath = trace?.jsonPath ?? "RenderIR.nodes[layerInd=\(trim.layerInd)].trimTraces[\(trimIndex)]"
            try comparisons.append(numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "trim.startFraction",
                expectedPath: "$.frames[\(frameIndex)].trims[\(trimIndex)].startFraction",
                actualPath: "\(actualPath).normalization.normalizedStartFraction",
                expected: trim.startFraction,
                actual: trace?.normalization.normalizedStartFraction,
                toleranceID: "trim.segment.unit-interval.absolute",
                tolerances: tolerances
            ))
            try comparisons.append(numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "trim.endFraction",
                expectedPath: "$.frames[\(frameIndex)].trims[\(trimIndex)].endFraction",
                actualPath: "\(actualPath).normalization.normalizedEndFraction",
                expected: trim.endFraction,
                actual: trace?.normalization.normalizedEndFraction,
                toleranceID: "trim.segment.unit-interval.absolute",
                tolerances: tolerances
            ))
            try comparisons.append(numericComparison(
                fixture: fixture,
                frame: webFrame.frame,
                field: "trim.offsetTurns",
                expectedPath: "$.frames[\(frameIndex)].trims[\(trimIndex)].offsetTurns",
                actualPath: "\(actualPath).normalization.offsetTurns",
                expected: trim.offsetTurns,
                actual: trace?.normalization.offsetTurns,
                toleranceID: "trim.segment.unit-interval.absolute",
                tolerances: tolerances
            ))
        }
        return comparisons
    }

    private func numericComparison(
        fixture: LottieNumericOracleFixture,
        frame: Double,
        field: String,
        expectedPath: String,
        actualPath: String,
        expected: Double,
        actual: Double?,
        toleranceID: String,
        tolerances: LottieOracleToleranceLedger
    ) throws -> LottieNumericOracleDiffComparison {
        guard let actual else {
            return try missingActual(
                fixture: fixture,
                frame: frame,
                field: field,
                expectedPath: expectedPath,
                actualPath: actualPath,
                expected: expected,
                toleranceID: toleranceID,
                tolerances: tolerances
            )
        }
        let tolerance = try tolerances.threshold(id: toleranceID)
        let delta = abs(expected - actual)
        return LottieNumericOracleDiffComparison(
            fixtureID: fixture.id,
            frame: frame,
            field: field,
            expectedPath: expectedPath,
            actualPath: actualPath,
            expectedValue: expected,
            actualValue: actual,
            toleranceID: toleranceID,
            tolerance: tolerance,
            delta: delta,
            witness: fixture.witness,
            result: delta <= tolerance ? .pass : .fail
        )
    }

    private func missingActual(
        fixture: LottieNumericOracleFixture,
        frame: Double,
        field: String,
        expectedPath: String,
        actualPath: String,
        expected: Double,
        toleranceID: String,
        tolerances: LottieOracleToleranceLedger
    ) throws -> LottieNumericOracleDiffComparison {
        try LottieNumericOracleDiffComparison(
            fixtureID: fixture.id,
            frame: frame,
            field: field,
            expectedPath: expectedPath,
            actualPath: actualPath,
            expectedValue: expected,
            actualValue: nil,
            toleranceID: toleranceID,
            tolerance: tolerances.threshold(id: toleranceID),
            delta: nil,
            witness: fixture.witness,
            result: .fail
        )
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.6f", value)
    }
}

public struct LottieNumericOracleFixture: Decodable, Sendable, Equatable {
    public var id: String
    public var coverage: [String]
    public var semanticStatus: String
    public var lottie: String
    public var lottieWebIntent: String
    public var frames: [Frame]

    public struct Frame: Decodable, Sendable, Equatable {
        public var frame: Double
        public var rationale: String
    }

    public func url(for path: String, relativeTo root: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL
    }

    public var hasDirectTranslationComparison: Bool {
        let coverageSet = Set(coverage)
        guard coverageSet.contains("animated-position") || coverageSet.contains("split-position") else {
            return false
        }
        return coverageSet.isDisjoint(with: [
            "anchor",
            "rotation",
            "parent-transform",
            "precomp",
            "shape-transform",
            "time-remap",
        ])
    }

    public var witness: LottieClaimWitness {
        Self.witness(forIntentPath: lottieWebIntent)
    }

    public static func witness(forIntentPath path: String) -> LottieClaimWitness {
        LottieClaimWitness(
            status: .witnessed,
            evidence: [path],
            reason: "Expected numeric values are read from a committed lottie-web intent trace generated by pinned lottie-web in Chromium."
        )
    }
}

public struct LottieNumericOracleDiffReport: Codable, Sendable, Equatable {
    public var schema = Schema()
    public var fixtureCount: Int
    public var summary: Summary
    public var fixtures: [LottieNumericOracleDiffFixtureReport]

    public struct Schema: Codable, Sendable, Equatable {
        public var name = "purelottie.numeric-oracle-diff"
        public var version = 2
    }

    public struct Summary: Codable, Sendable, Equatable {
        public var comparedFields: Int
        public var passedComparisons: Int
        public var failedComparisons: Int
        public var witnessedComparisons: Int
        public var assertedComparisons: Int
        public var blockedComparisons: Int
    }
}

public struct LottieNumericOracleDiffFixtureReport: Codable, Sendable, Equatable {
    public var id: String
    public var source: String
    public var lottieWebIntent: String
    public var semanticStatus: String
    public var witness: LottieClaimWitness
    public var selectedFrames: [Double]
    public var result: LottieNumericOracleDiffResult
    public var comparisons: [LottieNumericOracleDiffComparison]
}

public struct LottieNumericOracleDiffComparison: Codable, Sendable, Equatable {
    public var fixtureID: String
    public var frame: Double
    public var field: String
    public var expectedPath: String
    public var actualPath: String
    public var expectedValue: Double
    public var actualValue: Double?
    public var toleranceID: String
    public var tolerance: Double
    public var delta: Double?
    public var witness: LottieClaimWitness
    public var result: LottieNumericOracleDiffResult
}

public enum LottieNumericOracleDiffResult: String, Codable, Sendable, Equatable {
    case pass
    case fail
}

public enum LottieNumericOracleDiffError: Error, Sendable, Equatable {
    case unknownFixture(String)
}

private extension LottieRenderFrame {
    func trimTraces(forLayerIndex layerIndex: Int) -> [LottieSourceTrimTrace] {
        nodes.flatMap { node -> [LottieSourceTrimTrace] in
            guard node.layerIndex == layerIndex, case let .shape(shape) = node.kind else {
                return []
            }
            return shape.draws.flatMap(\.trimTraces)
        }
    }
}

private extension LottieWebIntentTrace.Layer {
    var hasZeroLayerElementBounds: Bool {
        guard let bounds = layerElementBounds else {
            return false
        }
        return bounds.width == 0 && bounds.height == 0
    }
}
