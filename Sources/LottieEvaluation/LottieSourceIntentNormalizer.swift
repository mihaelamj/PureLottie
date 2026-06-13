//
//  LottieSourceIntentNormalizer.swift
//  PureLottie
//

import Foundation

/// A single step in a rewrite trace during normalization.
public struct LottieSourceIntentRewriteStep: Codable, Sendable, Equatable {
    public var ruleName: String
    public var description: String
    public var geometryId: String

    public init(ruleName: String, description: String, geometryId: String) {
        self.ruleName = ruleName
        self.description = description
        self.geometryId = geometryId
    }
}

/// The rewrite strategies to execute rules.
public enum LottieSourceIntentRewriteStrategy: String, Codable, Sendable {
    case leftToRight
    case rightToLeft
}

/// A formal, inspectable rewrite rule over Lottie source intent.
public struct LottieSourceIntentRewriteRule: Sendable {
    public let name: String
    public let description: String
    public let apply: @Sendable (LottieSourceIntentGeometry, LottieSourceIntentRewriteStrategy) -> (LottieSourceIntentGeometry, Bool)?

    public init(
        name: String,
        description: String,
        apply: @escaping @Sendable (LottieSourceIntentGeometry, LottieSourceIntentRewriteStrategy) -> (LottieSourceIntentGeometry, Bool)?
    ) {
        self.name = name
        self.description = description
        self.apply = apply
    }
}

private func isIdentityMatrix(_ values: [Double], tolerance: Double = 1e-6) -> Bool {
    guard values.count == 16 else { return false }
    let identity = [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]
    for i in 0 ..< 16 {
        if abs(values[i] - identity[i]) > tolerance {
            return false
        }
    }
    return true
}

private func normalizeTrim(_ trim: LottieSourceIntentTrim) -> (Double, Double) {
    let rawStart = trim.start / 100.0
    let rawEnd = trim.end / 100.0
    var offsetTurns = trim.offset.truncatingRemainder(dividingBy: 360.0) / 360.0
    if offsetTurns < 0 {
        offsetTurns += 1.0
    }

    func shiftClamp(_ val: Double) -> Double {
        if val > 1.0 { return 1.0 + offsetTurns }
        if val < 0.0 { return offsetTurns }
        return val + offsetTurns
    }

    var s = shiftClamp(rawStart)
    var e = shiftClamp(rawEnd)
    if s > e {
        swap(&s, &e)
    }
    s = max(0.0, min(1.0, s))
    e = max(0.0, min(1.0, e))
    return (s, e)
}

public extension LottieSourceIntentRewriteRule {
    /// Rule 1: Identity Transform Removal (transform-identity)
    /// Removes any transform in transformStack that is close to the identity matrix.
    static let transformIdentity = LottieSourceIntentRewriteRule(
        name: "transform-identity",
        description: "Removes identity transforms from the geometry's transform stack."
    ) { geometry, strategy in
        var stack = geometry.transformStack
        let indices = strategy == .leftToRight ? Array(stack.indices) : Array(stack.indices.reversed())
        for i in indices {
            if isIdentityMatrix(stack[i].matrix.values) {
                stack.remove(at: i)
                var newGeom = geometry
                newGeom.transformStack = stack
                return (newGeom, true)
            }
        }
        return nil
    }

