import Foundation
import LottieImport
import LottieModel
import XCTest

final class CorpusImportSmokeTests: XCTestCase {
    func testCorpusDecodeAndImportOptIn() throws {
        guard ProcessInfo.processInfo.environment["PURELOTTIE_RUN_CORPUS_IMPORT"] == "1" else {
            throw XCTSkip("Set PURELOTTIE_RUN_CORPUS_IMPORT=1 to decode and import the full Lottie fixture corpus.")
        }

        var failures: [String] = []
        for file in try fixtureFiles() {
            do {
                let animation = try LottieAnimation.decode(from: Data(contentsOf: file))
                _ = LottieImporter().scene(from: animation)
            } catch {
                failures.append("\(relativePath(file)): \(error)")
            }
        }

        let unexpectedFailures = failures.filter { failure in
            !knownInvalidFixtures.contains { failure.hasPrefix($0) }
        }

        XCTAssertTrue(unexpectedFailures.isEmpty, unexpectedFailures.prefix(25).joined(separator: "\n"))
    }

    private func fixtureFiles() throws -> [URL] {
        let root = fixtureRoot()
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

    private func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieCorpus", isDirectory: true)
    }

    private func relativePath(_ url: URL) -> String {
        let rootPath = fixtureRoot().path + "/"
        return url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.lastPathComponent
    }

    private var knownInvalidFixtures: Set<String> {
        [
            "Samsung-rlottie/example/resource/test/repro_propertyhelper_type_confusion2.json",
        ]
    }
}
