//
//  LottieTransformEvaluator.swift
//  PureLottie
//

import Foundation
import LottieModel

/// A row-vector 4x4 transform matrix in the same storage order as lottie-web's
/// `Matrix.props` and PureLayer's `Transform3D`.
public struct LottieTransformMatrix: Sendable, Equatable {
    public var values: [Double]

    public init(values: [Double]) {
        precondition(values.count == 16, "LottieTransformMatrix requires 16 values.")
        self.values = values
    }

    public static let identity = LottieTransformMatrix(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])

    public static func translation(x: Double, y: Double, z: Double) -> LottieTransformMatrix {
        LottieTransformMatrix(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            x, y, z, 1,
        ])
    }

    public static func scale(x: Double, y: Double, z: Double) -> LottieTransformMatrix {
        LottieTransformMatrix(values: [
            x, 0, 0, 0,
            0, y, 0, 0,
            0, 0, z, 0,
            0, 0, 0, 1,
        ])
    }

    public static func rotationZ(_ radians: Double) -> LottieTransformMatrix {
        let cosine = cos(radians)
        let sine = sin(radians)
        return LottieTransformMatrix(values: [
            cosine, -sine, 0, 0,
            sine, cosine, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    }

    public func concatenating(_ other: LottieTransformMatrix) -> LottieTransformMatrix {
        var result = [Double](repeating: 0, count: 16)
        for row in 0 ..< 4 {
            for column in 0 ..< 4 {
                var sum = 0.0
                for index in 0 ..< 4 {
                    sum += values[row * 4 + index] * other.values[index * 4 + column]
                }
                result[row * 4 + column] = sum
            }
        }
        return LottieTransformMatrix(values: result)
    }
}

/// Source-frame transform state before any PureLayer lowering.
public struct LottieTransformState: Sendable, Equatable {
    public var matrix: LottieTransformMatrix
    public var anchor: [Double]
    public var position: [Double]
    public var scale: [Double]
    public var rotationZDegrees: Double
    public var is3DLayer: Bool
}

/// Evaluates Lottie layer transforms in source-frame space.
public struct LottieTransformEvaluator: Sendable {
    public let animation: LottieAnimation
    public let frameEvaluator: LottieFrameEvaluator

    public init(animation: LottieAnimation) {
        self.animation = animation
        frameEvaluator = LottieFrameEvaluator(animation: animation)
    }

    public func localTransform(
        for layer: LottieLayer,
        at sourceFrame: Double,
        path: JSONPath = JSONPath()
    ) -> LottieEvaluationResult<LottieTransformState> {
        let transform = layer.transform
        var diagnostics: [ValidationError] = []

        let anchor = evaluate(transform?.anchor, at: sourceFrame, path: path.appending(.key("ks")).appending(.key("a")), defaultValue: [0, 0, 0], diagnostics: &diagnostics)
        let position = evaluate(transform?.position, at: sourceFrame, path: path.appending(.key("ks")).appending(.key("p")), defaultValue: [0, 0, 0], diagnostics: &diagnostics)
        let scale = evaluate(transform?.scale, at: sourceFrame, path: path.appending(.key("ks")).appending(.key("s")), defaultValue: [100, 100, 100], diagnostics: &diagnostics)
        let rotationZDegrees = evaluate(transform?.rotation, at: sourceFrame, path: path.appending(.key("ks")).appending(.key("r")), defaultValue: 0, diagnostics: &diagnostics)

        appendUnsupportedDiagnostics(for: layer, at: path, diagnostics: &diagnostics)

        var matrix = LottieTransformMatrix.identity
        matrix = matrix.concatenating(.translation(x: -anchor.component(0, default: 0), y: -anchor.component(1, default: 0), z: anchor.component(2, default: 0)))
        matrix = matrix.concatenating(.scale(
            x: scale.component(0, default: 100) / 100,
            y: scale.component(1, default: 100) / 100,
            z: scale.component(2, default: 100) / 100
        ))
        matrix = matrix.concatenating(.rotationZ(-rotationZDegrees * .pi / 180))
        matrix = matrix.concatenating(.translation(
            x: position.component(0, default: 0),
            y: position.component(1, default: 0),
            z: -position.component(2, default: 0)
        ))

        return LottieEvaluationResult(
            value: LottieTransformState(
                matrix: matrix,
                anchor: anchor,
                position: position,
                scale: scale,
                rotationZDegrees: rotationZDegrees,
                is3DLayer: layer.is3D
            ),
            diagnostics: diagnostics
        )
    }

    public func worldTransform(
        for layer: LottieLayer,
        in layers: [LottieLayer],
        at sourceFrame: Double,
        path: JSONPath = JSONPath()
    ) -> LottieEvaluationResult<LottieTransformState> {
        let local = localTransform(for: layer, at: sourceFrame, path: path)
        var state = local.value
        var diagnostics = local.diagnostics
        let byIndex = Dictionary(
            layers.enumerated().compactMap { offset, item in
                item.index.map { ($0, ParentLayerRecord(layer: item, arrayOffset: offset)) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var cursor = layer.parent
        var visited: Set<Int> = []
        var guardCounter = 0

        while let parentIndex = cursor, let parent = byIndex[parentIndex], guardCounter < 64 {
            guard !visited.contains(parentIndex) else {
                diagnostics.append(
                    diagnostic(
                        ruleID: "lottie.evaluation.transform.parent-cycle",
                        reason: "Layer parent transform chain must be acyclic before evaluation.",
                        path: path.appending(.key("parent")),
                        classification: .gap
                    )
                )
                return LottieEvaluationResult(value: state, diagnostics: diagnostics)
            }
            visited.insert(parentIndex)
            let parentPath = siblingLayerPath(from: path, arrayOffset: parent.arrayOffset)
            let parentResult = localTransform(for: parent.layer, at: sourceFrame, path: parentPath)
            state.matrix = state.matrix.concatenating(parentResult.value.matrix)
            diagnostics.append(contentsOf: parentResult.diagnostics)
            cursor = parent.layer.parent
            guardCounter += 1
        }

        if let parentIndex = cursor, byIndex[parentIndex] != nil {
            diagnostics.append(
                diagnostic(
                    ruleID: "lottie.evaluation.transform.parent-depth",
                    reason: "Layer parent transform chain exceeded the evaluator depth guard.",
                    path: path.appending(.key("parent")),
                    classification: .gap
                )
            )
        }

        return LottieEvaluationResult(value: state, diagnostics: diagnostics)
    }

    private func evaluate(
        _ property: AnimatedVector?,
        at sourceFrame: Double,
        path: JSONPath,
        defaultValue: [Double],
        diagnostics: inout [ValidationError]
    ) -> [Double] {
        guard let property else { return defaultValue }
        let result = frameEvaluator.evaluate(property, at: sourceFrame, path: path)
        diagnostics.append(contentsOf: result.diagnostics)
        return result.value
    }

    private func evaluate(
        _ position: LottiePosition?,
        at sourceFrame: Double,
        path: JSONPath,
        defaultValue: [Double],
        diagnostics: inout [ValidationError]
    ) -> [Double] {
        guard let position else { return defaultValue }
        let result = frameEvaluator.evaluate(position, at: sourceFrame, path: path)
        diagnostics.append(contentsOf: result.diagnostics)
        return result.value
    }

    private func evaluate(
        _ property: AnimatedDouble?,
        at sourceFrame: Double,
        path: JSONPath,
        defaultValue: Double,
        diagnostics: inout [ValidationError]
    ) -> Double {
        guard let property else { return defaultValue }
        let result = frameEvaluator.evaluate(property, at: sourceFrame, path: path)
        diagnostics.append(contentsOf: result.diagnostics)
        return result.value
    }

    private func appendUnsupportedDiagnostics(for layer: LottieLayer, at path: JSONPath, diagnostics: inout [ValidationError]) {
        guard let transform = layer.transform else {
            if layer.isAutoOriented {
                diagnostics.append(autoOrientDiagnostic(at: path))
            }
            return
        }

        if transform.skew?.hasEffect == true {
            diagnostics.append(
                diagnostic(
                    ruleID: "lottie.evaluation.transform.skew.unsupported",
                    reason: "Transform skew must be supported or rejected before exact frame evaluation.",
                    path: path.appending(.key("ks")).appending(.key("sk")),
                    classification: .gap
                )
            )
        } else if transform.skewAxis?.hasEffect == true {
            diagnostics.append(
                diagnostic(
                    ruleID: "lottie.evaluation.transform.skew.unsupported",
                    reason: "Transform skew axis must be supported or rejected before exact frame evaluation.",
                    path: path.appending(.key("ks")).appending(.key("sa")),
                    classification: .gap
                )
            )
        }

        if layer.is3D || transform.rotationX?.hasEffect == true || transform.rotationY?.hasEffect == true || transform.rotationZ?.hasEffect == true || transform.orientation?
            .hasEffect == true
        {
            diagnostics.append(
                diagnostic(
                    ruleID: "lottie.evaluation.transform.3d.unsupported",
                    reason: "3D transform/orientation must be lowered into PureLayer 2.5D semantics before exact frame evaluation.",
                    path: path.appending(.key("ks")),
                    classification: .gap
                )
            )
        }

        if layer.isAutoOriented {
            diagnostics.append(autoOrientDiagnostic(at: path))
        }
    }

    private func autoOrientDiagnostic(at path: JSONPath) -> ValidationError {
        diagnostic(
            ruleID: "lottie.evaluation.transform.auto-orient.unsupported",
            reason: "Auto-orient must derive rotation from the position tangent before exact frame evaluation.",
            path: path.appending(.key("ao")),
            classification: .gap
        )
    }

    private func diagnostic(
        ruleID: String,
        reason: String,
        path: JSONPath,
        classification: FeatureClassification
    ) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: reason,
            at: path,
            severity: .warning,
            phase: .semantic,
            classification: classification
        )
    }
}

private struct ParentLayerRecord {
    var layer: LottieLayer
    var arrayOffset: Int
}

private func siblingLayerPath(from path: JSONPath, arrayOffset: Int) -> JSONPath {
    var components = path.components
    if let last = components.last {
        switch last {
        case .index:
            components.removeLast()
        case .key:
            components = [.key("layers")]
        }
    } else {
        components = [.key("layers")]
    }
    return JSONPath(components).appending(.index(arrayOffset))
}

private extension AnimatedDouble {
    var hasEffect: Bool {
        isAnimated || abs(initialValue) > 0.0001
    }
}

private extension AnimatedVector {
    var hasEffect: Bool {
        isAnimated || initialValue.contains { abs($0) > 0.0001 }
    }
}

private extension [Double] {
    func component(_ index: Int, default defaultValue: Double) -> Double {
        if indices.contains(index) { return self[index] }
        return last ?? defaultValue
    }
}
