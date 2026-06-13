import Foundation
import LottieModel

public struct LottieOracleToleranceLedger: Codable, Equatable, Sendable, Validatable {
    public var schema: Schema
    public var tolerances: [Tolerance]

    public struct Schema: Codable, Equatable, Sendable, Validatable {
        public var name: String
        public var version: Int
    }

    public struct Tolerance: Codable, Equatable, Sendable, Validatable {
        public var id: String
        public var feature: String
        public var unit: String
        public var comparison: String
        public var threshold: Double
        public var reason: String
        public var derivation: Derivation
        public var witness: LottieClaimWitness

        public struct Derivation: Codable, Equatable, Sendable, Validatable {
            public var status: Status
            public var arithmeticModel: String
            public var derivedBound: Double
            public var formula: String
            public var proof: String
            public var evidence: [String]
            public var counterexampleOffset: Double
            public var assumption: String?

            public enum Status: String, Codable, Equatable, Sendable, Validatable {
                case derived
                case assumed
            }
        }
    }

    public func tolerance(id: String) throws -> Tolerance {
        guard let match = tolerances.first(where: { $0.id == id }) else {
            throw LottieOracleToleranceLookupError.missing(id)
        }
        return match
    }

    public func threshold(id: String) throws -> Double {
        try tolerance(id: id).threshold
    }
}

public enum LottieOracleToleranceLookupError: Error, Equatable, Sendable {
    case missing(String)
}

public final class LottieOracleToleranceLedgerValidator {
    private var defaultValidations: [LottieOracleToleranceAnyValidation]
    private var customValidations: [LottieOracleToleranceAnyValidation]

    public init() {
        defaultValidations = LottieOracleToleranceBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [LottieOracleToleranceAnyValidation],
        customValidations: [LottieOracleToleranceAnyValidation]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieOracleToleranceLedgerValidator {
        LottieOracleToleranceLedgerValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieOracleToleranceLedger, some Validatable>) -> Self {
        customValidations.append(LottieOracleToleranceAnyValidation(validation))
        return self
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    public func collectErrors(in ledger: LottieOracleToleranceLedger) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(ledger, at: JSONPath(), in: ledger, errors: &errors)
        visit(ledger.schema, at: JSONPath([.key("schema")]), in: ledger, errors: &errors)
        for index in ledger.tolerances.indices {
            let tolerancePath = JSONPath([.key("tolerances"), .index(index)])
            visit(
                ledger.tolerances[index],
                at: tolerancePath,
                in: ledger,
                errors: &errors
            )
            visit(
                ledger.tolerances[index].witness,
                at: tolerancePath.appending(.key("witness")),
                in: ledger,
                errors: &errors
            )
            visit(
                ledger.tolerances[index].derivation,
                at: tolerancePath.appending(.key("derivation")),
                in: ledger,
                errors: &errors
            )
        }
        return errors
    }

    public func validate(_ ledger: LottieOracleToleranceLedger) throws {
        let errors = collectErrors(in: ledger)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    private var activeValidations: [LottieOracleToleranceAnyValidation] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in ledger: LottieOracleToleranceLedger,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: ledger))
        }
    }
}

public extension LottieOracleToleranceLedger {
    static func decodeValidated(
        from data: Data,
        using validator: LottieOracleToleranceLedgerValidator = LottieOracleToleranceLedgerValidator()
    ) throws -> LottieOracleToleranceLedger {
        do {
            return try JSONDecoder().decode(LottieOracleToleranceLedger.self, from: data)
                .validate(using: validator)
        } catch let errors as ValidationErrorCollection {
            throw errors
        } catch let error as DecodingError {
            throw ValidationErrorCollection([Self.validationError(from: error)])
        }
    }

    @discardableResult
    func validate(using validator: LottieOracleToleranceLedgerValidator = LottieOracleToleranceLedgerValidator()) throws -> Self {
        try validator.validate(self)
        return self
    }

    private static func validationError(from error: DecodingError) -> ValidationError {
        switch error {
        case let .keyNotFound(key, context):
            return ValidationError(
                ruleID: "oracle-tolerance.decode.key-not-found",
                reason: "Failed to satisfy: Oracle tolerance ledger decodes as the typed schema",
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
                ruleID: "oracle-tolerance.decode.unknown",
                reason: "Failed to satisfy: Oracle tolerance ledger decodes as the typed schema",
                at: JSONPath(),
                phase: .parse,
                classification: .gap
            )
        }
    }

