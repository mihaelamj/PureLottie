import Foundation
import XCTest

final class ReferenceProvenanceLedgerTests: XCTestCase {
    func testReferenceProvenanceLedgerPinsCurrentCorpusSources() throws {
        let ledger = try ledgerContents()
        let corpusRoot = repositoryRoot().appendingPathComponent("Tests/Fixtures/LottieCorpus", isDirectory: true)

        XCTAssertTrue(ledger.contains("Raw corpus JSON files | 1016"))
        XCTAssertEqual(try jsonFiles(in: corpusRoot).count, 1016)

        for source in expectedCorpusSources {
            let sourceRoot = corpusRoot.appendingPathComponent(source.directory, isDirectory: true)
            XCTAssertEqual(try jsonFiles(in: sourceRoot).count, source.fileCount, source.directory)
            XCTAssertTrue(ledger.contains(source.url), source.url)
            XCTAssertTrue(ledger.contains(source.revision), source.revision)
            XCTAssertTrue(ledger.contains("| \(source.fileCount) |"), source.directory)
            XCTAssertTrue(ledger.contains(source.licensePath), source.licensePath)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: corpusRoot.appendingPathComponent(source.licensePath).path),
                source.licensePath
            )
        }
    }

    func testReferenceProvenanceLedgerPinsCuratedOracleCorpus() throws {
        let ledger = try ledgerContents()
        let manifest = try JSONDecoder().decode(
            [OracleManifestEntry].self,
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/oracle-fixtures.json"))
        )
        let sourceFixtures = try jsonFiles(in: repositoryRoot().appendingPathComponent("Tests/Fixtures/LottieOracle", isDirectory: true))
            .filter { $0.deletingLastPathComponent().lastPathComponent == "LottieOracle" }
        let intentFixtures = try jsonFiles(in: repositoryRoot().appendingPathComponent("Tests/Fixtures/LottieOracle/lottie-web-intent", isDirectory: true))
        let statuses = Dictionary(grouping: manifest.map(\.semanticStatus), by: { $0 }).mapValues(\.count)
        let validationStatuses = Dictionary(grouping: manifest.map(\.validation.status), by: { $0 }).mapValues(\.count)
        let roleStatuses = Dictionary(grouping: manifest.flatMap(\.evidenceRoles), by: { $0 }).mapValues(\.count)

        XCTAssertEqual(manifest.count, 31)
        XCTAssertEqual(sourceFixtures.count, manifest.count)
        XCTAssertEqual(intentFixtures.count, manifest.count)
        XCTAssertEqual(statuses["modeled"], 30)
        XCTAssertEqual(statuses["diagnosed"], 1)
        XCTAssertEqual(roleStatuses["conformance"], 30)
        XCTAssertEqual(roleStatuses["regression"], 31)
        XCTAssertEqual(roleStatuses["visual-inspection"], 31)
        XCTAssertEqual(roleStatuses["engine-divergence"], 24)
        XCTAssertEqual(roleStatuses["unsupported-feature"], 1)
        XCTAssertTrue(manifest.allSatisfy { !$0.evidenceRoles.isEmpty })
        XCTAssertTrue(manifest.allSatisfy { !$0.purpose.isEmpty })
        XCTAssertTrue(manifest.allSatisfy { entry in
            entry.coverage.contains { entry.purpose.contains($0) }
        })
        XCTAssertEqual(validationStatuses["usable"], 31)
        XCTAssertTrue(manifest.allSatisfy { $0.validation.sourceJSON == "parses" })
        XCTAssertTrue(manifest.allSatisfy { $0.validation.lottieWeb == "loads" })
        XCTAssertTrue(manifest.allSatisfy { $0.validation.numericIntent == "committed" })
        XCTAssertTrue(manifest.allSatisfy { $0.validation.referenceNonEmpty == "passed" })
        XCTAssertTrue(manifest.allSatisfy(\.validation.failureReasons.isEmpty))
        XCTAssertTrue(ledger.contains("31 source JSON files"))
        XCTAssertTrue(ledger.contains("31 JSON files in `Tests/Fixtures/LottieOracle/lottie-web-intent`"))
        XCTAssertTrue(ledger.contains("30 `modeled`, 1 `diagnosed`"))
        XCTAssertTrue(ledger.contains("30 `conformance`, 31 `regression`, 31 `visual-inspection`, 24 `engine-divergence`, 1 `unsupported-feature`"))
        XCTAssertTrue(ledger.contains("`validation.status` | `usable` for 31 fixtures"))
        XCTAssertTrue(ledger.contains("`validation.sourceJSON` | `parses` for 31 fixtures"))
        XCTAssertTrue(ledger.contains("`validation.lottieWeb` | `loads` for 31 fixtures"))
        XCTAssertTrue(ledger.contains("`validation.numericIntent` | `committed` for 31 fixtures"))
        XCTAssertTrue(ledger.contains("`validation.referenceNonEmpty` | `passed` for 31 fixtures"))
        XCTAssertTrue(ledger.contains("`validation.failureReasons` | empty for 31 fixtures"))
        XCTAssertTrue(ledger.contains("`npm --prefix Tools/LottieOracle run validate-fixtures`"))
        XCTAssertTrue(ledger.contains("lottie-web@5.13.0"))
        XCTAssertTrue(ledger.contains("Local PureLottie-authored regression fixtures tracked by Git"))
        XCTAssertTrue(ledger.contains("Repository history plus manifest path"))
    }

    func testReferenceProvenanceLedgerPinsOracleToolDependencies() throws {
        let ledger = try ledgerContents()
        let packageLock = try JSONSerialization.jsonObject(
            with: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/package-lock.json"))
        )
        guard let root = packageLock as? [String: Any],
              let packages = root["packages"] as? [String: [String: Any]]
        else {
            XCTFail("Unable to decode Tools/LottieOracle/package-lock.json packages.")
            return
        }

        for dependency in [
            ("node_modules/lottie-web", "lottie-web", "5.13.0"),
            ("node_modules/playwright", "playwright", "1.60.0"),
            ("node_modules/pngjs", "pngjs", "7.0.0"),
        ] {
            XCTAssertEqual(packages[dependency.0]?["version"] as? String, dependency.2)
            XCTAssertTrue(ledger.contains("`\(dependency.1)` | `\(dependency.2)`"), dependency.1)
        }
    }

    func testReferenceProvenanceLedgerMakesUnknownsExplicit() throws {
        let ledger = try ledgerContents()

        XCTAssertTrue(ledger.contains("## Known Unknowns"))
        XCTAssertTrue(ledger.contains("`UNKNOWN`"))
        XCTAssertTrue(ledger.contains("Package.resolved` is not committed"))
        XCTAssertTrue(ledger.contains("#58"))
        XCTAssertTrue(ledger.contains("Reference Update and Audit Workflow"))
        XCTAssertTrue(ledger.contains("Fixture Evidence Roles"))
        XCTAssertTrue(ledger.contains("Reference Provenance Schema"))
        XCTAssertTrue(ledger.contains("reference-provenance.json"))
        XCTAssertTrue(ledger.contains("20 entries"))
        XCTAssertTrue(ledger.contains("## Issue #54-#58 Completion Criteria"))
        XCTAssertTrue(ledger.contains("composable positive-rule validation"))
        XCTAssertTrue(ledger.contains("25 checked-in files including this ledger"))
        XCTAssertTrue(ledger.contains("tolerance-bound"))
        XCTAssertTrue(ledger.contains("Wider lottie-web witness corpus"))
        XCTAssertTrue(ledger.contains("5 trace files over 25 sampled frames"))
        XCTAssertTrue(ledger.contains("Reversibility Compiler Contract"))
        XCTAssertEqual(
            try regularFiles(in: repositoryRoot().appendingPathComponent("docs/lottie-format", isDirectory: true)).count,
            25
        )
    }

    func testReferenceUpdateWorkflowIsLinkedAndExecutable() throws {
        let ledger = try ledgerContents()
        let workflow = try workflowContents()

        XCTAssertTrue(ledger.contains("[Reference Update and Audit Workflow](reference-update-audit-workflow.md)"))
        XCTAssertTrue(ledger.contains("[Reversibility Compiler Contract](reversibility-compiler-contract.md)"))
        XCTAssertTrue(workflow.contains("## Reversibility Contract"))
        XCTAssertTrue(workflow.contains("docs/lottie-format/reversibility-compiler-contract.md"))
        XCTAssertTrue(workflow.contains("source fixture -> manifest entry -> generated trace -> validation -> review evidence"))
        XCTAssertTrue(workflow.contains("docs/lottie-format/reference-provenance.json"))
        XCTAssertTrue(workflow.contains("docs/lottie-format/reference-provenance-schema.md"))
        XCTAssertTrue(workflow.contains("The manifest entry"))
        XCTAssertTrue(workflow.contains("must link the fixture id to that trace"))
        XCTAssertTrue(workflow.contains("workflow review evidence must"))
        XCTAssertTrue(workflow.contains("record the command that generated or refreshed the trace"))
        XCTAssertTrue(workflow.contains("Do not modify PureLayer or PureDraw"))

        for command in [
            "npm --prefix Tools/LottieOracle ci",
            "npm --prefix Tools/LottieOracle test",
            "npm --prefix Tools/LottieOracle run validate-fixtures",
            "swift scripts/ci-model-only.swift",
            "swift test --package-path .build/ci/model-only",
            "swiftformat . --config .swiftformat",
            "swiftlint --config .swiftlint.yml --strict",
            "swift build",
            "swift test",
        ] {
            XCTAssertTrue(workflow.contains(command), command)
        }

        for script in [
            "Tools/LottieOracle/package.json",
            "Tools/LottieOracle/scripts/build-curated-corpus.mjs",
            "Tools/LottieOracle/scripts/extract-intent.mjs",
            "Tools/LottieOracle/scripts/render-reference.mjs",
            "Tools/LottieOracle/scripts/run-oracle.mjs",
            "Tools/LottieOracle/scripts/validate-fixtures.mjs",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repositoryRoot().appendingPathComponent(script).path),
                script
            )
        }

        let packageJSON = try JSONSerialization.jsonObject(
            with: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/package.json"))
        )
        guard let package = packageJSON as? [String: Any],
              let scripts = package["scripts"] as? [String: String]
        else {
            XCTFail("Unable to decode Tools/LottieOracle/package.json scripts.")
            return
        }

        XCTAssertEqual(scripts["build-corpus"], "node scripts/build-curated-corpus.mjs")
        XCTAssertEqual(scripts["extract-intent"], "node scripts/extract-intent.mjs")
        XCTAssertEqual(scripts["oracle"], "node scripts/run-oracle.mjs")
        XCTAssertEqual(scripts["render-reference"], "node scripts/render-reference.mjs")
        XCTAssertEqual(scripts["validate-fixtures"], "node scripts/validate-fixtures.mjs --check-lottie-web")
        XCTAssertEqual(scripts["test"], "node --test tests/*.test.mjs")
    }

    private func ledgerContents() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("docs/lottie-format/reference-provenance-ledger.md"),
            encoding: .utf8
        )
    }

    private func workflowContents() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("docs/lottie-format/reference-update-audit-workflow.md"),
            encoding: .utf8
        )
    }

    private func regularFiles(in root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        .sorted { $0.path < $1.path }
    }

    private func jsonFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "json" else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
        .sorted { $0.path < $1.path }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ExpectedCorpusSource {
    var directory: String
    var url: String
    var revision: String
    var fileCount: Int
    var licensePath: String
}

