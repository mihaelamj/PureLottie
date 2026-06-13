import Foundation

public struct ReferenceProvenanceManifest: Codable, Equatable, Sendable, Validatable {
    public var schema: Schema
    public var entries: [Entry]

    public init(schema: Schema, entries: [Entry]) {
        self.schema = schema
        self.entries = entries
    }

    public struct Schema: Codable, Equatable, Sendable, Validatable {
        public var name: String
        public var version: Int

        public init(name: String, version: Int) {
            self.name = name
            self.version = version
        }
    }

    public struct Entry: Codable, Equatable, Sendable, Validatable {
        public var id: String
        public var kind: String
        public var path: String
        public var source: Source
        public var revision: Fact
        public var license: Fact
        public var purpose: String
        public var classifications: [String]
        public var validation: ValidationRecord
        public var measurements: [String: Int]?

        public init(
            id: String,
            kind: String,
            path: String,
            source: Source,
            revision: Fact,
            license: Fact,
            purpose: String,
            classifications: [String],
            validation: ValidationRecord,
            measurements: [String: Int]? = nil
        ) {
            self.id = id
            self.kind = kind
            self.path = path
            self.source = source
            self.revision = revision
            self.license = license
            self.purpose = purpose
            self.classifications = classifications
            self.validation = validation
            self.measurements = measurements
        }
    }

    public struct Source: Codable, Equatable, Sendable, Validatable {
        public var type: String
        public var value: String

        public init(type: String, value: String) {
            self.type = type
            self.value = value
        }
    }

    public struct Fact: Codable, Equatable, Sendable, Validatable {
        public var status: String
        public var value: String?
        public var followUp: String?

        public init(status: String, value: String? = nil, followUp: String? = nil) {
            self.status = status
            self.value = value
            self.followUp = followUp
        }
    }

    public struct ValidationRecord: Codable, Equatable, Sendable, Validatable {
        public var status: String
        public var evidence: [String]

        public init(status: String, evidence: [String]) {
            self.status = status
            self.evidence = evidence
        }
    }
}

public final class ReferenceProvenanceValidator {
    private var defaultValidations: [AnyValidation<ReferenceProvenanceManifest>]
    private var customValidations: [AnyValidation<ReferenceProvenanceManifest>]

    public init() {
        defaultValidations = ReferenceProvenanceBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [AnyValidation<ReferenceProvenanceManifest>],
        customValidations: [AnyValidation<ReferenceProvenanceManifest>]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: ReferenceProvenanceValidator {
        ReferenceProvenanceValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<ReferenceProvenanceManifest, some Validatable>) -> Self {
        customValidations.append(AnyValidation(validation))
        return self
    }

    @discardableResult
    public func validating(
        _ validation: KeyPath<ReferenceProvenanceBuiltinValidation.Type, Validation<ReferenceProvenanceManifest, some Validatable>>
    ) -> Self {
        validating(ReferenceProvenanceBuiltinValidation.self[keyPath: validation])
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    @discardableResult
    public func withoutValidating(
        _ validation: KeyPath<ReferenceProvenanceBuiltinValidation.Type, Validation<ReferenceProvenanceManifest, some Validatable>>
    ) -> Self {
        withoutValidating(ReferenceProvenanceBuiltinValidation.self[keyPath: validation].description)
    }

    public func validate(_ manifest: ReferenceProvenanceManifest) throws {
        let errors = collectErrors(in: manifest)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    public func collectErrors(in manifest: ReferenceProvenanceManifest) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(manifest, at: JSONPath(), in: manifest, errors: &errors)
        visit(manifest.schema, at: JSONPath([.key("schema")]), in: manifest, errors: &errors)
        for index in manifest.entries.indices {
            let entry = manifest.entries[index]
            let entryPath = JSONPath([.key("entries"), .index(index)])
            visit(entry, at: entryPath, in: manifest, errors: &errors)
            visit(entry.source, at: entryPath.appending(.key("source")), in: manifest, errors: &errors)
            visit(entry.revision, at: entryPath.appending(.key("revision")), in: manifest, errors: &errors)
            visit(entry.license, at: entryPath.appending(.key("license")), in: manifest, errors: &errors)
            visit(entry.validation, at: entryPath.appending(.key("validation")), in: manifest, errors: &errors)
        }
        return errors
    }

    private var activeValidations: [AnyValidation<ReferenceProvenanceManifest>] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in manifest: ReferenceProvenanceManifest,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: manifest))
        }
    }
}

