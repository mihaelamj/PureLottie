public enum ValidationPhase: String, Codable, Sendable {
    case parse
    case source
    case semantic
    case lowering
}

public enum ValidationSeverity: String, Codable, Sendable {
    case error
    case warning
    case note
}

public enum FeatureClassification: String, Codable, Sendable {
    case exact
    case approximate
    case reported
    case metadata
    case gap
}

public protocol Validatable {}

extension JSONValue: Validatable {}

public struct ValidationContext<Document: Validatable, Subject: Validatable> {
    public let document: Document
    public let subject: Subject
    public let codingPath: JSONPath

    public init(document: Document, subject: Subject, codingPath: JSONPath) {
        self.document = document
        self.subject = subject
        self.codingPath = codingPath
    }
}

public struct Validation<Document: Validatable, Subject: Validatable> {
    public typealias Context = ValidationContext<Document, Subject>
    public typealias Check = (Context) -> [ValidationError]
    public typealias Predicate = (Context) -> Bool

    public let ruleID: String
    public let description: String
    public let phase: ValidationPhase
    private let check: Check
    private let predicate: Predicate

    public init(
        ruleID: String,
        description: String,
        phase: ValidationPhase = .semantic,
        check: @escaping Check,
        when predicate: @escaping Predicate = { _ in true }
    ) {
        self.ruleID = ruleID
        self.description = description
        self.phase = phase
        self.check = check
        self.predicate = predicate
    }

    public init(
        ruleID: String,
        description: String,
        phase: ValidationPhase = .semantic,
        check: @escaping (Context) -> Bool,
        when predicate: @escaping Predicate = { _ in true }
    ) {
        self.init(
            ruleID: ruleID,
            description: description,
            phase: phase,
            check: { context in
                guard !check(context) else { return [] }
                return [
                    ValidationError(
                        ruleID: ruleID,
                        reason: "Failed to satisfy: \(description)",
                        at: context.codingPath,
                        phase: phase
                    ),
                ]
            },
            when: predicate
        )
    }

    public func apply(to subject: Subject, at codingPath: JSONPath, in document: Document) -> [ValidationError] {
        let context = Context(document: document, subject: subject, codingPath: codingPath)
        guard predicate(context) else { return [] }
        return check(context)
    }
}

struct AnyValidation<Document: Validatable> {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, Document) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<Document, Subject>) {
        ruleID = validation.ruleID
        description = validation.description
        applyClosure = { input, path, document in
            guard let subject = input as? Subject else { return [] }
            return validation.apply(to: subject, at: path, in: document)
        }
    }

    func apply(to subject: any Validatable, at codingPath: JSONPath, in document: Document) -> [ValidationError] {
        applyClosure(subject, codingPath, document)
    }
}

public struct ValidationError: Codable, Error, Sendable, Equatable, CustomStringConvertible {
    public let ruleID: String
    public let reason: String
    public let codingPath: JSONPath
    public let range: SourceRange?
    public let severity: ValidationSeverity
    public let phase: ValidationPhase
    public let classification: FeatureClassification
    public let evidence: String?

    public init(
        ruleID: String,
        reason: String,
        at codingPath: JSONPath,
        range: SourceRange? = nil,
        severity: ValidationSeverity = .error,
        phase: ValidationPhase = .semantic,
        classification: FeatureClassification = .reported,
        evidence: String? = nil
    ) {
        self.ruleID = ruleID
        self.reason = reason
        self.codingPath = codingPath
        self.range = range
        self.severity = severity
        self.phase = phase
        self.classification = classification
        self.evidence = evidence
    }

    public var description: String {
        let trimmedReason = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
        if codingPath.components.isEmpty {
            return "\(trimmedReason) at root of document"
        }
        return "\(trimmedReason) at path: \(codingPath)"
    }
}

public struct ValidationErrorCollection: Codable, Error, Sendable, Equatable {
    public let values: [ValidationError]

    public init(_ values: [ValidationError]) {
        self.values = values
    }
}

public func take<Document: Validatable, Subject: Validatable, Value>(
    _ keyPath: KeyPath<Subject, Value>,
    _ predicate: @escaping (Value) -> Bool
) -> (ValidationContext<Document, Subject>) -> Bool {
    { context in
        predicate(context.subject[keyPath: keyPath])
    }
}

public func && <Document: Validatable, Subject: Validatable>(
    lhs: @escaping (ValidationContext<Document, Subject>) -> Bool,
    rhs: @escaping (ValidationContext<Document, Subject>) -> Bool
) -> (ValidationContext<Document, Subject>) -> Bool {
    { context in
        lhs(context) && rhs(context)
    }
}

public func || <Document: Validatable, Subject: Validatable>(
    lhs: @escaping (ValidationContext<Document, Subject>) -> Bool,
    rhs: @escaping (ValidationContext<Document, Subject>) -> Bool
) -> (ValidationContext<Document, Subject>) -> Bool {
    { context in
        lhs(context) || rhs(context)
    }
}
