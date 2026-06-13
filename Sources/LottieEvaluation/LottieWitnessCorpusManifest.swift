import Foundation
import LottieModel

public struct LottieWitnessCorpusManifest: Codable, Equatable, Sendable, Validatable {
    public var schema: Schema
    public var entries: [Entry]

    public struct Schema: Codable, Equatable, Sendable, Validatable {
        public var name: String
        public var version: Int
    }

    public struct Entry: Codable, Equatable, Sendable, Validatable {
        public var id: String
        public var description: String
        public var semanticStatus: String
        public var lottie: String
        public var lottieWebIntent: String
        public var frames: [Frame]
        public var witness: LottieClaimWitness
    }

    public struct Frame: Codable, Equatable, Sendable, Validatable {
        public var frame: Double
        public var rationale: String
    }
}

public final class LottieWitnessCorpusManifestValidator {
    private var defaultValidations: [LottieWitnessCorpusManifestAnyValidation]
    private var customValidations: [LottieWitnessCorpusManifestAnyValidation]

    public init() {
        defaultValidations = LottieWitnessCorpusManifestBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [LottieWitnessCorpusManifestAnyValidation],
        customValidations: [LottieWitnessCorpusManifestAnyValidation]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieWitnessCorpusManifestValidator {
        LottieWitnessCorpusManifestValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieWitnessCorpusManifest, some Validatable>) -> Self {
        customValidations.append(LottieWitnessCorpusManifestAnyValidation(validation))
        return self
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    public func collectErrors(in manifest: LottieWitnessCorpusManifest) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(manifest, at: JSONPath(), in: manifest, errors: &errors)
        visit(manifest.schema, at: JSONPath([.key("schema")]), in: manifest, errors: &errors)
        for entryIndex in manifest.entries.indices {
            let entry = manifest.entries[entryIndex]
            let entryPath = JSONPath([.key("entries"), .index(entryIndex)])
            visit(entry, at: entryPath, in: manifest, errors: &errors)
            visit(entry.witness, at: entryPath.appending(.key("witness")), in: manifest, errors: &errors)
            for frameIndex in entry.frames.indices {
                visit(
                    entry.frames[frameIndex],
                    at: entryPath.appending(.key("frames")).appending(.index(frameIndex)),
                    in: manifest,
                    errors: &errors
                )
            }
        }
        return errors
    }

    public func validate(_ manifest: LottieWitnessCorpusManifest) throws {
        let errors = collectErrors(in: manifest)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    private var activeValidations: [LottieWitnessCorpusManifestAnyValidation] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in manifest: LottieWitnessCorpusManifest,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: manifest))
        }
    }
}

public extension LottieWitnessCorpusManifest {
    static func decodeValidated(
        from data: Data,
        using validator: LottieWitnessCorpusManifestValidator = LottieWitnessCorpusManifestValidator()
    ) throws -> LottieWitnessCorpusManifest {
        do {
            return try JSONDecoder().decode(LottieWitnessCorpusManifest.self, from: data)
                .validate(using: validator)
        } catch let errors as ValidationErrorCollection {
            throw errors
        } catch let error as DecodingError {
            throw ValidationErrorCollection([Self.validationError(from: error)])
        }
    }

    @discardableResult
    func validate(
        using validator: LottieWitnessCorpusManifestValidator = LottieWitnessCorpusManifestValidator()
    ) throws -> Self {
        try validator.validate(self)
        return self
    }

    private static func validationError(from error: DecodingError) -> ValidationError {
        switch error {
        case let .keyNotFound(key, context):
            ValidationError(
                ruleID: "witness-corpus.decode.key-not-found",
                reason: "Failed to satisfy: Witness corpus manifest decodes as the typed schema",
                at: jsonPath(from: context.codingPath).appending(codingComponent(from: key)),
                phase: .parse,
                classification: .gap,
                evidence: context.debugDescription
            )
        case let .typeMismatch(_, context):
            decodingError(context: context)
        case let .valueNotFound(_, context):
            decodingError(context: context)
        case let .dataCorrupted(context):
            decodingError(context: context)
        @unknown default:
            ValidationError(
                ruleID: "witness-corpus.decode.unknown",
                reason: "Failed to satisfy: Witness corpus manifest decodes as the typed schema",
                at: JSONPath(),
                phase: .parse,
                classification: .gap
            )
        }
    }

