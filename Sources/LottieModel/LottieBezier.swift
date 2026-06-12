//
//  LottieBezier.swift
//  PureLottie
//

/// A cubic bezier path as Lottie serializes it: vertices plus per-vertex
/// in/out tangents that are *relative* to their vertex, and a closed flag.
///
/// The segment from vertex `n` to `n + 1` is the cubic curve with control
/// points `vertices[n] + outTangents[n]` and `vertices[n+1] + inTangents[n+1]`.
public struct LottieBezier: Decodable, Sendable, Equatable {
    public var isClosed: Bool
    public var vertices: [[Double]]
    public var inTangents: [[Double]]
    public var outTangents: [[Double]]

    public init(
        isClosed: Bool,
        vertices: [[Double]],
        inTangents: [[Double]],
        outTangents: [[Double]]
    ) {
        self.isClosed = isClosed
        self.vertices = vertices
        self.inTangents = inTangents
        self.outTangents = outTangents
    }

    private enum CodingKeys: String, CodingKey {
        case isClosed = "c"
        case vertices = "v"
        case inTangents = "i"
        case outTangents = "o"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false
        vertices = try container.decode([[Double]].self, forKey: .vertices)
        inTangents = try container.decodeIfPresent([[Double]].self, forKey: .inTangents) ?? []
        outTangents = try container.decodeIfPresent([[Double]].self, forKey: .outTangents) ?? []
    }
}
