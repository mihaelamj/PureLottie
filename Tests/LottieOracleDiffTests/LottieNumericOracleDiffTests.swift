import Foundation
import LottieEvaluation
@testable import LottieOracleDiff
import Testing

@Suite("Lottie numeric oracle diff command")
struct LottieNumericOracleDiffTests {
    @Test("curated corpus numeric diff report is deterministic and passing")
    func curatedCorpusNumericDiffReportIsDeterministicAndPassing() throws {
        let differ = LottieNumericOracleDiffer()
        let report = try differ.report(manifestURL: manifestURL(), toleranceURL: toleranceURL())
        let repeated = try differ.report(manifestURL: manifestURL(), toleranceURL: toleranceURL())

        #expect(report.schema.version == 2)
        #expect(report.fixtureCount >= 30)
        #expect(report.summary.comparedFields > 100)
        #expect(report.summary.failedComparisons == 0)
        #expect(report.summary.witnessedComparisons == report.summary.comparedFields)
        #expect(report.summary.assertedComparisons == 0)
        #expect(report.summary.blockedComparisons == 0)
        #expect(report.fixtures.allSatisfy { $0.result == .pass })
        #expect(report.fixtures.allSatisfy { $0.witness.status == .witnessed })
        #expect(report.fixtures.flatMap(\.comparisons).allSatisfy { comparison in
            !comparison.expectedPath.isEmpty
                && !comparison.actualPath.isEmpty
                && !comparison.toleranceID.isEmpty
                && comparison.witness.status == .witnessed
                && comparison.witness.evidence.isEmpty == false
        })
        let encodedReport = try encoded(report)
        let encodedRepeated = try encoded(repeated)
        #expect(encodedReport == encodedRepeated)
    }

    @Test("command writes JSON and Markdown reports")
    func commandWritesJSONAndMarkdownReports() throws {
        let output = try temporaryDirectory()
        let code = try LottieNumericOracleDiffCommand.run(arguments: [
            "--fixture", "eligible-shape-position",
            "--manifest", manifestURL().path,
            "--tolerances", toleranceURL().path,
            "--output", output.path,
        ])

        #expect(code == 0)
        let jsonURL = output.appendingPathComponent("numeric-oracle-diff.json")
        let markdownURL = output.appendingPathComponent("numeric-oracle-diff.md")
        let report = try JSONDecoder().decode(
            LottieNumericOracleDiffReport.self,
            from: Data(contentsOf: jsonURL)
        )
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)

        #expect(report.schema.version == 2)
        #expect(report.fixtureCount == 1)
        #expect(report.summary.failedComparisons == 0)
        #expect(report.summary.witnessedComparisons == report.summary.comparedFields)
        #expect(markdown.contains("- Witnessed coverage: "))
        #expect(markdown.contains("| Fixture | Frame | Field | Result | Witness | Tolerance | Expected | Actual | Delta | Expected path | Actual path |"))
        #expect(markdown.contains("eligible-shape-position"))
    }

    @Test("command returns non-zero on numeric mismatches")
    func commandReturnsNonZeroOnNumericMismatches() throws {
        let directory = try temporaryDirectory()
        let intentURL = directory.appendingPathComponent("mutated-intent.json")
        var intent = try LottieWebIntentTrace.decodeValidated(
            from: Data(contentsOf: repositoryRoot()
                .appendingPathComponent("Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json"))
        )
        intent.frames[0].layers[0].opacity = 0.25
        try encoded(intent).write(to: intentURL)

        let manifestURL = directory.appendingPathComponent("oracle-fixtures.json")
        let manifest = [
            TestManifestEntry(
                id: "mutated-opacity",
                coverage: ["animated-position", "rectangle", "fill", "transform"],
                semanticStatus: "modeled",
                lottie: repositoryRoot()
                    .appendingPathComponent("Tests/Fixtures/LottieOracle/eligible-shape-position.json")
                    .path,
                lottieWebIntent: intentURL.path,
                frames: [TestManifestEntry.Frame(frame: 0, rationale: "corrupted opacity reference")]
            ),
        ]
        try encoded(manifest).write(to: manifestURL)
        let output = directory.appendingPathComponent("out")

        let code = try LottieNumericOracleDiffCommand.run(arguments: [
            "--manifest", manifestURL.path,
            "--tolerances", toleranceURL().path,
            "--output", output.path,
        ])
        let report = try JSONDecoder().decode(
            LottieNumericOracleDiffReport.self,
            from: Data(contentsOf: output.appendingPathComponent("numeric-oracle-diff.json"))
        )

        #expect(code == 1)
        #expect(report.summary.failedComparisons > 0)
        #expect(report.fixtures[0].comparisons.contains { comparison in
            comparison.field == "layer.opacity" && comparison.result == .fail
        })
    }

    @Test("numeric diff rejects counterexamples just outside each tolerance")
    func numericDiffRejectsCounterexamplesJustOutsideEachTolerance() throws {
        for counterexample in NumericCounterexample.allCases {
            try assertNumericDiffRejectsCounterexample(counterexample)
        }
    }

    private func assertNumericDiffRejectsCounterexample(_ counterexample: NumericCounterexample) throws {
        let directory = try temporaryDirectory()
        let ledger = try LottieOracleToleranceLedger.decodeValidated(from: Data(contentsOf: toleranceURL()))
        let tolerance = try ledger.tolerance(id: counterexample.toleranceID)
        #expect(tolerance.derivation.counterexampleOffset > tolerance.threshold)

        let fixture = try oracleManifestEntry(id: counterexample.fixtureID)
        let intentURL = directory.appendingPathComponent("\(counterexample.fixtureID)-mutated-intent.json")
        var intent = try LottieWebIntentTrace.decodeValidated(
            from: Data(contentsOf: url(fromOracleRootPath: fixture.lottieWebIntent))
        )
        try counterexample.mutate(&intent, by: tolerance.derivation.counterexampleOffset)
        try encoded(intent).write(to: intentURL)

        let manifestURL = directory.appendingPathComponent("oracle-fixtures.json")
        let manifest = [
            TestManifestEntry(
                id: "counterexample-\(counterexample.toleranceID)",
                coverage: fixture.coverage,
                semanticStatus: fixture.semanticStatus,
                lottie: url(fromOracleRootPath: fixture.lottie).path,
                lottieWebIntent: intentURL.path,
                frames: fixture.frames.map { TestManifestEntry.Frame(frame: $0.frame, rationale: $0.rationale) }
            ),
        ]
        try encoded(manifest).write(to: manifestURL)
        let output = directory.appendingPathComponent("out")

        let code = try LottieNumericOracleDiffCommand.run(arguments: [
            "--manifest", manifestURL.path,
            "--tolerances", toleranceURL().path,
            "--output", output.path,
        ])
        let report = try JSONDecoder().decode(
            LottieNumericOracleDiffReport.self,
            from: Data(contentsOf: output.appendingPathComponent("numeric-oracle-diff.json"))
        )

        #expect(code == 1)
        #expect(report.fixtures[0].comparisons.contains { comparison in
            comparison.toleranceID == counterexample.toleranceID
                && comparison.field == counterexample.expectedField
                && comparison.result == .fail
                && (comparison.delta ?? 0) > comparison.tolerance
        })
    }

    private func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func oracleManifestEntry(id: String) throws -> OracleFixtureEntry {
        let entries = try JSONDecoder().decode([OracleFixtureEntry].self, from: Data(contentsOf: manifestURL()))
        return try #require(entries.first { $0.id == id })
    }

    private func url(fromOracleRootPath path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: manifestURL().deletingLastPathComponent()).standardizedFileURL
    }

    private func manifestURL() -> URL {
        repositoryRoot().appendingPathComponent("Tools/LottieOracle/oracle-fixtures.json")
    }

    private func toleranceURL() -> URL {
        repositoryRoot().appendingPathComponent("Tools/LottieOracle/oracle-tolerances.json")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purelottie-numeric-diff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum NumericCounterexample: CaseIterable {
    case opacity
    case matrixTranslation
    case bounds
    case sourceFrame
    case trimSegment

    var fixtureID: String {
        switch self {
        case .opacity, .matrixTranslation, .bounds:
            "eligible-shape-position"
        case .sourceFrame:
            "precomp-static-child"
        case .trimSegment:
            "trim-ellipse-quadrant"
        }
    }

    var toleranceID: String {
        switch self {
        case .opacity:
            "opacity.unit-interval.absolute"
        case .matrixTranslation:
            "matrix.translation.css-pixel.absolute"
        case .bounds:
            "bounds.css-pixel.absolute"
        case .sourceFrame:
            "frame.source-frame.absolute"
        case .trimSegment:
            "trim.segment.unit-interval.absolute"
        }
    }

    var expectedField: String {
        switch self {
        case .opacity:
            "layer.opacity"
        case .matrixTranslation:
            "layer.translation.x"
        case .bounds:
            "composition.width"
        case .sourceFrame:
            "precomposition.renderedFrame"
        case .trimSegment:
            "trim.startFraction"
        }
    }

    func mutate(_ intent: inout LottieWebIntentTrace, by offset: Double) throws {
        let frameIndex = try #require(intent.frames.indices.first)
        switch self {
        case .opacity:
            let layerIndex = try #require(intent.frames[frameIndex].layers.indices.first)
            intent.frames[frameIndex].layers[layerIndex].opacity -= offset
        case .matrixTranslation:
            let layerIndex = try #require(intent.frames[frameIndex].layers.indices.first)
            #expect(intent.frames[frameIndex].layers[layerIndex].matrix.indices.contains(12))
            intent.frames[frameIndex].layers[layerIndex].matrix[12] += offset
        case .bounds:
            intent.width += offset
        case .sourceFrame:
            let precompositionIndex = try #require(intent.frames[frameIndex].precompositions.indices.first)
            let renderedFrame = try #require(intent.frames[frameIndex].precompositions[precompositionIndex].renderedFrame)
            intent.frames[frameIndex].precompositions[precompositionIndex].renderedFrame = renderedFrame + offset
        case .trimSegment:
            let trimIndex = try #require(intent.frames[frameIndex].trims.indices.first)
            intent.frames[frameIndex].trims[trimIndex].startFraction += offset
        }
    }
}

private struct OracleFixtureEntry: Decodable {
    var id: String
    var coverage: [String]
    var semanticStatus: String
    var lottie: String
    var lottieWebIntent: String
    var frames: [Frame]

    struct Frame: Decodable {
        var frame: Double
        var rationale: String
    }
}

private struct TestManifestEntry: Encodable {
    var id: String
    var coverage: [String]
    var semanticStatus: String
    var lottie: String
    var lottieWebIntent: String
    var frames: [Frame]

    struct Frame: Encodable {
        var frame: Double
        var rationale: String
    }
}