    private static func decodingError(context: DecodingError.Context) -> ValidationError {
        ValidationError(
            ruleID: "witness-corpus.decode",
            reason: "Failed to satisfy: Witness corpus manifest decodes as the typed schema",
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

public enum LottieWitnessCorpusManifestBuiltinValidation {
    fileprivate static var defaultValidations: [LottieWitnessCorpusManifestAnyValidation] {
        [
            LottieWitnessCorpusManifestAnyValidation(schemaNameAndVersionAreSupported),
            LottieWitnessCorpusManifestAnyValidation(entriesArePresentAndUnique),
            LottieWitnessCorpusManifestAnyValidation(entriesAreComplete),
            LottieWitnessCorpusManifestAnyValidation(framesAreFiniteAndExplained),
            LottieWitnessCorpusManifestAnyValidation(entryWitnessClassificationsAreExplicit),
        ]
    }

    public static var schemaNameAndVersionAreSupported:
        Validation<LottieWitnessCorpusManifest, LottieWitnessCorpusManifest.Schema>
    {
        Validation(
            ruleID: "witness-corpus.schema.supported",
            description: "Witness corpus schema name is purelottie.numeric-claim-witness-corpus and version is 1",
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.name != "purelottie.numeric-claim-witness-corpus" {
                errors.append(error(
                    ruleID: "witness-corpus.schema.name",
                    description: "Witness corpus schema name is purelottie.numeric-claim-witness-corpus and version is 1",
                    path: context.codingPath.appending(.key("name"))
                ))
            }
            if context.subject.version != 1 {
                errors.append(error(
                    ruleID: "witness-corpus.schema.version",
                    description: "Witness corpus schema name is purelottie.numeric-claim-witness-corpus and version is 1",
                    path: context.codingPath.appending(.key("version"))
                ))
            }
            return errors
        }
    }

    public static var entriesArePresentAndUnique:
        Validation<LottieWitnessCorpusManifest, LottieWitnessCorpusManifest>
    {
        Validation(
            ruleID: "witness-corpus.entries.unique",
            description: "Witness corpus manifest contains unique witness entry ids"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.entries.isEmpty {
                errors.append(error(
                    ruleID: "witness-corpus.entries.present",
                    description: "Witness corpus manifest contains unique witness entry ids",
                    path: context.codingPath.appending(.key("entries"))
                ))
            }
            var seen: Set<String> = []
            for index in context.subject.entries.indices {
                let id = context.subject.entries[index].id
                if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || seen.contains(id) {
                    errors.append(error(
                        ruleID: "witness-corpus.entries.unique",
                        description: "Witness corpus manifest contains unique witness entry ids",
                        path: context.codingPath.appending(.key("entries")).appending(.index(index)).appending(.key("id"))
                    ))
                }
                seen.insert(id)
            }
            return errors
        }
    }

    public static var entriesAreComplete:
        Validation<LottieWitnessCorpusManifest, LottieWitnessCorpusManifest.Entry>
    {
        Validation(
            ruleID: "witness-corpus.entry.complete",
            description: "Witness corpus entries record source trace semantic status frames and witnessed evidence"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.description.trimmingCharacters(in: .whitespacesAndNewlines).count < 30 {
                errors.append(entryError("description", context))
            }
            if context.subject.semanticStatus != "witnessed-reference" {
                errors.append(entryError("semanticStatus", context))
            }
            if !context.subject.lottie.hasSuffix(".json") {
                errors.append(entryError("lottie", context))
            }
            if !context.subject.lottieWebIntent.hasSuffix(".json") {
                errors.append(entryError("lottieWebIntent", context))
            }
            if context.subject.frames.isEmpty {
                errors.append(entryError("frames", context))
            }
            if context.subject.witness.status != .witnessed {
                errors.append(entryError("witness", context))
            }
            if !context.subject.witness.evidence.contains(context.subject.lottieWebIntent) {
                errors.append(entryError("witness.evidence", context))
            }
            return errors
        }
    }

    public static var framesAreFiniteAndExplained:
        Validation<LottieWitnessCorpusManifest, LottieWitnessCorpusManifest.Frame>
    {
        Validation(
            ruleID: "witness-corpus.frame.finite",
            description: "Witness corpus frame samples are finite source frames with rationales"
        ) { context in
            var errors: [ValidationError] = []
            if !context.subject.frame.isFinite {
                errors.append(error(
                    ruleID: "witness-corpus.frame.finite",
                    description: "Witness corpus frame samples are finite source frames with rationales",
                    path: context.codingPath.appending(.key("frame"))
                ))
            }
            if context.subject.rationale.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                errors.append(error(
                    ruleID: "witness-corpus.frame.rationale",
                    description: "Witness corpus frame samples are finite source frames with rationales",
                    path: context.codingPath.appending(.key("rationale"))
                ))
            }
            return errors
        }
    }

    public static var entryWitnessClassificationsAreExplicit:
        Validation<LottieWitnessCorpusManifest, LottieClaimWitness>
    {
        LottieClaimWitnessValidation.claimWitnessIsExplicit(
            ruleIDPrefix: "witness-corpus.witness",
            description: "Witness corpus classifications state witnessed asserted or blocked evidence"
        )
    }

    private static func entryError(
        _ key: String,
        _ context: ValidationContext<LottieWitnessCorpusManifest, LottieWitnessCorpusManifest.Entry>
    ) -> ValidationError {
        error(
            ruleID: "witness-corpus.entry.complete",
            description: "Witness corpus entries record source trace semantic status frames and witnessed evidence",
            path: context.codingPath.appending(.key(key))
        )
    }

    private static func error(
        ruleID: String,
        description: String,
        path: JSONPath
    ) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "Failed to satisfy: \(description)",
            at: path,
            phase: .source,
            classification: .reported
        )
    }
}

private struct LottieWitnessCorpusManifestAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, LottieWitnessCorpusManifest) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<LottieWitnessCorpusManifest, Subject>) {
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
        in document: LottieWitnessCorpusManifest
    ) -> [ValidationError] {
        applyClosure(subject, codingPath, document)
    }
}
