/// A 1-based location in a source file.
public struct SourceLocation: Codable, Sendable, Equatable, CustomStringConvertible {
    public let offset: Int
    public let line: Int
    public let column: Int

    public init(offset: Int, line: Int, column: Int) {
        self.offset = offset
        self.line = line
        self.column = column
    }

    public var description: String {
        "\(line):\(column)"
    }
}

/// A half-open range in source text.
public struct SourceRange: Codable, Sendable, Equatable, CustomStringConvertible {
    public let start: SourceLocation
    public let end: SourceLocation

    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start
        self.end = end
    }

    public var description: String {
        "\(start)-\(end)"
    }
}

/// A JSON path rooted at `$`, used by parser and validation diagnostics.
public struct JSONPath: Codable, Sendable, Hashable, CustomStringConvertible {
    public private(set) var components: [Component]

    public enum Component: Codable, Sendable, Hashable, CustomStringConvertible {
        case key(String)
        case index(Int)

        private enum CodingKeys: String, CodingKey {
            case kind
            case value
        }

        private enum Kind: String, Codable {
            case key
            case index
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .key:
                self = try .key(container.decode(String.self, forKey: .value))
            case .index:
                self = try .index(container.decode(Int.self, forKey: .value))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .key(value):
                try container.encode(Kind.key, forKey: .kind)
                try container.encode(value, forKey: .value)
            case let .index(value):
                try container.encode(Kind.index, forKey: .kind)
                try container.encode(value, forKey: .value)
            }
        }

        public var description: String {
            switch self {
            case let .key(value):
                ".\(value)"
            case let .index(value):
                "[\(value)]"
            }
        }
    }

    public init(_ components: [Component] = []) {
        self.components = components
    }

    public func appending(_ component: Component) -> JSONPath {
        var copy = self
        copy.components.append(component)
        return copy
    }

    public var description: String {
        guard !components.isEmpty else { return "$" }
        return "$" + components.map(\.description).joined()
    }
}

extension JSONPath.Component: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .key(value)
    }
}
