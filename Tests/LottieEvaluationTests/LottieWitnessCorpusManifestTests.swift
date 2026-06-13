import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie witness corpus manifest")
struct LottieWitnessCorpusManifestTests {
    @Test("checked-in witness corpus manifest validates")
    func checkedInWitnessCorpusManifestValidates() throws {
        let manifest = try loadManifest()

        #expect(manifest.schema.name == "purelottie.numeric-claim-witness-corpus")
        #expect(manifest.schema.version == 1)
        #expect(manifest.entries.count == 5)
        #expect(manifest.entries.allSatisfy { $0.semanticStatus == "witnessed-reference" })
        #expect(manifest.entries.allSatisfy { $0.witness.status == .witnessed })
    }

    @Test("witness corpus traces resolve and match manifest frames")
    func witnessCorpusTracesResolveAndMatchManifestFrames() throws {
        let root = repositoryRoot()

        for entry in try loadManifest().entries {
            let sourceURL = root.appendingPathComponent("Tools/LottieOracle").appendingPathComponent(entry.lottie)
                .standardizedFileURL
            let traceURL = root.appendingPathComponent("Tools/LottieOracle").appendingPathComponent(entry.lottieWebIntent)
                .standardizedFileURL
            #expect(FileManager.default.fileExists(atPath: sourceURL.path), "\(entry.id) missing source")
            #expect(FileManager.default.fileExists(atPath: traceURL.path), "\(entry.id) missing trace")

            let trace = try LottieWebIntentTrace.decodeValidated(from: Data(contentsOf: traceURL))
            #expect(trace.source == entry.lottie)
            #expect(trace.lottieWeb.version == "5.13.0")
            #expect(trace.frames.map(\.frame) == entry.frames.map(\.frame))
        }
    }

    @Test("invalid witness corpus reports exact JSON paths")
    func invalidWitnessCorpusReportsExactJSONPaths() throws {
        var manifest = try loadManifest()
        manifest.schema.version = 2
        manifest.entries[1].id = manifest.entries[0].id
        manifest.entries[0].semanticStatus = "modeled"
        manifest.entries[0].witness.evidence = []
        manifest.entries[0].witness.reason = ""
        manifest.entries[0].frames[0].rationale = ""

        let errors = LottieWitnessCorpusManifestValidator().collectErrors(in: manifest)
        let paths = Set(errors.map(\.codingPath.description))

        #expect(paths.contains("$.schema.version"))
        #expect(paths.contains("$.entries[1].id"))
        #expect(paths.contains("$.entries[0].semanticStatus"))
        #expect(paths.contains("$.entries[0].witness.evidence"))
        #expect(paths.contains("$.entries[0].witness.reason"))
        #expect(paths.contains("$.entries[0].frames[0].rationale"))
    }

    private func loadManifest() throws -> LottieWitnessCorpusManifest {
        try LottieWitnessCorpusManifest.decodeValidated(
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/witness-corpus.json"))
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