public extension ReferenceProvenanceManifest {
    static func decodeValidated(
        from data: Data,
        using validator: ReferenceProvenanceValidator = ReferenceProvenanceValidator()
    ) throws -> ReferenceProvenanceManifest {
        do {
            return try JSONDecoder().decode(ReferenceProvenanceManifest.self, from: data)
                .validate(using: validator)
        } catch let errors as ValidationErrorCollection {
            throw errors
        } catch let error as DecodingError {
            throw ValidationErrorCollection([Self.validationError(from: error)])
        }
    }

    @discardableResult
    func validate(using validator: ReferenceProvenanceValidator = ReferenceProvenanceValidator()) throws -> Self {
        try validator.validate(self)
        return self
    }

    private static func validationError(from error: DecodingError) -> ValidationError {
        switch error {
        case let .keyNotFound(key, context):
            return ValidationError(
                ruleID: "reference.decode.key-not-found",
                reason: "Failed to satisfy: Reference provenance manifest decodes as the typed schema",
                at: jsonPath(from: context.codingPath).appending(codingComponent(from: key)),
                phase: .parse,
                classification: .gap,
                evidence: context.debugDescription
            )
        case let .typeMismatch(_, context):
            return decodingError(context: context)
        case let .valueNotFound(_, context):
            return decodingError(context: context)
        case let .dataCorrupted(context):
            return decodingError(context: context)
        @unknown default:
            return ValidationError(
                ruleID: "reference.decode.unknown",
                reason: "Failed to satisfy: Reference provenance manifest decodes as the typed schema",
                at: JSONPath(),
                phase: .parse,
                classification: .gap
            )
        }
    }

    private static func decodingError(context: DecodingError.Context) -> ValidationError {
        ValidationError(
            ruleID: "reference.decode",
            reason: "Failed to satisfy: Reference provenance manifest decodes as the typed schema",
            at: jsonPath(from: context.codingPath),
            phase: .parse,
            classification: .gap,
            evidence: context.debugDescription
        )
    }

    private static func jsonPath(from codingPath: [any CodingKey]) -> JSONPath {
        JSONPath(codingPath.map(codingComponent(from:)))
    }

    private static func codingComponent(from key: any CodingKey) -> JSONPath.Component {
        if let index = key.intValue {
            return .index(index)
        }
        return .key(key.stringValue)
    }
}

public enum ReferenceProvenanceBuiltinValidation {
    static var defaultValidations: [AnyValidation<ReferenceProvenanceManifest>] {
        [
            AnyValidation(schemaNameAndVersionAreSupported),
            AnyValidation(entriesArePresent),
            AnyValidation(entryIDsAreUnique),
            AnyValidation(entryRequiredStringsArePresent),
            AnyValidation(entryKindsUseStableVocabulary),
            AnyValidation(entryClassificationsUseStableVocabulary),
            AnyValidation(entryPurposesAreSpecific),
            AnyValidation(entryUnknownFactsAffectValidationStatus),
            AnyValidation(sourcesUseStableVocabulary),
            AnyValidation(sourcesHaveValues),
            AnyValidation(factsUseStableStatusVocabulary),
            AnyValidation(knownFactsHaveValues),
            AnyValidation(unknownFactsHaveFollowUps),
            AnyValidation(validationRecordsUseStableStatusVocabulary),
            AnyValidation(validationRecordsContainEvidence),
        ]
    }

    public static let supportedKinds: Set<String> = [
        "raw-corpus-source",
        "curated-corpus",
        "numeric-trace-corpus",
        "golden-trace",
        "tool",
        "executable-tool",
        "documentation-set",
        "dependency",
        "documentation-reference",
        "validation-idiom",
    ]

    public static let supportedSourceTypes: Set<String> = [
        "git",
        "local",
        "npm",
        "swift-package",
        "documentation",
        "canonical-rule",
    ]

    public static let supportedFactStatuses: Set<String> = [
        "known",
        "unknown",
    ]

    public static let supportedClassifications: Set<String> = [
        "discovery",
        "raw-corpus",
        "curated-oracle",
        "numeric-intent",
        "source-intent",
        "tooling",
        "documentation",
        "target-oracle",
        "validation-idiom",
        "unknown-tracked",
    ]

    public static let supportedValidationStatuses: Set<String> = [
        "usable",
        "usable-with-unknowns",
        "documented-only",
    ]

    public static var schemaNameAndVersionAreSupported: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Schema> {
        Validation(
            ruleID: "reference.schema.supported",
            description: "Reference provenance schema is purelottie.reference-provenance version 1",
            phase: .source,
            check: { context in
                var errors: [ValidationError] = []
                if context.subject.name != "purelottie.reference-provenance" {
                    errors.append(
                        ValidationError(
                            ruleID: "reference.schema.supported.name",
                            reason: "Failed to satisfy: Reference provenance schema name is purelottie.reference-provenance",
                            at: context.codingPath.appending(.key("name")),
                            phase: .source,
                            classification: .gap
                        )
                    )
                }
                if context.subject.version != 1 {
                    errors.append(
                        ValidationError(
                            ruleID: "reference.schema.supported.version",
                            reason: "Failed to satisfy: Reference provenance schema version is 1",
                            at: context.codingPath.appending(.key("version")),
                            phase: .source,
                            classification: .gap
                        )
                    )
                }
                return errors
            }
        )
    }

