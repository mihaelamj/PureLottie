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

        #expect(report.fixtureCount >= 30)
        #expect(report.summary.comparedFields > 100)
        #expect(report.summary.failedComparisons == 0)
        #expect(report.fixtures.allSatisfy { $0.result == .pass })
        #expect(report.fixtures.flatMap(\.comparisons).allSatisfy { comparison in
            !comparison.expectedPath.isEmpty
                && !comparison.actualPath.isEmpty
                && !comparison.toleranceID.isEmpty
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

        #expect(report.fixtureCount == 1)
        #expect(report.summary.failedComparisons == 0)
        #expect(markdown.contains("| Fixture | Frame | Field | Result | Tolerance | Expected | Actual | Delta | Expected path | Actual path |"))
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

    private func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
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
