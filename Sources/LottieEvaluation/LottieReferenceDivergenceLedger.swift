import Foundation
import LottieModel

public struct LottieReferenceDivergenceLedger: Codable, Equatable, Sendable, Validatable {
    public var schema: Schema
    public var divergences: [Divergence]

    public struct Schema: Codable, Equatable, Sendable, Validatable {
        public var name: String
        public var version: Int
    }

    public struct Divergence: Codable, Equatable, Sendable, Validatable {
        public var id: String
        public var title: String
        public var status: String
        public var engines: [String]
        public var affectedFields: [String]
        public var fixtures: [String]
        public var observedBehavior: String
        public var comparisonEvidence: [String]
        public var sourcePointers: [SourcePointer]
        public var witness: LottieClaimWitness
    }

    public struct SourcePointer: Codable, Equatable, Sendable, Validatable {
        public var kind: String
        public var path: String
        public var note: String
    }

    public func divergence(id: String) throws -> Divergence {
        guard let match = divergences.first(where: { $0.id == id }) else {
            throw LottieReferenceDivergenceLookupError.missing(id)
        }
        return match
    }
}

public enum LottieReferenceDivergenceLookupError: Error, Equatable, Sendable {
    case missing(String)
}

public final class LottieReferenceDivergenceLedgerValidator {
    private var defaultValidations: [LottieReferenceDivergenceAnyValidation]
    private var customValidations: [LottieReferenceDivergenceAnyValidation]

    public init() {
        defaultValidations = LottieReferenceDivergenceBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [LottieReferenceDivergenceAnyValidation],
        customValidations: [LottieReferenceDivergenceAnyValidation]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieReferenceDivergenceLedgerValidator {
        LottieReferenceDivergenceLedgerValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieReferenceDivergenceLedger, some Validatable>) -> Self {
        customValidations.append(LottieReferenceDivergenceAnyValidation(validation))
        return self
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    public func collectErrors(in ledger: LottieReferenceDivergenceLedger) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(ledger, at: JSONPath(), in: ledger, errors: &errors)
        visit(ledger.schema, at: JSONPath([.key("schema")]), in: ledger, errors: &errors)
        for divergenceIndex in ledger.divergences.indices {
            let divergencePath = JSONPath([.key("divergences"), .index(divergenceIndex)])
            let divergence = ledger.divergences[divergenceIndex]
            visit(divergence, at: divergencePath, in: ledger, errors: &errors)
            visit(divergence.witness, at: divergencePath.appending(.key("witness")), in: ledger, errors: &errors)
            for pointerIndex in divergence.sourcePointers.indices {
                visit(
                    divergence.sourcePointers[pointerIndex],
                    at: divergencePath
                        .appending(.key("sourcePointers"))
                        .appending(.index(pointerIndex)),
                    in: ledger,
                    errors: &errors
                )
            }
        }
        return errors
    }

    public func validate(_ ledger: LottieReferenceDivergenceLedger) throws {
        let errors = collectErrors(in: ledger)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    private var activeValidations: [LottieReferenceDivergenceAnyValidation] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in ledger: LottieReferenceDivergenceLedger,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: ledger))
        }
    }
}

public extension LottieReferenceDivergenceLedger {
    static func decodeValidated(
        from data: Data,
        using validator: LottieReferenceDivergenceLedgerValidator = LottieReferenceDivergenceLedgerValidator()
    ) throws -> LottieReferenceDivergenceLedger {
        do {
            return try JSONDecoder().decode(LottieReferenceDivergenceLedger.self, from: data)
                .validate(using: validator)
        } catch let errors as ValidationErrorCollection {
            throw errors
        } catch let error as DecodingError {
            throw ValidationErrorCollection([Self.validationError(from: error)])
        }
    }

    @discardableResult
    func validate(using validator: LottieReferenceDivergenceLedgerValidator = LottieReferenceDivergenceLedgerValidator()) throws -> Self {
        try validator.validate(self)
        return self
    }

