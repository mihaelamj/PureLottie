import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie reference divergence ledger")
struct LottieReferenceDivergenceLedgerTests {
    @Test("checked-in reference divergence ledger validates")
    func checkedInReferenceDivergenceLedgerValidates() throws {
        let ledger = try loadLedger()
        let ids = Set(ledger.divergences.map(\.id))

        #expect(ledger.schema.name == "purelottie.reference-divergences")
        #expect(ledger.schema.version == 1)
        #expect(ledger.divergences.count == 17)
        #expect(ids.count == ledger.divergences.count)
        #expect(ids.contains("transform.layer-position-sampled-matrix"))
        #expect(ids.contains("trim.length-normalized-segments"))
        #expect(ids.contains("precomp.time-remap-diagnosed-boundary"))
        #expect(ledger.divergences.allSatisfy { $0.witness.status == .witnessed })
        #expect(ledger.divergences.allSatisfy { $0.witness.evidence.isEmpty == false })
    }

    @Test("engine divergence fixtures link to ledger-backed facts")
    func engineDivergenceFixturesLinkToLedgerBackedFacts() throws {
        let ledger = try loadLedger()
        let ledgerIDs = Set(ledger.divergences.map(\.id))
        let manifest = try loadManifest()
        let manifestIDs = Set(manifest.map(\.id))
        let engineDivergenceFixtures = manifest.filter { $0.evidenceRoles.contains("engine-divergence") }
        let referencedFixtures = Set(ledger.divergences.flatMap(\.fixtures))

        #expect(engineDivergenceFixtures.count == 24)
        #expect(Set(engineDivergenceFixtures.map(\.id)).isSubset(of: referencedFixtures))

        for entry in engineDivergenceFixtures {
            let ids = try #require(entry.divergenceIDs, "\(entry.id) lacks divergenceIDs")
            #expect(ids.isEmpty == false, "\(entry.id) lacks ledger-backed reasons")
            for id in ids {
                #expect(ledgerIDs.contains(id), "\(entry.id) references unknown divergence id \(id)")
                let divergence = try ledger.divergence(id: id)
                #expect(divergence.fixtures.contains(entry.id), "\(id) does not back-reference \(entry.id)")
            }
        }

        for divergence in ledger.divergences {
            for fixtureID in divergence.fixtures {
                #expect(manifestIDs.contains(fixtureID), "\(divergence.id) references unknown fixture \(fixtureID)")
                let entry = try #require(manifest.first { $0.id == fixtureID })
                #expect(entry.evidenceRoles.contains("engine-divergence"), "\(fixtureID) is not tagged engine-divergence")
                #expect(entry.divergenceIDs?.contains(divergence.id) == true, "\(fixtureID) does not link back to \(divergence.id)")
            }
        }
    }

    @Test("source pointers and comparison evidence resolve to repository files")
    func sourcePointersAndComparisonEvidenceResolveToRepositoryFiles() throws {
        let root = repositoryRoot()

        for divergence in try loadLedger().divergences {
            for evidence in divergence.comparisonEvidence {
                #expect(fileExists(root.appendingPathComponent(evidence)), "\(divergence.id) missing evidence path \(evidence)")
            }
            for evidence in divergence.witness.evidence {
                #expect(fileExists(root.appendingPathComponent(evidence)), "\(divergence.id) missing witness evidence \(evidence)")
            }
            for pointer in divergence.sourcePointers {
                #expect(
                    LottieReferenceDivergenceBuiltinValidation.supportedSourcePointerKinds.contains(pointer.kind),
                    "\(divergence.id) has unknown pointer kind \(pointer.kind)"
                )
                #expect(fileExists(root.appendingPathComponent(pointer.path)), "\(divergence.id) missing source pointer \(pointer.path)")
            }
        }
    }

    @Test("invalid reference divergence ledger reports exact JSON paths")
    func invalidReferenceDivergenceLedgerReportsExactJSONPaths() throws {
        var ledger = try loadLedger()
        ledger.schema.version = 2
        ledger.divergences[1].id = ledger.divergences[0].id
        ledger.divergences[0].status = "guess"
        ledger.divergences[0].sourcePointers[0].kind = "blog"
        ledger.divergences[0].sourcePointers[0].path = ""
        ledger.divergences[0].sourcePointers[0].note = ""
        ledger.divergences[0].witness.evidence = []
        ledger.divergences[0].witness.reason = ""

        let errors = LottieReferenceDivergenceLedgerValidator().collectErrors(in: ledger)
        let paths = Set(errors.map(\.codingPath.description))

        #expect(paths.contains("$.schema.version"))
        #expect(paths.contains("$.divergences[1].id"))
        #expect(paths.contains("$.divergences[0].status"))
        #expect(paths.contains("$.divergences[0].sourcePointers[0].kind"))
        #expect(paths.contains("$.divergences[0].sourcePointers[0].path"))
        #expect(paths.contains("$.divergences[0].sourcePointers[0].note"))
        #expect(paths.contains("$.divergences[0].witness.evidence"))
        #expect(paths.contains("$.divergences[0].witness.reason"))
    }

    @Test("missing reference divergence keys decode as validation errors with paths")
    func missingReferenceDivergenceKeysDecodeAsValidationErrorsWithPaths() throws {
        let source = """
        {
          "schema": { "name": "purelottie.reference-divergences", "version": 1 },
          "divergences": [
            {
              "id": "missing-title",
              "status": "measured",
              "engines": ["lottie-web"],
              "affectedFields": ["ks.p"],
              "fixtures": ["eligible-shape-position"],
              "observedBehavior": "This text is long enough to pass semantic validation when the typed decode succeeds.",
              "comparisonEvidence": ["Tests/Fixtures/LottieOracle/eligible-shape-position.json"],
              "sourcePointers": [
                {
                  "kind": "fixture",
                  "path": "Tests/Fixtures/LottieOracle/eligible-shape-position.json",
                  "note": "Fixture source document used by this divergence."
                }
              ]
            }
          ]
        }
        """

        do {
            _ = try LottieReferenceDivergenceLedger.decodeValidated(from: Data(source.utf8))
            Issue.record("Expected missing title to fail validated decode.")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].ruleID == "reference-divergence.decode.key-not-found")
            #expect(errors.values[0].codingPath.description == "$.divergences[0].title")
        }
    }

    @Test("default reference divergence validation set is composable and removable")
    func defaultReferenceDivergenceValidationSetIsComposableAndRemovable() {
        let validator = LottieReferenceDivergenceLedgerValidator()
        let schemaDescription = LottieReferenceDivergenceBuiltinValidation.schemaNameAndVersionAreSupported.description

        #expect(validator.validationDescriptions.contains(schemaDescription))
        #expect(
            LottieReferenceDivergenceLedgerValidator.blank
                .validating(LottieReferenceDivergenceBuiltinValidation.schemaNameAndVersionAreSupported)
                .validationDescriptions == [schemaDescription]
        )
        #expect(
            LottieReferenceDivergenceLedgerValidator()
                .withoutValidating(schemaDescription)
                .validationDescriptions.contains(schemaDescription) == false
        )
    }

    private func loadLedger() throws -> LottieReferenceDivergenceLedger {
        try LottieReferenceDivergenceLedger.decodeValidated(
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/reference-divergences.json"))
        )
    }

    private func loadManifest() throws -> [DivergenceFixtureManifestEntry] {
        try JSONDecoder().decode(
            [DivergenceFixtureManifestEntry].self,
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/oracle-fixtures.json"))
        )
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct DivergenceFixtureManifestEntry: Decodable {
    var id: String
    var evidenceRoles: [String]
    var divergenceIDs: [String]?
}
