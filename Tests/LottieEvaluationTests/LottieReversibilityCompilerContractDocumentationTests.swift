import Foundation
import Testing

@Suite("Lottie reversibility compiler contract documentation")
struct LottieReversibilityCompilerContractDocumentationTests {
    @Test("contract links phase boundary executable gates and loss evidence")
    func contractLinksPhaseBoundaryExecutableGatesAndLossEvidence() throws {
        let contract = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("docs/lottie-format/reversibility-compiler-contract.md"),
            encoding: .utf8
        )

        for requiredText in [
            "source -> parse -> validate -> normalize/evaluate -> lower -> decompile -> source-intent",
            "PureLayer and PureDraw are target oracles",
            "PNG and APNG files are downstream inspection artifacts",
            "OpenAPIKit-style",
            "LottieSourceIntentTransformTimingRoundTripGate",
            "LottieSourceIntentReversibilityCorpusGateTests",
            "Tests/Fixtures/LottieOracle/reversibility-gate/report.json",
            "`sourcePath`",
            "`jsonPath`",
            "`phase`",
            "`owner`",
            "`ruleID`",
            "`reason`",
            "`reconstructability`",
            "#### Owner Mapping",
            "| Boundary | Owner | Evidence |",
            "target backend",
            "external oracle",
            "`missingSourceFact`",
            "`approximation`",
            "`unsupported`",
            "`intentionallyDropped`",
            "`reconstructedWithLoss`",
            "`notReconstructable`",
            "Which executable gate would fail if the claim were false?",
        ] {
            #expect(contract.contains(requiredText), "Missing contract text: \(requiredText)")
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
