import Foundation
import LottieModel
import Testing

@Suite("Reference provenance manifest validation")
struct ReferenceProvenanceManifestValidationTests {
    @Test("checked-in reference provenance manifest validates")
    func checkedInReferenceProvenanceManifestValidates() throws {
        let manifest = try loadManifest()

        try manifest.validate()

        #expect(manifest.schema.name == "purelottie.reference-provenance")
        #expect(manifest.schema.version == 1)
        #expect(manifest.entries.count == 18)
        #expect(Set(manifest.entries.map(\.id)).count == manifest.entries.count)
        #expect(manifest.entries.contains { $0.id == "curated-oracle-corpus" })
        #expect(manifest.entries.contains { $0.id == "committed-lottie-web-intent-traces" })
        #expect(manifest.entries.contains { $0.id == "wider-lottie-web-witness-corpus" })
        #expect(manifest.entries.contains { $0.id == "purelayer-dependency" })
        let validationStatuses = Dictionary(grouping: manifest.entries.map(\.validation.status), by: { $0 }).mapValues(\.count)
        #expect(validationStatuses["usable"] == 15)
        #expect(validationStatuses["usable-with-unknowns"] == 3)
    }

    @Test("known fact without value and unknown fact without follow-up fail with paths")
    func factCompletenessFailuresCarryPaths() throws {
        var manifest = try loadManifest()
        manifest.entries[0].revision = .init(status: "known")
        manifest.entries[0].license = .init(status: "unknown")

        let errors = ReferenceProvenanceValidator().collectErrors(in: manifest)

        #expect(errors.map(\.codingPath.description).contains("$.entries[0].revision.value"))
        #expect(errors.map(\.codingPath.description).contains("$.entries[0].license.followUp"))
        #expect(errors.map(\.reason).contains("Failed to satisfy: Known reference provenance facts declare a value"))
        #expect(errors.map(\.reason).contains("Failed to satisfy: Unknown reference provenance facts declare a follow-up"))
    }

    @Test("incomplete provenance entry fails with entry-local paths")
    func incompleteEntryFailuresCarryEntryPaths() throws {
        var manifest = try loadManifest()
        manifest.entries[0].purpose = ""
        manifest.entries[0].classifications = []
        manifest.entries[0].source.value = ""
        manifest.entries[0].validation.evidence = []

        let errors = ReferenceProvenanceValidator().collectErrors(in: manifest)
        let paths = Set(errors.map(\.codingPath.description))

        #expect(paths.contains("$.entries[0].purpose"))
        #expect(paths.contains("$.entries[0].classifications"))
        #expect(paths.contains("$.entries[0].source.value"))
        #expect(paths.contains("$.entries[0].validation.evidence"))
        #expect(errors.allSatisfy { $0.reason.isEmpty == false })
    }

    @Test("missing provenance keys decode as validation errors with paths")
    func missingKeysDecodeAsValidationErrorsWithPaths() throws {
        let source = """
        {
          "schema": { "name": "purelottie.reference-provenance", "version": 1 },
          "entries": [
            {
              "id": "missing-purpose",
              "kind": "tool",
              "path": "Tools/LottieOracle",
              "source": { "type": "local", "value": "test source" },
              "revision": { "status": "known", "value": "test revision" },
              "license": { "status": "known", "value": "test license" },
              "classifications": ["tooling"],
              "validation": { "status": "usable", "evidence": ["unit test"] }
            }
          ]
        }
        """

        do {
            _ = try ReferenceProvenanceManifest.decodeValidated(from: Data(source.utf8))
            Issue.record("Expected missing purpose to fail validated decode.")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].ruleID == "reference.decode.key-not-found")
            #expect(errors.values[0].codingPath.description == "$.entries[0].purpose")
        }
    }

    @Test("duplicate provenance ids fail at the duplicate id path")
    func duplicateIDsFailAtDuplicatePath() throws {
        var manifest = try loadManifest()
        manifest.entries[1].id = manifest.entries[0].id

        let errors = ReferenceProvenanceValidator().collectErrors(in: manifest)

        #expect(errors.contains { error in
            error.ruleID == "reference.entry.id.unique"
                && error.codingPath.description == "$.entries[1].id"
        })
    }

    @Test("default validation set is composable and removable")
    func defaultValidationSetIsComposableAndRemovable() {
        let validator = ReferenceProvenanceValidator()
        let purposeDescription = ReferenceProvenanceBuiltinValidation.entryPurposesAreSpecific.description

        #expect(validator.validationDescriptions.contains(purposeDescription))
        #expect(
            ReferenceProvenanceValidator.blank
                .validating(\.entryPurposesAreSpecific)
                .validationDescriptions == [purposeDescription]
        )
        #expect(
            ReferenceProvenanceValidator()
                .withoutValidating(\.entryPurposesAreSpecific)
                .validationDescriptions.contains(purposeDescription) == false
        )
    }

    @Test("manifest paths that claim repository files exist")
    func manifestRepositoryPathsExist() throws {
        let root = repositoryRoot()
        for entry in try loadManifest().entries {
            #expect(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(entry.path).path),
                "\(entry.id) path does not exist: \(entry.path)"
            )
            if entry.license.status == "known", let value = entry.license.value, value.hasPrefix("Tests/") {
                #expect(
                    FileManager.default.fileExists(atPath: root.appendingPathComponent(value).path),
                    "\(entry.id) license path does not exist: \(value)"
                )
            }
        }
    }

    @Test("schema documentation names every default validation description")
    func schemaDocumentationNamesEveryDefaultValidationDescription() throws {
        let schemaDoc = try String(
            contentsOf: repositoryRoot().appendingPathComponent("docs/lottie-format/reference-provenance-schema.md"),
            encoding: .utf8
        )

        for description in ReferenceProvenanceValidator().validationDescriptions {
            #expect(schemaDoc.contains(description), "Missing validation description in schema doc: \(description)")
        }
    }

    @Test("schema documentation names every stable vocabulary value")
    func schemaDocumentationNamesEveryStableVocabularyValue() throws {
        let schemaDoc = try String(
            contentsOf: repositoryRoot().appendingPathComponent("docs/lottie-format/reference-provenance-schema.md"),
            encoding: .utf8
        )
        let vocabularies = ReferenceProvenanceBuiltinValidation.supportedKinds
            .union(ReferenceProvenanceBuiltinValidation.supportedSourceTypes)
            .union(ReferenceProvenanceBuiltinValidation.supportedFactStatuses)
            .union(ReferenceProvenanceBuiltinValidation.supportedClassifications)
            .union(ReferenceProvenanceBuiltinValidation.supportedValidationStatuses)

        for value in vocabularies {
            #expect(schemaDoc.contains("`\(value)`"), "Missing vocabulary value in schema doc: \(value)")
        }
    }

    private func loadManifest() throws -> ReferenceProvenanceManifest {
        try ReferenceProvenanceManifest.decodeValidated(
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("docs/lottie-format/reference-provenance.json"))
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
