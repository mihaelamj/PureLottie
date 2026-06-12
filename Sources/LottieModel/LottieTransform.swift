//
//  LottieTransform.swift
//  PureLottie
//

/// A layer transform (`ks`): anchor and position in points, scale in percent,
/// rotation/skew/orientation in degrees, opacity in percent.
public struct LottieTransform: Decodable, Sendable, Equatable {
    public var anchor: AnimatedVector?
    public var position: LottiePosition?
    public var scale: AnimatedVector?
    public var rotation: AnimatedDouble?
    public var rotationX: AnimatedDouble?
    public var rotationY: AnimatedDouble?
    public var rotationZ: AnimatedDouble?
    public var orientation: AnimatedVector?
    public var skew: AnimatedDouble?
    public var skewAxis: AnimatedDouble?
    public var opacity: AnimatedDouble?

    private enum CodingKeys: String, CodingKey {
        case anchor = "a"
        case position = "p"
        case scale = "s"
        case rotation = "r"
        case rotationX = "rx"
        case rotationY = "ry"
        case rotationZ = "rz"
        case orientation = "or"
        case skew = "sk"
        case skewAxis = "sa"
        case opacity = "o"
    }
}

/// A position property, which Lottie writes either as one animated vector or
/// split per axis (`{s: true, x: ..., y: ...}`).
public enum LottiePosition: Sendable, Equatable {
    case vector(AnimatedVector)
    case split(x: AnimatedDouble, y: AnimatedDouble, z: AnimatedDouble?)

    public var initialPoint: (x: Double, y: Double) {
        switch self {
        case let .vector(vector):
            let value = vector.initialValue
            return (value.count > 0 ? value[0] : 0, value.count > 1 ? value[1] : 0)
        case let .split(x, y, _):
            return (x.initialValue, y.initialValue)
        }
    }

    public var initialValue: [Double] {
        switch self {
        case let .vector(vector):
            vector.initialValue
        case let .split(x, y, z):
            [x.initialValue, y.initialValue, z?.initialValue ?? 0]
        }
    }

    public var isAnimated: Bool {
        switch self {
        case let .vector(vector):
            vector.isAnimated
        case let .split(x, y, z):
            x.isAnimated || y.isAnimated || z?.isAnimated == true
        }
    }
}

extension LottiePosition: Decodable {
    private enum CodingKeys: String, CodingKey {
        case split = "s"
        case x, y, z
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if (try? container.decode(Bool.self, forKey: .split)) == true {
            self = try .split(
                x: container.decode(AnimatedDouble.self, forKey: .x),
                y: container.decode(AnimatedDouble.self, forKey: .y),
                z: container.decodeIfPresent(AnimatedDouble.self, forKey: .z)
            )
        } else {
            self = try .vector(AnimatedVector(from: decoder))
        }
    }
}
