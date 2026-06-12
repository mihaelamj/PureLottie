public struct JSONParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> JSONParseResult {
        let lexed = JSONLexer(source: source).tokenize()
        var parser = Parser(tokens: lexed.tokens, diagnostics: lexed.diagnostics)
        return parser.parse()
    }
}

struct JSONToken: Equatable {
    let kind: JSONTokenKind
    let range: SourceRange
}

enum JSONTokenKind: Equatable {
    case leftBrace
    case rightBrace
    case leftBracket
    case rightBracket
    case colon
    case comma
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case endOfFile
}

struct JSONLexer {
    private let scalars: [UnicodeScalar]

    init(source: String) {
        scalars = Array(source.unicodeScalars)
    }

    func tokenize() -> (tokens: [JSONToken], diagnostics: [ValidationError]) {
        var scanner = JSONScanner(scalars: scalars)
        return scanner.tokenize()
    }
}

private struct JSONScanner {
    let scalars: [UnicodeScalar]
    var index = 0
    var line = 1
    var column = 1
    var tokens: [JSONToken] = []
    var diagnostics: [ValidationError] = []

    mutating func tokenize() -> (tokens: [JSONToken], diagnostics: [ValidationError]) {
        while let scalar = peek() {
            switch scalar {
            case " ", "\t", "\r", "\n":
                advance()
            case "{":
                append(.leftBrace, consuming: 1)
            case "}":
                append(.rightBrace, consuming: 1)
            case "[":
                append(.leftBracket, consuming: 1)
            case "]":
                append(.rightBracket, consuming: 1)
            case ":":
                append(.colon, consuming: 1)
            case ",":
                append(.comma, consuming: 1)
            case "\"":
                scanString()
            case "-", "0" ... "9":
                scanNumber()
            case "t":
                scanKeyword("true", .bool(true))
            case "f":
                scanKeyword("false", .bool(false))
            case "n":
                scanKeyword("null", .null)
            default:
                let start = location()
                advance()
                emit(
                    ruleID: "json.lex.unexpected-character",
                    range: SourceRange(start: start, end: location()),
                    message: "Unexpected character in JSON source."
                )
            }
        }

        let eof = location()
        tokens.append(JSONToken(kind: .endOfFile, range: SourceRange(start: eof, end: eof)))
        return (tokens, diagnostics)
    }

    mutating func append(_ kind: JSONTokenKind, consuming count: Int) {
        let start = location()
        for _ in 0 ..< count {
            advance()
        }
        tokens.append(JSONToken(kind: kind, range: SourceRange(start: start, end: location())))
    }

    mutating func scanKeyword(_ spelling: String, _ kind: JSONTokenKind) {
        let start = location()
        for expected in spelling.unicodeScalars {
            guard peek() == expected else {
                emit(
                    ruleID: "json.lex.invalid-keyword",
                    range: SourceRange(start: start, end: location()),
                    message: "Invalid JSON keyword."
                )
                return
            }
            advance()
        }
        tokens.append(JSONToken(kind: kind, range: SourceRange(start: start, end: location())))
    }

    mutating func scanString() {
        let start = location()
        advance()
        var result = ""

        while let scalar = peek() {
            if scalar == "\"" {
                advance()
                tokens.append(JSONToken(kind: .string(result), range: SourceRange(start: start, end: location())))
                return
            }

            if scalar == "\\" {
                scanEscape(start: start, into: &result)
            } else if scalar.value < 0x20 {
                let badStart = location()
                advance()
                emit(
                    ruleID: "json.lex.control-character",
                    range: SourceRange(start: badStart, end: location()),
                    message: "Control characters must be escaped inside strings."
                )
            } else {
                result.unicodeScalars.append(scalar)
                advance()
            }
        }

        emit(
            ruleID: "json.lex.unterminated-string",
            range: SourceRange(start: start, end: location()),
            message: "Unterminated JSON string."
        )
    }

    mutating func scanEscape(start: SourceLocation, into result: inout String) {
        advance()
        guard let escaped = peek() else {
            emit(
                ruleID: "json.lex.unterminated-string",
                range: SourceRange(start: start, end: location()),
                message: "Unterminated string escape."
            )
            return
        }

        switch escaped {
        case "\"", "\\", "/":
            result.unicodeScalars.append(escaped)
            advance()
        case "b":
            result.unicodeScalars.append("\u{0008}")
            advance()
        case "f":
            result.unicodeScalars.append("\u{000C}")
            advance()
        case "n":
            result.unicodeScalars.append("\n")
            advance()
        case "r":
            result.unicodeScalars.append("\r")
            advance()
        case "t":
            result.unicodeScalars.append("\t")
            advance()
        case "u":
            advance()
            scanUnicodeEscape(start: start, into: &result)
        default:
            let escapeStart = location()
            advance()
            emit(
                ruleID: "json.lex.invalid-escape",
                range: SourceRange(start: escapeStart, end: location()),
                message: "Invalid JSON escape sequence."
            )
        }
    }

