//
//  LottieAnimation.swift
//  PureLottie
//

import Foundation

/// The root of a Lottie document: the main composition's frame window, size,
/// layers, and reusable assets. All times are frames at `frameRate`.
public struct LottieAnimation: Decodable, Sendable, Equatable {
    public var version: String?
    public var name: String?
    public var frameRate: Double
    public var inPoint: Double
    public var outPoint: Double
    public var width: Double
    public var height: Double
    public var layers: [LottieLayer]
    public var assets: [LottieAsset]

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case name = "nm"
        case frameRate = "fr"
        case inPoint = "ip"
        case outPoint = "op"
        case width = "w"
        case height = "h"
        case layers
        case assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        frameRate = try container.decode(Double.self, forKey: .frameRate)
        inPoint = try container.decodeIfPresent(Double.self, forKey: .inPoint) ?? 0
        outPoint = try container.decode(Double.self, forKey: .outPoint)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        layers = try container.decode([LottieLayer].self, forKey: .layers)
        assets = try container.decodeIfPresent([LottieAsset].self, forKey: .assets) ?? []
    }

    /// Decodes a Lottie JSON document.
    public static func decode(from data: Data) throws -> LottieAnimation {
        try JSONDecoder().decode(LottieAnimation.self, from: data)
    }

    /// The precomposition asset with the given id, if any.
    public func precomposition(id: String) -> LottieAsset? {
        assets.first { $0.id == id && $0.layers != nil }
    }
}

/// A reusable asset. Precompositions carry `layers`; image assets carry only
/// their identity here (decoding the pixel source is out of the model's scope).
public struct LottieAsset: Decodable, Sendable, Equatable {
    public var id: String
    public var name: String?
    public var layers: [LottieLayer]?
    public var width: Double?
    public var height: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case name = "nm"
        case layers
        case width = "w"
        case height = "h"
    }
}