    private static func decodingError(context: DecodingError.Context) -> ValidationError {
        ValidationError(
            ruleID: "oracle-tolerance.decode",
            reason: "Failed to satisfy: Oracle tolerance ledger decodes as the typed schema",
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

public enum LottieOracleToleranceBuiltinValidation {
    public static let requiredToleranceIDs: Set<String> = [
        "bounds.css-pixel.absolute",
        "frame.source-frame.absolute",
        "matrix.translation.css-pixel.absolute",
        "opacity.unit-interval.absolute",
        "path-length.css-pixel.absolute",
        "pixel.max-channel.exact",
        "trim.segment.unit-interval.absolute",
    ]

    public static let supportedFeatures: Set<String> = [
        "bounds",
        "frame",
        "matrix-translation",
        "opacity",
        "path-length",
        "pixel-diff",
        "trim-segment",
    ]

    public static let supportedUnits: Set<String> = [
        "cssPixel",
        "sourceFrame",
        "rgbaChannelValue",
        "unitInterval",
    ]

    public static let supportedComparisons: Set<String> = [
        "absolute-difference",
        "max-channel-difference",
    ]

    fileprivate static var defaultValidations: [LottieOracleToleranceAnyValidation] {
        [
            LottieOracleToleranceAnyValidation(schemaNameAndVersionAreSupported),
            LottieOracleToleranceAnyValidation(tolerancesArePresentAndUnique),
            LottieOracleToleranceAnyValidation(requiredToleranceFamiliesArePresent),
            LottieOracleToleranceAnyValidation(toleranceVocabularyIsStable),
            LottieOracleToleranceAnyValidation(toleranceThresholdsAreFiniteAndNonNegative),
            LottieOracleToleranceAnyValidation(toleranceReasonsAreSpecific),
            LottieOracleToleranceAnyValidation(toleranceDerivationsAreExplicit),
            LottieOracleToleranceAnyValidation(toleranceDerivationBoundsMatchThresholds),
            LottieOracleToleranceAnyValidation(toleranceCounterexampleOffsetsExceedThresholds),
            LottieOracleToleranceAnyValidation(toleranceWitnessMatchesDerivationStatus),
            LottieOracleToleranceAnyValidation(toleranceWitnessClassificationsAreExplicit),
        ]
    }

    public static var schemaNameAndVersionAreSupported: Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger.Schema> {
        Validation(
            ruleID: "oracle-tolerance.schema.supported",
            description: "Oracle tolerance schema name is purelottie.oracle-tolerances and version is 2",
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.name != "purelottie.oracle-tolerances" {
                errors.append(error(
                    ruleID: "oracle-tolerance.schema.name",
                    description: "Oracle tolerance schema name is purelottie.oracle-tolerances and version is 2",
                    path: context.codingPath.appending(.key("name"))
                ))
            }
            if context.subject.version != 2 {
                errors.append(error(
                    ruleID: "oracle-tolerance.schema.version",
                    description: "Oracle tolerance schema name is purelottie.oracle-tolerances and version is 2",
                    path: context.codingPath.appending(.key("version"))
                ))
            }
            return errors
        }
    }

    public static var tolerancesArePresentAndUnique: Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger> {
        Validation(
            ruleID: "oracle-tolerance.ids.unique",
            description: "Oracle tolerance ledger contains unique tolerance ids"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.tolerances.isEmpty {
                errors.append(error(
                    ruleID: "oracle-tolerance.ids.present",
                    description: "Oracle tolerance ledger contains unique tolerance ids",
                    path: context.codingPath.appending(.key("tolerances"))
                ))
            }
            var seen: Set<String> = []
            for index in context.subject.tolerances.indices {
                let id = context.subject.tolerances[index].id
                if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || seen.contains(id) {
                    errors.append(error(
                        ruleID: "oracle-tolerance.ids.unique",
                        description: "Oracle tolerance ledger contains unique tolerance ids",
                        path: context.codingPath
                            .appending(.key("tolerances"))
                            .appending(.index(index))
                            .appending(.key("id"))
                    ))
                }
                seen.insert(id)
            }
            return errors
        }
    }

    public static var requiredToleranceFamiliesArePresent: Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger> {
        Validation(
            ruleID: "oracle-tolerance.required.present",
            description: "Oracle tolerance ledger records opacity matrix translation bounds frame path length trim segment and pixel diff families"
        ) { context in
            let actual = Set(context.subject.tolerances.map(\.id))
            return requiredToleranceIDs.subtracting(actual).map { missingID in
                error(
                    ruleID: "oracle-tolerance.required.missing",
                    description: "Oracle tolerance ledger records opacity matrix translation bounds frame path length trim segment and pixel diff families",
                    path: context.codingPath.appending(.key("tolerances")),
                    evidence: missingID
                )
            }
        }
    }

    public static var toleranceVocabularyIsStable: Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger.Tolerance> {
        Validation(
            ruleID: "oracle-tolerance.vocabulary",
            description: "Oracle tolerance feature unit and comparison values use stable vocabulary"
        ) { context in
            var errors: [ValidationError] = []
            if !supportedFeatures.contains(context.subject.feature) {
                errors.append(error(
                    ruleID: "oracle-tolerance.feature",
                    description: "Oracle tolerance feature unit and comparison values use stable vocabulary",
                    path: context.codingPath.appending(.key("feature"))
                ))
            }
            if !supportedUnits.contains(context.subject.unit) {
                errors.append(error(
                    ruleID: "oracle-tolerance.unit",
                    description: "Oracle tolerance feature unit and comparison values use stable vocabulary",
                    path: context.codingPath.appending(.key("unit"))
                ))
            }
            if !supportedComparisons.contains(context.subject.comparison) {
                errors.append(error(
                    ruleID: "oracle-tolerance.comparison",
                    description: "Oracle tolerance feature unit and comparison values use stable vocabulary",
                    path: context.codingPath.appending(.key("comparison"))
                ))
            }
            return errors
        }
    }

    public static var toleranceThresholdsAreFiniteAndNonNegative:
        Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger.Tolerance>
    {
        Validation(
            ruleID: "oracle-tolerance.threshold.non-negative",
            description: "Oracle tolerance thresholds are finite non-negative numbers"
        ) { context in
            context.subject.threshold.isFinite && context.subject.threshold >= 0
                ? []
                : [
                    error(
                        ruleID: "oracle-tolerance.threshold",
                        description: "Oracle tolerance thresholds are finite non-negative numbers",
                        path: context.codingPath.appending(.key("threshold"))
                    ),
                ]
        }
    }

    public static var toleranceReasonsAreSpecific: Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger.Tolerance> {
        Validation(
            ruleID: "oracle-tolerance.reason.specific",
            description: "Oracle tolerance reasons explain the measured unit and error source"
        ) { context in
            context.subject.reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40
                ? []
                : [
                    error(
                        ruleID: "oracle-tolerance.reason",
                        description: "Oracle tolerance reasons explain the measured unit and error source",
                        path: context.codingPath.appending(.key("reason"))
                    ),
                ]
        }
    }

    public static var toleranceDerivationsAreExplicit:
        Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger.Tolerance.Derivation>
    {
        Validation(
            ruleID: "oracle-tolerance.derivation.explicit",
            description: "Oracle tolerance derivations state arithmetic model bound formula proof evidence and rejection offset"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.arithmeticModel.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
                errors.append(error(
                    ruleID: "oracle-tolerance.derivation.model",
                    description: "Oracle tolerance derivations state arithmetic model bound formula proof evidence and rejection offset",
                    path: context.codingPath.appending(.key("arithmeticModel"))
                ))
            }
            if !context.subject.derivedBound.isFinite || context.subject.derivedBound < 0 {
                errors.append(error(
                    ruleID: "oracle-tolerance.derivation.bound",
                    description: "Oracle tolerance derivations state arithmetic model bound formula proof evidence and rejection offset",
                    path: context.codingPath.appending(.key("derivedBound"))
                ))
            }
            if context.subject.formula.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
                errors.append(error(
                    ruleID: "oracle-tolerance.derivation.formula",
                    description: "Oracle tolerance derivations state arithmetic model bound formula proof evidence and rejection offset",
                    path: context.codingPath.appending(.key("formula"))
                ))
            }
            if context.subject.proof.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
                errors.append(error(
                    ruleID: "oracle-tolerance.derivation.proof",
                    description: "Oracle tolerance derivations state arithmetic model bound formula proof evidence and rejection offset",
                    path: context.codingPath.appending(.key("proof"))
                ))
            }
            if context.subject.evidence.isEmpty || context.subject.evidence.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                errors.append(error(
                    ruleID: "oracle-tolerance.derivation.evidence",
                    description: "Oracle tolerance derivations state arithmetic model bound formula proof evidence and rejection offset",
                    path: context.codingPath.appending(.key("evidence"))
                ))
            }
            if !context.subject.counterexampleOffset.isFinite || context.subject.counterexampleOffset <= context.subject.derivedBound {
                errors.append(error(
                    ruleID: "oracle-tolerance.derivation.counterexample-offset",
                    description: "Oracle tolerance derivations state arithmetic model bound formula proof evidence and rejection offset",
                    path: context.codingPath.appending(.key("counterexampleOffset"))
                ))
            }
            if context.subject.status == .assumed {
                let assumption = context.subject.assumption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if assumption.count < 40 {
                    errors.append(error(
                        ruleID: "oracle-tolerance.derivation.assumption",
                        description: "Oracle tolerance derivations state arithmetic model bound formula proof evidence and rejection offset",
                        path: context.codingPath.appending(.key("assumption"))
                    ))
                }
            }
            return errors
        }
    }

    public static var toleranceDerivationBoundsMatchThresholds:
        Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger.Tolerance>
    {
        Validation(
            ruleID: "oracle-tolerance.derivation.bound-matches-threshold",
            description: "Derived oracle tolerance thresholds equal their proven arithmetic bounds"
        ) { context in
            guard context.subject.derivation.status == .derived else { return [] }
            return context.subject.threshold == context.subject.derivation.derivedBound
                ? []
                : [
                    error(
                        ruleID: "oracle-tolerance.threshold.loose",
                        description: "Derived oracle tolerance thresholds equal their proven arithmetic bounds",
                        path: context.codingPath.appending(.key("threshold")),
                        evidence: context.subject.id
                    ),
                ]
        }
    }

    public static var toleranceCounterexampleOffsetsExceedThresholds:
        Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger.Tolerance>
    {
        Validation(
            ruleID: "oracle-tolerance.derivation.counterexample-exceeds-threshold",
            description: "Oracle tolerance counterexample offsets are outside the accepted threshold"
        ) { context in
            context.subject.derivation.counterexampleOffset > context.subject.threshold
                ? []
                : [
                    error(
                        ruleID: "oracle-tolerance.derivation.counterexample-threshold",
                        description: "Oracle tolerance counterexample offsets are outside the accepted threshold",
                        path: context.codingPath
                            .appending(.key("derivation"))
                            .appending(.key("counterexampleOffset")),
                        evidence: context.subject.id
                    ),
                ]
        }
    }

    public static var toleranceWitnessMatchesDerivationStatus:
        Validation<LottieOracleToleranceLedger, LottieOracleToleranceLedger.Tolerance>
    {
        Validation(
            ruleID: "oracle-tolerance.derivation.witness-status",
            description: "Oracle tolerance witness status matches derived or assumed derivation status"
        ) { context in
            let expectedStatus: LottieClaimWitnessStatus = context.subject.derivation.status == .derived ? .witnessed : .asserted
            return context.subject.witness.status == expectedStatus
                ? []
                : [
                    error(
                        ruleID: "oracle-tolerance.witness.status",
                        description: "Oracle tolerance witness status matches derived or assumed derivation status",
                        path: context.codingPath
                            .appending(.key("witness"))
                            .appending(.key("status")),
                        evidence: context.subject.id
                    ),
                ]
        }
    }

    public static var toleranceWitnessClassificationsAreExplicit:
        Validation<LottieOracleToleranceLedger, LottieClaimWitness>
    {
        LottieClaimWitnessValidation.claimWitnessIsExplicit(
            ruleIDPrefix: "oracle-tolerance.witness",
            description: "Oracle tolerance witness classifications state witnessed asserted or blocked evidence"
        )
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

private struct LottieOracleToleranceAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, LottieOracleToleranceLedger) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<LottieOracleToleranceLedger, Subject>) {
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
        in document: LottieOracleToleranceLedger
    ) -> [ValidationError] {
        applyClosure(subject, codingPath, document)
    }
}