    public static var entriesArePresent: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest> {
        Validation(
            ruleID: "reference.entries.present",
            description: "Reference provenance manifest contains at least one entry",
            phase: .source,
            check: { context in !context.subject.entries.isEmpty }
        )
    }

    public static var entryIDsAreUnique: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest> {
        Validation(
            ruleID: "reference.entry.id.unique",
            description: "Reference provenance entry ids are unique",
            phase: .source,
            check: { context in
                var firstIndexByID: [String: Int] = [:]
                var errors: [ValidationError] = []
                for (index, entry) in context.subject.entries.enumerated() where !entry.id.isEmpty {
                    if let firstIndex = firstIndexByID[entry.id] {
                        errors.append(
                            ValidationError(
                                ruleID: "reference.entry.id.unique",
                                reason: "Reference provenance entry id `\(entry.id)` duplicates entry at index \(firstIndex).",
                                at: JSONPath([.key("entries"), .index(index), .key("id")]),
                                phase: .source,
                                classification: .gap
                            )
                        )
                    } else {
                        firstIndexByID[entry.id] = index
                    }
                }
                return errors
            }
        )
    }

    public static var entryRequiredStringsArePresent: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Entry> {
        Validation(
            ruleID: "reference.entry.required-strings",
            description: "Reference provenance entries declare id, kind, path, and purpose",
            phase: .source,
            check: { context in
                [
                    ("id", context.subject.id),
                    ("kind", context.subject.kind),
                    ("path", context.subject.path),
                    ("purpose", context.subject.purpose),
                ].compactMap { key, value in
                    guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    return ValidationError(
                        ruleID: "reference.entry.required-strings",
                        reason: "Failed to satisfy: Reference provenance entries declare id, kind, path, and purpose",
                        at: context.codingPath.appending(.key(key)),
                        phase: .source,
                        classification: .gap
                    )
                }
            }
        )
    }

