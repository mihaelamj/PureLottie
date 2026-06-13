import Foundation

public struct JSONParseResult: Sendable {
    public let value: JSONValue?
    public let diagnostics: [ValidationError]

    public init(value: JSONValue?, diagnostics: [ValidationError]) {
        self.value = value
        self.diagnostics = diagnostics
    }
}

public indirect enum JSONValue: Sendable, Equatable {
    case object([JSONObjectMember], SourceRange)
    case array([JSONValue], SourceRange)
    case string(String, SourceRange)
    case number(Double, SourceRange)
    case bool(Bool, SourceRange)
    case null(SourceRange)

    public var range: SourceRange {
        switch self {
        case let .object(_, range),
             let .array(_, range),
             let .string(_, range),
             let .number(_, range),
             let .bool(_, range),
             let .null(range):
            range
        }
    }
}

public struct JSONObjectMember: Sendable, Equatable {
    public let key: String
    public let keyRange: SourceRange
    public let value: JSONValue

    public init(key: String, keyRange: SourceRange, value: JSONValue) {
        self.key = key
        self.keyRange = keyRange
        self.value = value
    }
}

public extension JSONValue {
    var objectMembers: [JSONObjectMember]? {
        if case let .object(members, _) = self { return members }
        return nil
    }

    var arrayValues: [JSONValue]? {
        if case let .array(values, _) = self { return values }
        return nil
    }

    var stringValue: String? {
        if case let .string(value, _) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case let .number(value, _) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value, _) = self { return value }
        return nil
    }

    func member(_ key: String) -> JSONValue? {
        objectMembers?.last(where: { $0.key == key })?.value
    }

    func memberRange(_ key: String) -> SourceRange? {
        objectMembers?.last(where: { $0.key == key })?.keyRange
    }

    func value(at path: JSONPath) -> JSONValue? {
        path.components.reduce(self as JSONValue?) { current, component in
            guard let current else { return nil }
            switch component {
            case let .key(key):
                return current.member(key)
            case let .index(index):
                guard let values = current.arrayValues, values.indices.contains(index) else { return nil }
                return values[index]
            }
        }
    }
}

public struct LottieSourceDocument: Sendable, Validatable {
    public let source: JSONValue
    public let data: Data

    public init(source: JSONValue, data: Data) {
        self.source = source
        self.data = data
    }

    public static func parse(_ source: String) throws -> LottieSourceDocument {
        let maxSourceLength = 20_000_000
        if source.count > maxSourceLength {
            throw ValidationErrorCollection([
                ValidationError(
                    ruleID: "json.source.size-limit-exceeded",
                    reason: "Source length exceeds the maximum limit of \(maxSourceLength) characters.",
                    at: JSONPath(),
                    phase: .parse
                ),
            ])
        }
        let result = JSONParser().parse(source)
        if !result.diagnostics.isEmpty {
            throw ValidationErrorCollection(result.diagnostics)
        }
        guard let value = result.value else {
            throw ValidationErrorCollection([
                ValidationError(
                    ruleID: "json.parse.empty-document",
                    reason: "JSON document must contain a root value.",
                    at: JSONPath(),
                    phase: .parse
                ),
            ])
        }
        return LottieSourceDocument(source: value, data: Data(source.utf8))
    }

    public static func parse(_ data: Data) throws -> LottieSourceDocument {
        guard let source = String(data: data, encoding: .utf8) else {
            throw ValidationErrorCollection([
                ValidationError(
                    ruleID: "json.source.utf8",
                    reason: "Lottie JSON source must be valid UTF-8.",
                    at: JSONPath(),
                    phase: .parse
                ),
            ])
        }
        return try parse(source)
    }

    public func decodeAnimation() throws -> LottieAnimation {
        try LottieAnimation.decode(from: data)
    }
}

public extension LottieAnimation {
    /// Parses, validates, then decodes a Lottie document.
    ///
    /// The existing `decode(from:)` API remains the raw format decoder. This
    /// entry point is the compiler-front-end gate for callers that must reject
    /// silent-risk features before import.
    static func decodeValidated(
        from data: Data,
        using validator: LottieValidator = LottieValidator()
    ) throws -> LottieAnimation {
        let document = try LottieSourceDocument.parse(data)
        try document.validate(using: validator)
        return try document.decodeAnimation()
    }
}
