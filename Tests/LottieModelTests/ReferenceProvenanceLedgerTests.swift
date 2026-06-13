import Foundation
import XCTest

final class ReferenceProvenanceLedgerTests: XCTestCase {
    func testReferenceProvenanceLedgerPinsCurrentCorpusSources() throws {
        let ledger = try ledgerContents()
        let corpusRoot = repositoryRoot().appendingPathComponent("Tests/Fixtures/LottieCorpus", isDirectory: true)

        XCTAssertTrue(ledger.contains("Raw corpus JSON files | 857"))
        XCTAssertEqual(try jsonFiles(in: corpusRoot).count, 857)

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

        XCTAssertEqual(manifest.count, 31)
        XCTAssertEqual(sourceFixtures.count, manifest.count)
        XCTAssertEqual(intentFixtures.count, manifest.count)
        XCTAssertEqual(statuses["modeled"], 30)
        XCTAssertEqual(statuses["diagnosed"], 1)
        XCTAssertTrue(ledger.contains("31 source JSON files"))
        XCTAssertTrue(ledger.contains("31 JSON files in `Tests/Fixtures/LottieOracle/lottie-web-intent`"))
        XCTAssertTrue(ledger.contains("30 `modeled`, 1 `diagnosed`"))
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
        XCTAssertTrue(ledger.contains("#56"))
        XCTAssertTrue(ledger.contains("#58"))
        XCTAssertTrue(ledger.contains("3 checked-in files before this ledger"))
    }

    private func ledgerContents() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("docs/lottie-format/reference-provenance-ledger.md"),
            encoding: .utf8
        )
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
]

private struct OracleManifestEntry: Decodable {
    var semanticStatus: String
}