private let expectedCorpusSources = [
    ExpectedCorpusSource(
        directory: "airbnb-lottie-android",
        url: "https://github.com/airbnb/lottie-android",
        revision: "05ea92e",
        fileCount: 451,
        licensePath: "_licenses/airbnb-lottie-android-LICENSE"
    ),
    ExpectedCorpusSource(
        directory: "airbnb-lottie-ios",
        url: "https://github.com/airbnb/lottie-ios",
        revision: "c10b740",
        fileCount: 186,
        licensePath: "_licenses/airbnb-lottie-ios-LICENSE"
    ),
    ExpectedCorpusSource(
        directory: "Samsung-rlottie",
        url: "https://github.com/Samsung/rlottie",
        revision: "bf689b7",
        fileCount: 105,
        licensePath: "_licenses/Samsung-rlottie-COPYING"
    ),
    ExpectedCorpusSource(
        directory: "TelegramMessenger-rlottie",
        url: "https://github.com/TelegramMessenger/rlottie",
        revision: "67f103b",
        fileCount: 97,
        licensePath: "_licenses/TelegramMessenger-rlottie-COPYING"
    ),
    ExpectedCorpusSource(
        directory: "airbnb-lottie-web",
        url: "https://github.com/airbnb/lottie-web",
        revision: "bede03d",
        fileCount: 17,
        licensePath: "_licenses/airbnb-lottie-web-LICENSE.md"
    ),
    ExpectedCorpusSource(
        directory: "LottieFiles-lottie-react",
        url: "https://github.com/LottieFiles/lottie-react",
        revision: "0082d3d",
        fileCount: 1,
        licensePath: "_licenses/LottieFiles-lottie-react-LICENSE"
    ),
    ExpectedCorpusSource(
        directory: "useAnimations-react-useanimations",
        url: "https://github.com/useAnimations/react-useanimations",
        revision: "a19d6f1",
        fileCount: 79,
        licensePath: "_licenses/useAnimations-react-useanimations-LICENSE"
    ),
    ExpectedCorpusSource(
        directory: "LottieFiles-test-files",
        url: "https://github.com/LottieFiles/test-files",
        revision: "ba02545",
        fileCount: 80,
        licensePath: "_licenses/LottieFiles-test-files-LICENSE"
    ),
]

private struct OracleManifestEntry: Decodable {
    var coverage: [String]
    var evidenceRoles: [String]
    var purpose: String
    var semanticStatus: String
    var validation: FixtureValidation

    struct FixtureValidation: Decodable {
        var status: String
        var sourceJSON: String
        var lottieWeb: String
        var numericIntent: String
        var referenceNonEmpty: String
        var failureReasons: [String]
    }
}
