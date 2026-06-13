import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie oracle tolerance ledger")
struct LottieOracleToleranceLedgerTests {
    @Test("checked-in oracle tolerance ledger validates")
    func checkedInOracleToleranceLedgerValidates() throws {
        let ledger = try loadLedger()
        let ids = Set(ledger.tolerances.map(\.id))

        #expect(ledger.schema.version == 2)
        #expect(ids == LottieOracleToleranceBuiltinValidation.requiredToleranceIDs)
        #expect(try ledger.threshold(id: "opacity.unit-interval.absolute") == 0.000_000_000_001)
        #expect(try ledger.threshold(id: "matrix.translation.css-pixel.absolute") == 0.000_003_814_697_265_625)
        #expect(try ledger.threshold(id: "frame.source-frame.absolute") == 0.000_000_000_001)
        #expect(try ledger.threshold(id: "bounds.css-pixel.absolute") == 0.000_01)
        #expect(try ledger.threshold(id: "path-length.css-pixel.absolute") == 0.000_001)
        #expect(try ledger.threshold(id: "trim.segment.unit-interval.absolute") == 0.000_000_000_001)
        #expect(try ledger.threshold(id: "pixel.max-channel.exact") == 0)
        #expect(ledger.tolerances.filter { $0.derivation.status == .derived }.count == 5)
        #expect(ledger.tolerances.filter { $0.derivation.status == .assumed }.count == 2)
        #expect(ledger.tolerances.allSatisfy { $0.derivation.counterexampleOffset > $0.threshold })
        #expect(ledger.tolerances.allSatisfy { tolerance in
            tolerance.derivation.status == .derived
                ? tolerance.threshold == tolerance.derivation.derivedBound
                : tolerance.derivation.assumption?.isEmpty == false
        })
        #expect(ledger.tolerances.allSatisfy { tolerance in
            tolerance.derivation.status == .derived
                ? tolerance.witness.status == .witnessed
                : tolerance.witness.status == .asserted
        })
    }

    @Test("invalid oracle tolerance ledger reports exact JSON paths")
    func invalidOracleToleranceLedgerReportsExactJSONPaths() throws {
        var ledger = try loadLedger()
        ledger.schema.version = 1
        ledger.tolerances[0].unit = "screenGuess"
        ledger.tolerances[0].threshold = -1
        ledger.tolerances[0].reason = ""
        ledger.tolerances[0].derivation.arithmeticModel = ""
        ledger.tolerances[0].derivation.derivedBound = Double.nan
        ledger.tolerances[0].derivation.formula = ""
        ledger.tolerances[0].derivation.proof = ""
        ledger.tolerances[0].derivation.evidence = [""]
        ledger.tolerances[0].derivation.counterexampleOffset = -1
        ledger.tolerances[0].witness.reason = ""

        let errors = LottieOracleToleranceLedgerValidator().collectErrors(in: ledger)
        let paths = Set(errors.map(\.codingPath.description))

        #expect(paths.contains("$.schema.version"))
        #expect(paths.contains("$.tolerances[0].unit"))
        #expect(paths.contains("$.tolerances[0].threshold"))
        #expect(paths.contains("$.tolerances[0].reason"))
        #expect(paths.contains("$.tolerances[0].derivation.arithmeticModel"))
        #expect(paths.contains("$.tolerances[0].derivation.derivedBound"))
        #expect(paths.contains("$.tolerances[0].derivation.formula"))
        #expect(paths.contains("$.tolerances[0].derivation.proof"))
        #expect(paths.contains("$.tolerances[0].derivation.evidence"))
        #expect(paths.contains("$.tolerances[0].derivation.counterexampleOffset"))
        #expect(paths.contains("$.tolerances[0].witness.reason"))
    }

    @Test("missing oracle tolerance lookup fails")
    func missingOracleToleranceLookupFails() throws {
        do {
            _ = try loadLedger().threshold(id: "missing")
            Issue.record("Expected missing tolerance id to throw.")
        } catch LottieOracleToleranceLookupError.missing("missing") {
            return
        } catch {
            Issue.record("Expected missing tolerance error, got \(error).")
        }
    }

    @Test("oracle comparison tests reference tolerance ids")
    func oracleComparisonTestsReferenceToleranceIDs() throws {
        let source = try [
            "Tests/LottieEvaluationTests/LottieWebIntentOracleTests.swift",
            "Tests/LottieEvaluationTests/LottieOracleCorpusTests.swift",
            "Tests/LottieImportTests/LottieAPNGExportTests.swift",
            "Tests/LottieImportTests/LottieLoweringSourceIntentGateTests.swift",
            "Sources/LottieOracleDiff/LottieNumericOracleDiff.swift",
        ]
        .map { try String(contentsOf: repositoryRoot().appendingPathComponent($0), encoding: .utf8) }
        .joined(separator: "\n")

        for id in [
            "bounds.css-pixel.absolute",
            "frame.source-frame.absolute",
            "matrix.translation.css-pixel.absolute",
            "opacity.unit-interval.absolute",
            "path-length.css-pixel.absolute",
            "trim.segment.unit-interval.absolute",
        ] {
            #expect(source.contains(id), "Missing tolerance id \(id)")
        }
        #expect(source.contains("tolerance: 0.05") == false)
    }

    private func loadLedger() throws -> LottieOracleToleranceLedger {
        try LottieOracleToleranceLedger.decodeValidated(
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/oracle-tolerances.json"))
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
