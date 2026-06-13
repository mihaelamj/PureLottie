import Foundation
import Testing

/// Loss-contract completeness and measured-count drift guard (issue #141, epic #137).
///
/// The reversibility contract doc records ten "MEASURED" counts, each with a jq
/// command to re-derive it from the reversibility report. Those were manual
/// measurements stamped with a date; nothing re-ran them. This test turns them
/// into a live drift guard: it re-derives each count from the committed
/// report.json and fails if the contract doc does not state that exact number
/// (so the report and the doc cannot drift apart silently), and it asserts the
/// loss-taxonomy completeness invariant: every reversibility fixture is
/// classified exactly once as exact or recorded-loss, with zero unrecorded
/// mismatches. "Loss is explicit" (Law 2) is thereby a checked theorem, not a
/// stamped measurement.
///
/// The numeric *bound* on the genuinely sampled approximations (spatial arc
/// length 150 vs 200, the easing reparameterization) is the remaining #141 work
/// and is not claimed here.
@Suite("Lottie loss contract")
struct LottieLossContractTests {
    struct ReversibilityReport: Decodable {
        var fixtureCount: Int
        var selectedFrameCount: Int
        var excludedFixtureCount: Int
        var exactFixtureCount: Int
        var recordedLossFixtureCount: Int
        var findingCount: Int
        var lossCount: Int
        var reconstructedFactCount: Int
        var sourcePathCount: Int
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func report() throws -> ReversibilityReport {
        let url = repositoryRoot().appendingPathComponent("Tests/Fixtures/LottieOracle/reversibility-gate/report.json")
        return try JSONDecoder().decode(ReversibilityReport.self, from: Data(contentsOf: url))
    }

    private func contractDoc() throws -> String {
        let url = repositoryRoot().appendingPathComponent("docs/lottie-format/reversibility-compiler-contract.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("contract doc states every measured count derived live from the report")
    func contractMeasuredCountsMatchReport() throws {
        let report = try report()
        let doc = try contractDoc()
        let rows: [(String, Int)] = [
            ("Reversibility fixture count", report.fixtureCount),
            ("Reversibility selected frame count", report.selectedFrameCount),
            ("Reversibility exclusions", report.excludedFixtureCount),
            ("Exact fixtures", report.exactFixtureCount),
            ("Fixtures with recorded loss", report.recordedLossFixtureCount),
            ("Unrecorded source-intent mismatches", report.findingCount),
            ("Path-bearing loss records", report.lossCount),
            ("Reconstructed facts", report.reconstructedFactCount),
            ("Unique source paths in reversibility report", report.sourcePathCount),
        ]
        for (label, value) in rows {
            #expect(
                doc.contains("| \(label) | \(value) |"),
                "contract doc must state the live measured count: | \(label) | \(value) |"
            )
        }
    }

    @Test("loss taxonomy is complete: every fixture is exact xor recorded-loss, no unrecorded mismatch")
    func lossTaxonomyIsComplete() throws {
        let report = try report()
        #expect(
            report.exactFixtureCount + report.recordedLossFixtureCount == report.fixtureCount,
            "every fixture must be classified exactly once: \(report.exactFixtureCount) exact + \(report.recordedLossFixtureCount) loss != \(report.fixtureCount)"
        )
        #expect(report.excludedFixtureCount == 0, "no fixture may be excluded from the loss taxonomy")
        #expect(report.findingCount == 0, "an unrecorded source-intent mismatch is a dropped render fact (Law 2 violation)")
    }
}
