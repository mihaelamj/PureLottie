//
//  AnimatedValue.swift
//  PureLottie
//

/// A cubic-bezier easing handle on one side of a keyframe segment.
///
/// Lottie serializes handles as `{x, y}` where each component may be a scalar
/// or a per-dimension array. `x` and `y` expose the first component for scalar
/// call sites; vector evaluators can use the indexed accessors.
public struct EasingHandle: Decodable, Sendable, Equatable {
    public var xComponents: [Double]
    public var yComponents: [Double]

    public var x: Double {
        get { Self.component(in: xComponents, at: 0) }
        set { Self.replaceFirstComponent(in: &xComponents, with: newValue) }
    }

    public var y: Double {
        get { Self.component(in: yComponents, at: 0) }
        set { Self.replaceFirstComponent(in: &yComponents, with: newValue) }
    }

    public init(x: Double, y: Double) {
        xComponents = [x]
        yComponents = [y]
    }

    private enum CodingKeys: String, CodingKey {
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        xComponents = try Self.components(in: container, key: .x)
        yComponents = try Self.components(in: container, key: .y)
    }

    public func xComponent(_ index: Int) -> Double {
        Self.component(in: xComponents, at: index)
    }

    public func yComponent(_ index: Int) -> Double {
        Self.component(in: yComponents, at: index)
    }

    private static func components(in container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> [Double] {
        if let scalar = try? container.decode(Double.self, forKey: key) {
            return [scalar]
        }
        return try container.decode([Double].self, forKey: key)
    }

    private static func component(in components: [Double], at index: Int) -> Double {
        if components.indices.contains(index) { return components[index] }
        return components.first ?? 0
    }

    private static func replaceFirstComponent(in components: inout [Double], with value: Double) {
        if components.isEmpty {
            components = [value]
        } else {
            components[0] = value
        }
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
        startValue = try Self.decodeValueIfPresent(in: container, key: .startValue)
        endValue = try Self.decodeValueIfPresent(in: container, key: .endValue)
        easeIn = try container.decodeIfPresent(EasingHandle.self, forKey: .easeIn)
        easeOut = try container.decodeIfPresent(EasingHandle.self, forKey: .easeOut)
        spatialOut = try container.decodeIfPresent([Double].self, forKey: .spatialOut)
        spatialIn = try container.decodeIfPresent([Double].self, forKey: .spatialIn)
        isHold = try (container.decodeIfPresent(Int.self, forKey: .hold) ?? 0) == 1
    }

    private static func decodeValueIfPresent(in container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Value? {
        if Value.self == [Double].self {
            if let array = try? container.decodeIfPresent([Double].self, forKey: key) {
                return array as? Value
            }
            if let scalar = try? container.decodeIfPresent(Double.self, forKey: key) {
                return [scalar] as? Value
            }
        }
        return try container.decodeIfPresent(Value.self, forKey: key)
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
