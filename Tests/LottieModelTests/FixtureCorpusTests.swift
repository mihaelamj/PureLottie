import Foundation
import XCTest

final class FixtureCorpusTests: XCTestCase {
    func testFixtureCorpusContainsLargeSet() throws {
        let files = try fixtureFiles()

        XCTAssertGreaterThanOrEqual(files.count, 800)
    }

    func testFixtureCorpusFilesAreLottieDocuments() throws {
        for file in try fixtureFiles() {
            let data = try Data(contentsOf: file)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let document = object as? [String: Any] else {
                XCTFail("\(relativePath(file)) is not a JSON object")
                continue
            }

            for key in ["v", "fr", "ip", "op", "w", "h", "layers"] {
                XCTAssertNotNil(document[key], "\(relativePath(file)) missing root key \(key)")
            }
        }
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
}
