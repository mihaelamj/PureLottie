import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie oracle corpus")
struct LottieOracleCorpusTests {
    @Test("curated corpus manifest has at least thirty vetted fixtures")
    func curatedCorpusManifestHasAtLeastThirtyVettedFixtures() throws {
        let manifest = try loadManifest()

        #expect(manifest.count >= 30)
        #expect(Set(manifest.map(\.id)).count == manifest.count)
        #expect(manifest.allSatisfy { !$0.coverage.isEmpty })
        #expect(manifest.allSatisfy { !$0.evidenceRoles.isEmpty })
        #expect(manifest.allSatisfy { !$0.purpose.isEmpty })
        #expect(manifest.allSatisfy { entry in
            entry.coverage.contains { entry.purpose.contains($0) }
        })
        #expect(manifest.allSatisfy { $0.frames.count >= 3 })
        #expect(manifest.allSatisfy { $0.validation.status == "usable" })
        #expect(manifest.allSatisfy { $0.validation.sourceJSON == "parses" })
        #expect(manifest.allSatisfy { $0.validation.lottieWeb == "loads" })
        #expect(manifest.allSatisfy { $0.validation.numericIntent == "committed" })
        #expect(manifest.allSatisfy { $0.validation.referenceNonEmpty == "passed" })
        let entriesWithValidationFailures = manifest.filter { !$0.validation.failureReasons.isEmpty }
        #expect(entriesWithValidationFailures.isEmpty)

        let coverage = Set(manifest.flatMap(\.coverage))
        let evidenceRoles = Set(manifest.flatMap(\.evidenceRoles))
        let allowedEvidenceRoles: Set = [
            "conformance",
            "regression",
            "unsupported-feature",
            "visual-inspection",
            "engine-divergence",
        ]
        #expect(evidenceRoles == allowedEvidenceRoles)
        for entry in manifest {
            #expect(Set(entry.evidenceRoles).isSubset(of: allowedEvidenceRoles), "\(entry.id) has an unknown evidence role")
            if entry.semanticStatus == .modeled {
                #expect(entry.evidenceRoles.contains("conformance"), "\(entry.id) must carry conformance evidence")
            }
            if entry.semanticStatus == .diagnosed {
                #expect(entry.evidenceRoles.contains("unsupported-feature"), "\(entry.id) must carry unsupported-feature evidence")
            }
        }
        for required in [
            "animated-position",
            "anchor",
            "scale",
            "rotation",
            "parent-transform",
            "ellipse",
            "rectangle",
            "path",
            "polygon",
            "star",
            "fill",
            "stroke",
            "trim",
            "mask",
            "matte",
            "precomp",
            "time-remap",
        ] {
            #expect(coverage.contains(required), "Missing corpus coverage family: \(required)")
        }
    }

    @Test("every corpus fixture has a committed lottie-web numeric intent snapshot")
    func everyCorpusFixtureHasCommittedLottieWebNumericIntentSnapshot() throws {
        for entry in try loadManifest() {
            let sourceURL = url(fromOracleRootPath: entry.lottie)
            let intentURL = url(fromOracleRootPath: entry.lottieWebIntent)
            let source = try LottieAnimation.decode(from: Data(contentsOf: sourceURL))
            let intent = try JSONDecoder().decode(
                CorpusLottieWebIntentTrace.self,
                from: Data(contentsOf: intentURL)
            )

            #expect(intent.schema.name == "purelottie.lottie-web-intent")
            #expect(intent.schema.version == 1)
            #expect(intent.source == entry.lottie)
            #expect(intent.renderer == entry.renderer)
            #expect(intent.lottieWeb.version == "5.13.0")
            #expect(intent.width == source.width)
            #expect(intent.height == source.height)
            #expect(intent.frames.map(\.frame) == entry.frames.map(\.frame))
            #expect(intent.frames.contains { $0.pathCount > 0 })
        }
    }

    @Test("corpus snapshots line up with RenderIR root layer facts")
    func corpusSnapshotsLineUpWithRenderIRRootLayerFacts() throws {
        for entry in try loadManifest() {
            let animation = try LottieAnimation.decode(from: Data(contentsOf: url(fromOracleRootPath: entry.lottie)))
            let intent = try JSONDecoder().decode(
                CorpusLottieWebIntentTrace.self,
                from: Data(contentsOf: url(fromOracleRootPath: entry.lottieWebIntent))
            )
            let builder = LottieRenderIRBuilder(animation: animation)

            for webFrame in intent.frames {
                let renderFrame = builder.frame(at: webFrame.frame)
                #expect(renderFrame.width == intent.width)
                #expect(renderFrame.height == intent.height)
                #expect(renderFrame.nodes.isEmpty == false)
                #expect(webFrame.pathCount > 0)

                if entry.semanticStatus == .modeled {
                    #expect(renderFrame.diagnostics.isEmpty, "\(entry.id) frame \(webFrame.frame) emitted diagnostics")
                }

                for node in renderFrame.nodes {
                    guard let webLayer = webFrame.layers.first(where: { $0.name == node.layerName }) else {
                        continue
                    }
                    expectClose(webLayer.opacity, node.opacity, tolerance: 0.000_001)
                    if entry.hasDirectTranslationComparison, webLayer.matrix.indices.contains(13) {
                        expectClose(webLayer.matrix[12], node.transform.worldMatrix.values[12], tolerance: 0.05)
                        expectClose(webLayer.matrix[13], node.transform.worldMatrix.values[13], tolerance: 0.05)
                    }
                }
            }
        }
    }

    private func loadManifest() throws -> [CorpusFixtureManifestEntry] {
        try JSONDecoder().decode(
            [CorpusFixtureManifestEntry].self,
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/oracle-fixtures.json"))
        )
    }

    private func url(fromOracleRootPath path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: repositoryRoot().appendingPathComponent("Tools/LottieOracle", isDirectory: true))
            .standardizedFileURL
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double) {
        #expect(abs(actual - expected) <= tolerance)
    }
}

private struct CorpusFixtureManifestEntry: Decodable {
    var id: String
    var coverage: [String]
    var evidenceRoles: [String]
    var purpose: String
    var semanticStatus: SemanticStatus
    var lottie: String
    var lottieWebIntent: String
    var renderer: String
    var frames: [Frame]
    var validation: FixtureValidation

    struct Frame: Decodable {
        var frame: Double
    }

    struct FixtureValidation: Decodable {
        var status: String
        var sourceJSON: String
        var lottieWeb: String
        var numericIntent: String
        var referenceNonEmpty: String
        var failureReasons: [String]
    }

    enum SemanticStatus: String, Decodable {
        case modeled
        case diagnosed
    }

    var hasDirectTranslationComparison: Bool {
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
}

private struct CorpusLottieWebIntentTrace: Decodable {
    var schema: Schema
    var source: String
    var renderer: String
    var lottieWeb: LottieWeb
    var width: Double
    var height: Double
    var frames: [Frame]

    struct Schema: Decodable {
        var name: String
        var version: Int
    }

    struct LottieWeb: Decodable {
        var version: String
    }

    struct Frame: Decodable {
        var frame: Double
        var pathCount: Int
        var layers: [Layer]
    }

    struct Layer: Decodable {
        var name: String
        var opacity: Double
        var matrix: [Double]
    }
}