    mutating func scanUnicodeEscape(start: SourceLocation, into result: inout String) {
        var value: UInt32 = 0
        for _ in 0 ..< 4 {
            guard let scalar = peek(), let digit = scalar.jsonHexDigitValue else {
                emit(
                    ruleID: "json.lex.invalid-unicode-escape",
                    range: SourceRange(start: start, end: location()),
                    message: "Invalid Unicode escape."
                )
                return
            }
            value = value * 16 + UInt32(digit)
            advance()
        }

        guard let scalar = UnicodeScalar(value) else {
            emit(
                ruleID: "json.lex.invalid-unicode-scalar",
                range: SourceRange(start: start, end: location()),
                message: "Unicode escape is not a valid scalar."
            )
            return
        }
        result.unicodeScalars.append(scalar)
    }

    mutating func scanNumber() {
        let start = location()
        var spelling = ""

        if peek() == "-" {
            spelling.append("-")
            advance()
        }

        guard let first = peek(), ("0" ... "9").contains(first) else {
            emit(
                ruleID: "json.lex.invalid-number",
                range: SourceRange(start: start, end: location()),
                message: "Expected digit after minus sign."
            )
            return
        }

        if first == "0" {
            spelling.append("0")
            advance()
        } else {
            while let scalar = peek(), ("0" ... "9").contains(scalar) {
                spelling.unicodeScalars.append(scalar)
                advance()
            }
        }

        if peek() == "." {
            spelling.append(".")
            advance()
            guard let scalar = peek(), ("0" ... "9").contains(scalar) else {
                emit(
                    ruleID: "json.lex.invalid-number",
                    range: SourceRange(start: start, end: location()),
                    message: "Expected digit after decimal point."
                )
                return
            }
            while let scalar = peek(), ("0" ... "9").contains(scalar) {
                spelling.unicodeScalars.append(scalar)
                advance()
            }
        }

        if peek() == "e" || peek() == "E" {
            spelling.unicodeScalars.append(peek() ?? "e")
            advance()
            if peek() == "+" || peek() == "-" {
                spelling.unicodeScalars.append(peek() ?? "+")
                advance()
            }
            guard let scalar = peek(), ("0" ... "9").contains(scalar) else {
                emit(
                    ruleID: "json.lex.invalid-number",
                    range: SourceRange(start: start, end: location()),
                    message: "Expected exponent digits."
                )
                return
            }
            while let scalar = peek(), ("0" ... "9").contains(scalar) {
                spelling.unicodeScalars.append(scalar)
                advance()
            }
        }

        guard let number = Double(spelling) else {
            emit(
                ruleID: "json.lex.invalid-number",
                range: SourceRange(start: start, end: location()),
                message: "Invalid JSON number."
            )
            return
        }
        tokens.append(JSONToken(kind: .number(number), range: SourceRange(start: start, end: location())))
    }

    func peek() -> UnicodeScalar? {
        scalars.indices.contains(index) ? scalars[index] : nil
    }

    mutating func advance() {
        guard let scalar = peek() else { return }
        index += 1
        if scalar == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }

    func location() -> SourceLocation {
        SourceLocation(offset: index, line: line, column: column)
    }

    mutating func emit(ruleID: String, range: SourceRange, message: String) {
        diagnostics.append(
            ValidationError(
                ruleID: ruleID,
                reason: message,
                at: JSONPath(),
                range: range,
                phase: .parse
            )
        )
    }
}

private extension UnicodeScalar {
    var jsonHexDigitValue: UInt32? {
        switch value {
        case 48 ... 57:
            value - 48
        case 65 ... 70:
            value - 55
        case 97 ... 102:
            value - 87
        default:
            nil
        }
    }
}

private struct Parser {
    let tokens: [JSONToken]
    var index = 0
    var diagnostics: [ValidationError]

    mutating func parse() -> JSONParseResult {
        let value = parseValue(path: JSONPath())
        if !check(.endOfFile) {
            emit(
                ruleID: "json.parse.trailing-input",
                path: JSONPath(),
                range: current.range,
                message: "Unexpected input after JSON document."
            )
        }
        return JSONParseResult(value: value, diagnostics: diagnostics)
    }