    /// Rule 2: Adjacent Transform Composition (transform-compose)
    /// Composes two adjacent transforms in transformStack by matrix multiplication.
    static let transformCompose = LottieSourceIntentRewriteRule(
        name: "transform-compose",
        description: "Composes adjacent transforms in the transform stack using row-vector matrix concatenation."
    ) { geometry, strategy in
        var stack = geometry.transformStack
        guard stack.count >= 2 else { return nil }
        let indices = strategy == .leftToRight ? Array(0 ..< (stack.count - 1)) : Array((0 ..< (stack.count - 1)).reversed())
        for i in indices {
            let t1 = stack[i]
            let t2 = stack[i + 1]

            let m1 = LottieTransformMatrix(values: t1.matrix.values)
            let m2 = LottieTransformMatrix(values: t2.matrix.values)
            let mResult = m1.concatenating(m2)

            do {
                let composedMatrix = try LottieSourceIntentMatrix(values: mResult.values)
                let composedProvenance = LottieSourceIntentProvenance(
                    sourcePath: "\(t1.provenance.sourcePath) * \(t2.provenance.sourcePath)",
                    jsonPath: "\(t1.provenance.jsonPath) * \(t2.provenance.jsonPath)",
                    consumedFields: Array(Set(t1.provenance.consumedFields + t2.provenance.consumedFields)).sorted(),
                    preservedFields: Array(Set(t1.provenance.preservedFields + t2.provenance.preservedFields)).sorted(),
                    unrepresentedFields: Array(Set(t1.provenance.unrepresentedFields + t2.provenance.unrepresentedFields)).sorted()
                )
                let composedTransform = LottieSourceIntentTransform(
                    anchor: [0.0, 0.0, 0.0],
                    position: [mResult.values[12], mResult.values[13], mResult.values[14]],
                    scale: [100.0, 100.0, 100.0],
                    rotationZDegrees: 0.0,
                    is3DLayer: t1.is3DLayer || t2.is3DLayer,
                    matrix: composedMatrix,
                    matrixConvention: t1.matrixConvention,
                    provenance: composedProvenance
                )
                stack[i] = composedTransform
                stack.remove(at: i + 1)
                var newGeom = geometry
                newGeom.transformStack = stack
                return (newGeom, true)
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Rule 3: Identity Trim Removal (trim-identity)
    /// Removes any trim modifier in modifiers that is close to the identity trim (start=0, end=1, offset=0).
    static let trimIdentity = LottieSourceIntentRewriteRule(
        name: "trim-identity",
        description: "Removes identity trims that do not modify the geometry."
    ) { geometry, strategy in
        var mods = geometry.modifiers
        let indices = strategy == .leftToRight ? Array(mods.indices) : Array(mods.indices.reversed())
        for i in indices {
            let mod = mods[i]
            if mod.kind == .trim, let trim = mod.trim {
                let (s, e) = normalizeTrim(trim)
                if abs(s - 0.0) < 1e-6, abs(e - 1.0) < 1e-6 {
                    mods.remove(at: i)
                    var newGeom = geometry
                    newGeom.modifiers = mods
                    return (newGeom, true)
                }
            }
        }
        return nil
    }

    /// Rule 4: Adjacent Trim Composition (trim-compose)
    /// Composes two adjacent static trim modifiers into a single composed trim.
    static let trimCompose = LottieSourceIntentRewriteRule(
        name: "trim-compose",
        description: "Composes adjacent static trim modifiers by mapping relative intervals."
    ) { geometry, strategy in
        var mods = geometry.modifiers
        guard mods.count >= 2 else { return nil }
        let indices = strategy == .leftToRight ? Array(0 ..< (mods.count - 1)) : Array((0 ..< (mods.count - 1)).reversed())
        for i in indices {
            let m1 = mods[i]
            let m2 = mods[i + 1]
            if m1.kind == .trim, let t1 = m1.trim,
               m2.kind == .trim, let t2 = m2.trim,
               !t1.isAnimated, !t2.isAnimated
            {
                let (s1, e1) = normalizeTrim(t1)
                let (s2, e2) = normalizeTrim(t2)

                let s12 = s1 + (e1 - s1) * s2
                let e12 = s1 + (e1 - s1) * e2

                let composedTrim = LottieSourceIntentTrim(
                    start: s12 * 100.0,
                    end: e12 * 100.0,
                    offset: 0.0,
                    multiple: t1.multiple ?? t2.multiple,
                    isAnimated: false
                )
                let composedProvenance = LottieSourceIntentProvenance(
                    sourcePath: "\(m1.provenance.sourcePath) * \(m2.provenance.sourcePath)",
                    jsonPath: "\(m1.provenance.jsonPath) * \(m2.provenance.jsonPath)",
                    consumedFields: Array(Set(m1.provenance.consumedFields + m2.provenance.consumedFields)).sorted(),
                    preservedFields: Array(Set(m1.provenance.preservedFields + m2.provenance.preservedFields)).sorted(),
                    unrepresentedFields: Array(Set(m1.provenance.unrepresentedFields + m2.provenance.unrepresentedFields)).sorted()
                )
                let composedMod = LottieSourceIntentModifier(
                    kind: .trim,
                    trim: composedTrim,
                    provenance: composedProvenance
                )
                mods[i] = composedMod
                mods.remove(at: i + 1)
                var newGeom = geometry
                newGeom.modifiers = mods
                return (newGeom, true)
            }
        }
        return nil
    }
}

/// Normalizer implementing the rewrite rules until a normal form is reached.
public struct LottieSourceIntentNormalizer: Sendable {
    public var maxSteps: Int

    public init(maxSteps: Int = 1000) {
        self.maxSteps = maxSteps
    }

    /// Normalizes a single geometry using the specified rewrite strategy.
    public func normalize(
        _ geometry: LottieSourceIntentGeometry,
        strategy: LottieSourceIntentRewriteStrategy,
        steps: inout [LottieSourceIntentRewriteStep]
    ) -> LottieSourceIntentGeometry {
        var current = geometry
        let rules: [LottieSourceIntentRewriteRule] = [
            .transformIdentity,
            .transformCompose,
            .trimIdentity,
            .trimCompose,
        ]

        var rewritten = true
        var iteration = 0

        while rewritten, iteration < maxSteps {
            rewritten = false
            iteration += 1

            for rule in rules {
                if let (nextGeom, success) = rule.apply(current, strategy), success {
                    steps.append(LottieSourceIntentRewriteStep(
                        ruleName: rule.name,
                        description: rule.description,
                        geometryId: current.id
                    ))
                    current = nextGeom
                    rewritten = true
                    break
                }
            }
        }

        return current
    }

    /// Normalizes a frame's geometries under the given rewrite strategy.
    public func normalize(
        _ frame: LottieSourceIntentFrame,
        strategy: LottieSourceIntentRewriteStrategy
    ) -> (LottieSourceIntentFrame, [LottieSourceIntentRewriteStep]) {
        var steps: [LottieSourceIntentRewriteStep] = []
        var normalizedLayers: [LottieSourceIntentLayer] = []

        for layer in frame.visibleLayers {
            var normalizedGeoms: [LottieSourceIntentGeometry] = []
            for geom in layer.geometry {
                let normGeom = normalize(geom, strategy: strategy, steps: &steps)
                normalizedGeoms.append(normGeom)
            }
            var nextLayer = layer
            nextLayer.geometry = normalizedGeoms
            normalizedLayers.append(nextLayer)
        }

        var nextFrame = frame
        nextFrame.visibleLayers = normalizedLayers
        return (nextFrame, steps)
    }

    /// Normalizes a full source intent trace.
    public func normalize(
        _ trace: LottieSourceIntentTrace,
        strategy: LottieSourceIntentRewriteStrategy
    ) -> (LottieSourceIntentTrace, [LottieSourceIntentRewriteStep]) {
        var steps: [LottieSourceIntentRewriteStep] = []
        let normalizedFrames = trace.frames.map { frame -> LottieSourceIntentFrame in
            var normalizedLayers: [LottieSourceIntentLayer] = []
            for layer in frame.visibleLayers {
                var normalizedGeoms: [LottieSourceIntentGeometry] = []
                for geom in layer.geometry {
                    let normGeom = normalize(geom, strategy: strategy, steps: &steps)
                    normalizedGeoms.append(normGeom)
                }
                var nextLayer = layer
                nextLayer.geometry = normalizedGeoms
                normalizedLayers.append(nextLayer)
            }
            var nextFrame = frame
            nextFrame.visibleLayers = normalizedLayers
            return nextFrame
        }
        var nextTrace = trace
        nextTrace.frames = normalizedFrames
        return (nextTrace, steps)
    }
}