    public static var entryKindsUseStableVocabulary: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Entry> {
        Validation(
            ruleID: "reference.entry.kind.vocabulary",
            description: "Reference provenance entry kinds use the stable vocabulary",
            phase: .source,
            check: { context -> [ValidationError] in
                guard !supportedKinds.contains(context.subject.kind) else { return [] }
                return [
                    ValidationError(
                        ruleID: "reference.entry.kind.vocabulary",
                        reason: "Failed to satisfy: Reference provenance entry kinds use the stable vocabulary",
                        at: context.codingPath.appending(.key("kind")),
                        phase: .source,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var entryClassificationsUseStableVocabulary: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Entry> {
        Validation(
            ruleID: "reference.entry.classification.vocabulary",
            description: "Reference provenance classifications are non-empty and use the stable vocabulary",
            phase: .source,
            check: { context in
                guard !context.subject.classifications.isEmpty else {
                    return [
                        ValidationError(
                            ruleID: "reference.entry.classification.empty",
                            reason: "Failed to satisfy: Reference provenance classifications are non-empty and use the stable vocabulary",
                            at: context.codingPath.appending(.key("classifications")),
                            phase: .source,
                            classification: .gap
                        ),
                    ]
                }
                return context.subject.classifications.enumerated().compactMap { index, classification in
                    guard !supportedClassifications.contains(classification) else { return nil }
                    return ValidationError(
                        ruleID: "reference.entry.classification.vocabulary",
                        reason: "Reference provenance classification `\(classification)` is not in the stable vocabulary.",
                        at: context.codingPath.appending(.key("classifications")).appending(.index(index)),
                        phase: .source,
                        classification: .gap
                    )
                }
            }
        )
    }

    public static var entryPurposesAreSpecific: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Entry> {
        Validation(
            ruleID: "reference.entry.purpose.specific",
            description: "Reference provenance entry purposes describe the evidence in at least 40 characters",
            phase: .source,
            check: { context -> [ValidationError] in
                guard context.subject.purpose.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 else { return [] }
                return [
                    ValidationError(
                        ruleID: "reference.entry.purpose.specific",
                        reason: "Failed to satisfy: Reference provenance entry purposes describe the evidence in at least 40 characters",
                        at: context.codingPath.appending(.key("purpose")),
                        phase: .source,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var entryUnknownFactsAffectValidationStatus: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Entry> {
        Validation(
            ruleID: "reference.entry.unknown.status",
            description: "Reference provenance entries with unknown facts use usable-with-unknowns validation status",
            phase: .semantic,
            check: { context -> [ValidationError] in
                let hasUnknownFact = context.subject.revision.status == "unknown" || context.subject.license.status == "unknown"
                guard hasUnknownFact, context.subject.validation.status != "usable-with-unknowns" else { return [] }
                return [
                    ValidationError(
                        ruleID: "reference.entry.unknown.status",
                        reason: "Failed to satisfy: Reference provenance entries with unknown facts use usable-with-unknowns validation status",
                        at: context.codingPath.appending(.key("validation")).appending(.key("status")),
                        phase: .semantic,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var sourcesUseStableVocabulary: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Source> {
        Validation(
            ruleID: "reference.source.type.vocabulary",
            description: "Reference provenance source types use the stable vocabulary",
            phase: .source,
            check: { context -> [ValidationError] in
                guard !supportedSourceTypes.contains(context.subject.type) else { return [] }
                return [
                    ValidationError(
                        ruleID: "reference.source.type.vocabulary",
                        reason: "Failed to satisfy: Reference provenance source types use the stable vocabulary",
                        at: context.codingPath.appending(.key("type")),
                        phase: .source,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var sourcesHaveValues: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Source> {
        Validation(
            ruleID: "reference.source.value.present",
            description: "Reference provenance sources declare a durable value",
            phase: .source,
            check: { context -> [ValidationError] in
                guard context.subject.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
                return [
                    ValidationError(
                        ruleID: "reference.source.value.present",
                        reason: "Failed to satisfy: Reference provenance sources declare a durable value",
                        at: context.codingPath.appending(.key("value")),
                        phase: .source,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var factsUseStableStatusVocabulary: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Fact> {
        Validation(
            ruleID: "reference.fact.status.vocabulary",
            description: "Reference provenance facts use known or unknown status",
            phase: .source,
            check: { context -> [ValidationError] in
                guard !supportedFactStatuses.contains(context.subject.status) else { return [] }
                return [
                    ValidationError(
                        ruleID: "reference.fact.status.vocabulary",
                        reason: "Failed to satisfy: Reference provenance facts use known or unknown status",
                        at: context.codingPath.appending(.key("status")),
                        phase: .source,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var knownFactsHaveValues: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Fact> {
        Validation(
            ruleID: "reference.fact.known.value",
            description: "Known reference provenance facts declare a value",
            phase: .source,
            check: { context -> [ValidationError] in
                guard context.subject.status == "known",
                      (context.subject.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return []
                }
                return [
                    ValidationError(
                        ruleID: "reference.fact.known.value",
                        reason: "Failed to satisfy: Known reference provenance facts declare a value",
                        at: context.codingPath.appending(.key("value")),
                        phase: .source,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var unknownFactsHaveFollowUps: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.Fact> {
        Validation(
            ruleID: "reference.fact.unknown.follow-up",
            description: "Unknown reference provenance facts declare a follow-up",
            phase: .source,
            check: { context -> [ValidationError] in
                guard context.subject.status == "unknown",
                      (context.subject.followUp ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return []
                }
                return [
                    ValidationError(
                        ruleID: "reference.fact.unknown.follow-up",
                        reason: "Failed to satisfy: Unknown reference provenance facts declare a follow-up",
                        at: context.codingPath.appending(.key("followUp")),
                        phase: .source,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var validationRecordsUseStableStatusVocabulary: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.ValidationRecord> {
        Validation(
            ruleID: "reference.validation.status.vocabulary",
            description: "Reference provenance validation statuses use the stable vocabulary",
            phase: .source,
            check: { context -> [ValidationError] in
                guard !supportedValidationStatuses.contains(context.subject.status) else { return [] }
                return [
                    ValidationError(
                        ruleID: "reference.validation.status.vocabulary",
                        reason: "Failed to satisfy: Reference provenance validation statuses use the stable vocabulary",
                        at: context.codingPath.appending(.key("status")),
                        phase: .source,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var validationRecordsContainEvidence: Validation<ReferenceProvenanceManifest, ReferenceProvenanceManifest.ValidationRecord> {
        Validation(
            ruleID: "reference.validation.evidence.present",
            description: "Reference provenance validation records contain evidence commands or tests",
            phase: .source,
            check: { context -> [ValidationError] in
                guard context.subject.evidence.isEmpty
                    || context.subject.evidence.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                else {
                    return []
                }
                return [
                    ValidationError(
                        ruleID: "reference.validation.evidence.present",
                        reason: "Failed to satisfy: Reference provenance validation records contain evidence commands or tests",
                        at: context.codingPath.appending(.key("evidence")),
                        phase: .source,
                        classification: .gap
                    ),
                ]
            }
        )
    }
}
