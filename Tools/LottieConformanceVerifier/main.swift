import Foundation
import LottieConformanceVerifierCore

do {
    let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    let manifestURL = workingDirectory.appendingPathComponent("Tools/LottieOracle/oracle-fixtures.json")
    let tolerancesURL = workingDirectory.appendingPathComponent("Tools/LottieOracle/oracle-tolerances.json")
    let reversibilityURL = workingDirectory.appendingPathComponent("Tests/Fixtures/LottieOracle/reversibility-gate/report.json")
    let witnessCorpusURL = workingDirectory.appendingPathComponent("Tools/LottieOracle/witness-corpus.json")
    let lottieWebIntentDir = workingDirectory.appendingPathComponent("Tests/Fixtures/LottieOracle/lottie-web-intent")
    let witnessLottieWebIntentDir = workingDirectory.appendingPathComponent("Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent")

    print("Starting independent conformance verifier...")
    print("Manifest: \(manifestURL.path)")
    print("Tolerances: \(tolerancesURL.path)")
    print("Reversibility Report: \(reversibilityURL.path)")
    print("Witness Corpus: \(witnessCorpusURL.path)")

    try LottieConformanceVerifier.verify(
        manifestURL: manifestURL,
        tolerancesURL: tolerancesURL,
        reversibilityURL: reversibilityURL,
        witnessCorpusURL: witnessCorpusURL,
        lottieWebIntentDir: lottieWebIntentDir,
        witnessLottieWebIntentDir: witnessLottieWebIntentDir
    )

    print("✅ Conformance verification passed successfully! All claims matched.")
    exit(0)
} catch {
    print("❌ Conformance verification FAILED:")
    print(error)
    exit(1)
}