    private static func validationError(from error: DecodingError) -> ValidationError {
        switch error {
        case let .keyNotFound(key, context):
            return ValidationError(
                ruleID: "reference-divergence.decode.key-not-found",
                reason: "Failed to satisfy: Reference divergence ledger decodes as the typed schema",
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
                ruleID: "reference-divergence.decode.unknown",
                reason: "Failed to satisfy: Reference divergence ledger decodes as the typed schema",
                at: JSONPath(),
                phase: .parse,
                classification: .gap
            )
        }
    }

    private static func decodingError(context: DecodingError.Context) -> ValidationError {
        ValidationError(
            ruleID: "reference-divergence.decode",
            reason: "Failed to satisfy: Reference divergence ledger decodes as the typed schema",
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

public enum LottieReferenceDivergenceBuiltinValidation {
    public static let supportedStatuses: Set<String> = [
        "diagnosed-boundary",
        "measured",
    ]

    public static let supportedSourcePointerKinds: Set<String> = [
        "fixture",
        "lottie-web-intent",
        "local-source",
        "local-test",
        "oracle-tool",
    ]

    fileprivate static var defaultValidations: [LottieReferenceDivergenceAnyValidation] {
        [
            LottieReferenceDivergenceAnyValidation(schemaNameAndVersionAreSupported),
            LottieReferenceDivergenceAnyValidation(divergenceIDsArePresentAndUnique),
            LottieReferenceDivergenceAnyValidation(divergenceRecordsAreComplete),
            LottieReferenceDivergenceAnyValidation(divergenceStatusesUseStableVocabulary),
            LottieReferenceDivergenceAnyValidation(sourcePointersUseStableVocabularyAndPaths),
            LottieReferenceDivergenceAnyValidation(divergenceWitnessClassificationsAreExplicit),
        ]
    }

    public static var schemaNameAndVersionAreSupported:
        Validation<LottieReferenceDivergenceLedger, LottieReferenceDivergenceLedger.Schema>
    {
        Validation(
            ruleID: "reference-divergence.schema.supported",
            description: "Reference divergence schema name is purelottie.reference-divergences and version is 1",
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.name != "purelottie.reference-divergences" {
                errors.append(error(
                    ruleID: "reference-divergence.schema.name",
                    description: "Reference divergence schema name is purelottie.reference-divergences and version is 1",
                    path: context.codingPath.appending(.key("name"))
                ))
            }
            if context.subject.version != 1 {
                errors.append(error(
                    ruleID: "reference-divergence.schema.version",
                    description: "Reference divergence schema name is purelottie.reference-divergences and version is 1",
                    path: context.codingPath.appending(.key("version"))
                ))
            }
            return errors
        }
    }

    public static var divergenceIDsArePresentAndUnique:
        Validation<LottieReferenceDivergenceLedger, LottieReferenceDivergenceLedger>
    {
        Validation(
            ruleID: "reference-divergence.ids.unique",
            description: "Reference divergence ledger contains unique divergence ids"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.divergences.isEmpty {
                errors.append(error(
                    ruleID: "reference-divergence.ids.present",
                    description: "Reference divergence ledger contains unique divergence ids",
                    path: context.codingPath.appending(.key("divergences"))
                ))
            }
            var seen: Set<String> = []
            for index in context.subject.divergences.indices {
                let id = context.subject.divergences[index].id
                if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || seen.contains(id) {
                    errors.append(error(
                        ruleID: "reference-divergence.ids.unique",
                        description: "Reference divergence ledger contains unique divergence ids",
                        path: context.codingPath
                            .appending(.key("divergences"))
                            .appending(.index(index))
                            .appending(.key("id"))
                    ))
                }
                seen.insert(id)
            }
            return errors
        }
    }

    public static var divergenceRecordsAreComplete:
        Validation<LottieReferenceDivergenceLedger, LottieReferenceDivergenceLedger.Divergence>
    {
        Validation(
            ruleID: "reference-divergence.record.complete",
            description: "Reference divergence records state measured behavior affected fields fixtures evidence and source pointers"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.title.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                errors.append(recordError("title", context))
            }
            if context.subject.engines.isEmpty || context.subject.engines.contains(where: isBlank) {
                errors.append(recordError("engines", context))
            }
            if context.subject.affectedFields.isEmpty || context.subject.affectedFields.contains(where: isBlank) {
                errors.append(recordError("affectedFields", context))
            }
            if context.subject.fixtures.isEmpty || context.subject.fixtures.contains(where: isBlank) {
                errors.append(recordError("fixtures", context))
            }
            if context.subject.observedBehavior.trimmingCharacters(in: .whitespacesAndNewlines).count < 80 {
                errors.append(recordError("observedBehavior", context))
            }
            if context.subject.comparisonEvidence.isEmpty || context.subject.comparisonEvidence.contains(where: isBlank) {
                errors.append(recordError("comparisonEvidence", context))
            }
            if context.subject.sourcePointers.isEmpty {
                errors.append(recordError("sourcePointers", context))
            }
            return errors
        }
    }

    public static var divergenceStatusesUseStableVocabulary:
        Validation<LottieReferenceDivergenceLedger, LottieReferenceDivergenceLedger.Divergence>
    {
        Validation(
            ruleID: "reference-divergence.status.stable",
            description: "Reference divergence statuses use stable vocabulary"
        ) { context in
            supportedStatuses.contains(context.subject.status)
                ? []
                : [
                    error(
                        ruleID: "reference-divergence.status",
                        description: "Reference divergence statuses use stable vocabulary",
                        path: context.codingPath.appending(.key("status"))
                    ),
                ]
        }
    }

    public static var sourcePointersUseStableVocabularyAndPaths:
        Validation<LottieReferenceDivergenceLedger, LottieReferenceDivergenceLedger.SourcePointer>
    {
        Validation(
            ruleID: "reference-divergence.source-pointer.stable",
            description: "Reference divergence source pointers use stable kinds non-empty paths and explanatory notes"
        ) { context in
            var errors: [ValidationError] = []
            if !supportedSourcePointerKinds.contains(context.subject.kind) {
                errors.append(error(
                    ruleID: "reference-divergence.source-pointer.kind",
                    description: "Reference divergence source pointers use stable kinds non-empty paths and explanatory notes",
                    path: context.codingPath.appending(.key("kind"))
                ))
            }
            if isBlank(context.subject.path) {
                errors.append(error(
                    ruleID: "reference-divergence.source-pointer.path",
                    description: "Reference divergence source pointers use stable kinds non-empty paths and explanatory notes",
                    path: context.codingPath.appending(.key("path"))
                ))
            }
            if context.subject.note.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                errors.append(error(
                    ruleID: "reference-divergence.source-pointer.note",
                    description: "Reference divergence source pointers use stable kinds non-empty paths and explanatory notes",
                    path: context.codingPath.appending(.key("note"))
                ))
            }
            return errors
        }
    }

    public static var divergenceWitnessClassificationsAreExplicit:
        Validation<LottieReferenceDivergenceLedger, LottieClaimWitness>
    {
        LottieClaimWitnessValidation.claimWitnessIsExplicit(
            ruleIDPrefix: "reference-divergence.witness",
            description: "Reference divergence witness classifications state witnessed asserted or blocked evidence"
        )
    }

    private static func recordError(
        _ key: String,
        _ context: ValidationContext<LottieReferenceDivergenceLedger, LottieReferenceDivergenceLedger.Divergence>
    ) -> ValidationError {
        error(
            ruleID: "reference-divergence.record.complete",
            description: "Reference divergence records state measured behavior affected fields fixtures evidence and source pointers",
            path: context.codingPath.appending(.key(key))
        )
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func error(
        ruleID: String,
        description: String,
        path: JSONPath,
        evidence: String? = nil
    ) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "Failed to satisfy: \(description)",
            at: path,
            phase: .source,
            classification: .reported,
            evidence: evidence
        )
    }
}

private struct LottieReferenceDivergenceAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, LottieReferenceDivergenceLedger) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<LottieReferenceDivergenceLedger, Subject>) {
        ruleID = validation.ruleID
        description = validation.description
        applyClosure = { input, path, document in
            guard let subject = input as? Subject else { return [] }
            return validation.apply(to: subject, at: path, in: document)
        }
    }

    func apply(
        to subject: any Validatable,
        at codingPath: JSONPath,
        in document: LottieReferenceDivergenceLedger
    ) -> [ValidationError] {
        applyClosure(subject, codingPath, document)
    }
}
