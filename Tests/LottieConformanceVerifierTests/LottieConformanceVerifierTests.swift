import Foundation
import LottieConformanceVerifierCore
import Testing

@Suite("Lottie independent conformance verification")
struct LottieConformanceVerifierTests {
    @Test("independent verifier reproduces all conformance verdicts from committed evidence")
    func independentVerifierReproducesAllConformanceVerdicts() throws {
        let root = repositoryRoot()

        let manifestURL = root.appendingPathComponent("Tools/LottieOracle/oracle-fixtures.json")
        let tolerancesURL = root.appendingPathComponent("Tools/LottieOracle/oracle-tolerances.json")
        let reversibilityURL = root.appendingPathComponent("Tests/Fixtures/LottieOracle/reversibility-gate/report.json")
        let witnessCorpusURL = root.appendingPathComponent("Tools/LottieOracle/witness-corpus.json")
        let lottieWebIntentDir = root.appendingPathComponent("Tests/Fixtures/LottieOracle/lottie-web-intent")
        let witnessLottieWebIntentDir = root.appendingPathComponent("Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent")

        // Assert that the independent verifier runs and succeeds
        try LottieConformanceVerifier.verify(
            manifestURL: manifestURL,
            tolerancesURL: tolerancesURL,
            reversibilityURL: reversibilityURL,
            witnessCorpusURL: witnessCorpusURL,
            lottieWebIntentDir: lottieWebIntentDir,
            witnessLottieWebIntentDir: witnessLottieWebIntentDir
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