    mutating func parseValue(path: JSONPath) -> JSONValue? {
        let token = current
        switch token.kind {
        case .leftBrace:
            return parseObject(path: path)
        case .leftBracket:
            return parseArray(path: path)
        case let .string(value):
            advance()
            return .string(value, token.range)
        case let .number(value):
            advance()
            return .number(value, token.range)
        case let .bool(value):
            advance()
            return .bool(value, token.range)
        case .null:
            advance()
            return .null(token.range)
        case .endOfFile:
            emit(
                ruleID: "json.parse.unexpected-eof",
                path: path,
                range: token.range,
                message: "Unexpected end of file."
            )
            return nil
        default:
            emit(
                ruleID: "json.parse.expected-value",
                path: path,
                range: token.range,
                message: "Expected JSON value."
            )
            advance()
            return nil
        }
    }

    mutating func parseObject(path: JSONPath) -> JSONValue? {
        let start = consume(.leftBrace)
        var members: [JSONObjectMember] = []

        if match(.rightBrace) {
            let end = previous.range
            return .object(members, SourceRange(start: start.range.start, end: end.end))
        }

        while !check(.endOfFile) {
            guard case let .string(key) = current.kind else {
                emit(
                    ruleID: "json.parse.expected-object-key",
                    path: path,
                    range: current.range,
                    message: "Expected string key in object."
                )
                synchronizeObject()
                break
            }

            let keyRange = current.range
            advance()
            guard match(.colon) else {
                emit(
                    ruleID: "json.parse.expected-colon",
                    path: path.appending(.key(key)),
                    range: current.range,
                    message: "Expected ':' after object key."
                )
                synchronizeObject()
                break
            }

            let valuePath = path.appending(.key(key))
            if let value = parseValue(path: valuePath) {
                members.append(JSONObjectMember(key: key, keyRange: keyRange, value: value))
            }

            if match(.rightBrace) {
                let end = previous.range
                return .object(members, SourceRange(start: start.range.start, end: end.end))
            }

            guard match(.comma) else {
                emit(
                    ruleID: "json.parse.expected-comma-or-object-end",
                    path: path,
                    range: current.range,
                    message: "Expected ',' or '}' after object member."
                )
                synchronizeObject()
                break
            }
        }

        let end = previous.range
        return .object(members, SourceRange(start: start.range.start, end: end.end))
    }

    mutating func parseArray(path: JSONPath) -> JSONValue? {
        let start = consume(.leftBracket)
        var values: [JSONValue] = []
        var elementIndex = 0

        if match(.rightBracket) {
            let end = previous.range
            return .array(values, SourceRange(start: start.range.start, end: end.end))
        }

        while !check(.endOfFile) {
            if let value = parseValue(path: path.appending(.index(elementIndex))) {
                values.append(value)
            }
            elementIndex += 1

            if match(.rightBracket) {
                let end = previous.range
                return .array(values, SourceRange(start: start.range.start, end: end.end))
            }

            guard match(.comma) else {
                emit(
                    ruleID: "json.parse.expected-comma-or-array-end",
                    path: path,
                    range: current.range,
                    message: "Expected ',' or ']' after array element."
                )
                synchronizeArray()
                break
            }
        }

        let end = previous.range
        return .array(values, SourceRange(start: start.range.start, end: end.end))
    }

    mutating func synchronizeObject() {
        while !check(.endOfFile), !check(.rightBrace) {
            advance()
        }
        _ = match(.rightBrace)
    }

    mutating func synchronizeArray() {
        while !check(.endOfFile), !check(.rightBracket) {
            advance()
        }
        _ = match(.rightBracket)
    }

    var current: JSONToken {
        tokens[min(index, tokens.count - 1)]
    }

    var previous: JSONToken {
        tokens[max(0, min(index - 1, tokens.count - 1))]
    }

    mutating func advance() {
        if index < tokens.count - 1 {
            index += 1
        }
    }

    @discardableResult
    mutating func consume(_ kind: JSONTokenKind) -> JSONToken {
        let token = current
        if token.kind == kind {
            advance()
        }
        return token
    }

    mutating func match(_ kind: JSONTokenKind) -> Bool {
        guard check(kind) else { return false }
        advance()
        return true
    }

    func check(_ kind: JSONTokenKind) -> Bool {
        current.kind == kind
    }

    mutating func emit(ruleID: String, path: JSONPath, range: SourceRange, message: String) {
        diagnostics.append(
            ValidationError(
                ruleID: ruleID,
                reason: message,
                at: path,
                range: range,
                phase: .parse
            )
        )
    }
}
