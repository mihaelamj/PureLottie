//
//  AnimatedValue.swift
//  PureLottie
//

/// A cubic-bezier easing handle on one side of a keyframe segment.
///
/// Lottie serializes handles as `{x, y}` where each component may be a scalar
/// or a per-dimension array; the first dimension is used, matching how every
/// mainstream player eases multi-dimensional values with a single curve.
public struct EasingHandle: Decodable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    private enum CodingKeys: String, CodingKey {
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try Self.component(in: container, key: .x)
        y = try Self.component(in: container, key: .y)
    }

    private static func component(in container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Double {
        if let scalar = try? container.decode(Double.self, forKey: key) {
            return scalar
        }
        let array = try container.decode([Double].self, forKey: key)
        return array.first ?? 0
    }
}

/// One keyframe of an animated property: the frame `t` it starts at, the
/// segment's start value `s` (the end value is the next keyframe's `s`; legacy
/// files also carry it as `e`), the easing handles, and the hold flag.
public struct LottieKeyframe<Value: Decodable & Sendable & Equatable>: Decodable, Sendable, Equatable {
    public var time: Double
    public var startValue: Value?
    public var endValue: Value?
    public var easeIn: EasingHandle?
    public var easeOut: EasingHandle?
    /// Spatial out/in tangents on position keyframes (`to`/`ti`), relative to
    /// the keyframe values; present when the motion path curves.
    public var spatialOut: [Double]?
    public var spatialIn: [Double]?
    public var isHold: Bool

    private enum CodingKeys: String, CodingKey {
        case time = "t"
        case startValue = "s"
        case endValue = "e"
        case easeIn = "i"
        case easeOut = "o"
        case spatialOut = "to"
        case spatialIn = "ti"
        case hold = "h"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(Double.self, forKey: .time)
        startValue = try container.decodeIfPresent(Value.self, forKey: .startValue)
        endValue = try container.decodeIfPresent(Value.self, forKey: .endValue)
        easeIn = try? container.decodeIfPresent(EasingHandle.self, forKey: .easeIn)
        easeOut = try? container.decodeIfPresent(EasingHandle.self, forKey: .easeOut)
        spatialOut = try? container.decodeIfPresent([Double].self, forKey: .spatialOut)
        spatialIn = try? container.decodeIfPresent([Double].self, forKey: .spatialIn)
        isHold = try (container.decodeIfPresent(Int.self, forKey: .hold) ?? 0) == 1
    }
}

/// A scalar property: either a fixed value or keyframes over it.
///
/// Lottie writes the fixed form as `{a: 0, k: value}` where `value` may also be
/// a single-element array, and the keyframed form as `{a: 1, k: [keyframes]}`
/// whose `s` values are single-element arrays.
public enum AnimatedDouble: Sendable, Equatable {
    case fixed(Double)
    case keyframed([LottieKeyframe<[Double]>])

    /// The fixed value, or the first keyframe's start value for a keyframed
    /// property (the value before any animation progresses).
    public var initialValue: Double {
        switch self {
        case let .fixed(value):
            value
        case let .keyframed(keyframes):
            keyframes.first?.startValue?.first ?? 0
        }
    }

    public var isAnimated: Bool {
        if case .keyframed = self { return true }
        return false
    }
}

extension AnimatedDouble: Decodable {
    private enum CodingKeys: String, CodingKey {
        case animated = "a"
        case value = "k"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let keyframes = try? container.decode([LottieKeyframe<[Double]>].self, forKey: .value) {
            self = .keyframed(keyframes)
        } else if let scalar = try? container.decode(Double.self, forKey: .value) {
            self = .fixed(scalar)
        } else {
            let array = try container.decode([Double].self, forKey: .value)
            self = .fixed(array.first ?? 0)
        }
    }
}

/// A multi-dimensional property (positions, scales, colors): a fixed vector or
/// keyframes over it.
public enum AnimatedVector: Sendable, Equatable {
    case fixed([Double])
    case keyframed([LottieKeyframe<[Double]>])

    public var initialValue: [Double] {
        switch self {
        case let .fixed(value):
            value
        case let .keyframed(keyframes):
            keyframes.first?.startValue ?? []
        }
    }

    public var isAnimated: Bool {
        if case .keyframed = self { return true }
        return false
    }
}

extension AnimatedVector: Decodable {
    private enum CodingKeys: String, CodingKey {
        case animated = "a"
        case value = "k"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let keyframes = try? container.decode([LottieKeyframe<[Double]>].self, forKey: .value) {
            self = .keyframed(keyframes)
        } else {
            self = try .fixed(container.decode([Double].self, forKey: .value))
        }
    }
}

/// A bezier-path property: a fixed shape or keyframes morphing it.
public enum AnimatedBezier: Sendable, Equatable {
    case fixed(LottieBezier)
    case keyframed([LottieKeyframe<[LottieBezier]>])

    public var initialValue: LottieBezier? {
        switch self {
        case let .fixed(value):
            value
        case let .keyframed(keyframes):
            keyframes.first?.startValue?.first
        }
    }

    public var isAnimated: Bool {
        if case .keyframed = self { return true }
        return false
    }
}

extension AnimatedBezier: Decodable {
    private enum CodingKeys: String, CodingKey {
        case animated = "a"
        case value = "k"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let bezier = try? container.decode(LottieBezier.self, forKey: .value) {
            self = .fixed(bezier)
        } else {
            self = try .keyframed(container.decode([LottieKeyframe<[LottieBezier]>].self, forKey: .value))
        }
    }
}
