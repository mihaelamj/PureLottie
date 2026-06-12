//
//  LottieTransformEvaluator.swift
//  PureLottie
//

import Foundation
import LottieModel

/// A row-vector 4x4 transform matrix in the same storage order as lottie-web's
/// `Matrix.props` and PureLayer's `Transform3D`.
public struct LottieTransformMatrix: Codable, Sendable, Equatable {
    public var values: [Double]

    public init(values: [Double]) {
        precondition(values.count == 16, "LottieTransformMatrix requires 16 values.")
        self.values = values
    }

    private enum CodingKeys: String, CodingKey {
        case values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values = try container.decode([Double].self, forKey: .values)
        guard values.count == 16 else {
            throw DecodingError.dataCorruptedError(
                forKey: .values,
                in: container,
                debugDescription: "LottieTransformMatrix requires 16 values."
            )
        }
        self.values = values
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(values, forKey: .values)
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

    /// Applies the matrix to a Lottie source-space point using lottie-web's
    /// `Matrix.applyToPoint` formula.
    public func applying(to point: [Double]) -> [Double] {
        let x = point.component(0, default: 0)
        let y = point.component(1, default: 0)
        let z = point.component(2, default: 0)
        return [
            x * values[0] + y * values[4] + z * values[8] + values[12],
            x * values[1] + y * values[5] + z * values[9] + values[13],
            x * values[2] + y * values[6] + z * values[10] + values[14],
        ]
    }
}

/// Distinguishes a transform evaluated in its own layer/group space from a
/// transform composed through the layer parent chain.
public enum LottieTransformTraceScope: String, Codable, Sendable, Equatable {
    case local
    case world
}

/// Named transform components in Lottie order before matrix lowering.
public enum LottieTransformComponentName: String, Codable, Sendable, Equatable {
    case anchor
    case position
    case scale
    case rotationZ
}

/// Evaluation evidence for one authored transform property.
///
/// `rawValue` is the authored initial value when the property exists,
/// `evaluatedValue` is the sampled value at `sourceFrame`, and `matrixValue` is
/// the normalized value that feeds the matrix operation.
public struct LottieTransformComponentTrace: Codable, Sendable, Equatable {
    public var name: LottieTransformComponentName
    public var propertyPath: String
    public var rawValue: [Double]?
    public var evaluatedValue: [Double]
    public var matrixValue: [Double]
    public var defaultValue: [Double]
    public var usedDefault: Bool
    public var propertyTrace: LottiePropertyEvaluationTrace?

    public init(
        name: LottieTransformComponentName,
        propertyPath: String,
        rawValue: [Double]?,
        evaluatedValue: [Double],
        matrixValue: [Double],
        defaultValue: [Double],
        usedDefault: Bool,
        propertyTrace: LottiePropertyEvaluationTrace?
    ) {
        self.name = name
        self.propertyPath = propertyPath
        self.rawValue = rawValue
        self.evaluatedValue = evaluatedValue
        self.matrixValue = matrixValue
        self.defaultValue = defaultValue
        self.usedDefault = usedDefault
        self.propertyTrace = propertyTrace
    }
}

/// Matrix operations emitted from Lottie transform components in lottie-web
/// order.
public enum LottieTransformOperationKind: String, Codable, Sendable, Equatable {
    case translateAnchor
    case scale
    case rotateZ
    case translatePosition
}

/// One matrix operation plus the accumulated matrix immediately after applying
/// it.
public struct LottieTransformOperationTrace: Codable, Sendable, Equatable {
    public var kind: LottieTransformOperationKind
    public var values: [Double]
    public var operationMatrix: LottieTransformMatrix
    public var resultingMatrix: LottieTransformMatrix

    public init(
        kind: LottieTransformOperationKind,
        values: [Double],
        operationMatrix: LottieTransformMatrix,
        resultingMatrix: LottieTransformMatrix
    ) {
        self.kind = kind
        self.values = values
        self.operationMatrix = operationMatrix
        self.resultingMatrix = resultingMatrix
    }
}

/// Parent-layer matrix evidence appended while computing a world transform.
public struct LottieParentTransformTrace: Codable, Sendable, Equatable {
    public var layerIndex: Int?
    public var layerPath: String
    public var matrixConvention: LottieSourceIntentMatrixConvention
    public var components: [LottieTransformComponentTrace]
    public var matrix: LottieTransformMatrix
    public var operations: [LottieTransformOperationTrace]

    public init(
        layerIndex: Int?,
        layerPath: String,
        matrixConvention: LottieSourceIntentMatrixConvention = .lottieWebRowVector4x4,
        components: [LottieTransformComponentTrace],
        matrix: LottieTransformMatrix,
        operations: [LottieTransformOperationTrace]
    ) {
        self.layerIndex = layerIndex
        self.layerPath = layerPath
        self.matrixConvention = matrixConvention
        self.components = components
        self.matrix = matrix
        self.operations = operations
    }
}

/// Complete transform evaluation evidence for a source frame.
///
/// The trace is intentionally backend-neutral: it records the authored values,
/// normalization, operation order, matrix convention, parent chain, and final
/// matrix before any PureLayer lowering happens.
public struct LottieTransformTrace: Codable, Sendable, Equatable {
    public var scope: LottieTransformTraceScope
    public var transformPath: String
    public var sourceFrame: Double
    public var matrixConvention: LottieSourceIntentMatrixConvention
    public var components: [LottieTransformComponentTrace]
    public var operations: [LottieTransformOperationTrace]
    public var parentChain: [LottieParentTransformTrace]
    public var resultingMatrix: LottieTransformMatrix

    public init(
        scope: LottieTransformTraceScope,
        transformPath: String,
        sourceFrame: Double,
        matrixConvention: LottieSourceIntentMatrixConvention = .lottieWebRowVector4x4,
        components: [LottieTransformComponentTrace],
        operations: [LottieTransformOperationTrace],
        parentChain: [LottieParentTransformTrace] = [],
        resultingMatrix: LottieTransformMatrix
    ) {
        self.scope = scope
        self.transformPath = transformPath
        self.sourceFrame = sourceFrame
        self.matrixConvention = matrixConvention
        self.components = components
        self.operations = operations
        self.parentChain = parentChain
        self.resultingMatrix = resultingMatrix
    }
}

/// Source-frame transform state before any PureLayer lowering.
public struct LottieTransformState: Codable, Sendable, Equatable {
    public var matrix: LottieTransformMatrix
    public var anchor: [Double]
    public var position: [Double]
    public var scale: [Double]
    public var rotationZDegrees: Double
    public var is3DLayer: Bool
    public var trace: LottieTransformTrace
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

        let anchor = vectorComponent(
            .anchor,
            transform?.anchor,
            at: sourceFrame,
            path: path.appending(.key("ks")).appending(.key("a")),
            defaultValue: [0, 0, 0],
            matrixValue: normalizedAnchor,
            diagnostics: &diagnostics
        )
        let position = positionComponent(
            transform?.position,
            at: sourceFrame,
            path: path.appending(.key("ks")).appending(.key("p")),
            defaultValue: [0, 0, 0],
            diagnostics: &diagnostics
        )
        let scale = vectorComponent(
            .scale,
            transform?.scale,
            at: sourceFrame,
            path: path.appending(.key("ks")).appending(.key("s")),
            defaultValue: [100, 100, 100],
            matrixValue: normalizedScale,
            diagnostics: &diagnostics
        )
        let rotationZ = scalarComponent(
            .rotationZ,
            transform?.rotation,
            at: sourceFrame,
            path: path.appending(.key("ks")).appending(.key("r")),
            defaultValue: 0,
            matrixValue: normalizedRotationZ,
            diagnostics: &diagnostics
        )

        appendUnsupportedDiagnostics(for: layer, at: path, diagnostics: &diagnostics)

        return LottieEvaluationResult(
            value: transformState(
                sourceFrame: sourceFrame,
                path: path.appending(.key("ks")),
                anchor: anchor,
                position: position,
                scale: scale,
                rotationZ: rotationZ,
                is3DLayer: layer.is3D,
                scope: .local
            ),
            diagnostics: diagnostics
        )
    }

    public func groupTransform(
        for transform: ShapeTransform?,
        at sourceFrame: Double,
        path: JSONPath = JSONPath()
    ) -> LottieEvaluationResult<LottieTransformState> {
        var diagnostics: [ValidationError] = []
        let anchor = vectorComponent(
            .anchor,
            transform?.anchor,
            at: sourceFrame,
            path: path.appending(.key("a")),
            defaultValue: [0, 0, 0],
            matrixValue: normalizedAnchor,
            diagnostics: &diagnostics
        )
        let position = vectorComponent(
            .position,
            transform?.position,
            at: sourceFrame,
            path: path.appending(.key("p")),
            defaultValue: [0, 0, 0],
            matrixValue: normalizedPosition,
            diagnostics: &diagnostics
        )
        let scale = vectorComponent(
            .scale,
            transform?.scale,
            at: sourceFrame,
            path: path.appending(.key("s")),
            defaultValue: [100, 100, 100],
            matrixValue: normalizedScale,
            diagnostics: &diagnostics
        )
        let rotationZ = scalarComponent(
            .rotationZ,
            transform?.rotation,
            at: sourceFrame,
            path: path.appending(.key("r")),
            defaultValue: 0,
            matrixValue: normalizedRotationZ,
            diagnostics: &diagnostics
        )

        return LottieEvaluationResult(
            value: transformState(
                sourceFrame: sourceFrame,
                path: path,
                anchor: anchor,
                position: position,
                scale: scale,
                rotationZ: rotationZ,
                is3DLayer: false,
                scope: .local
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
        state.trace.scope = .world
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
            state.trace.parentChain.append(LottieParentTransformTrace(
                layerIndex: parent.layer.index,
                layerPath: parentPath.description,
                matrixConvention: parentResult.value.trace.matrixConvention,
                components: parentResult.value.trace.components,
                matrix: parentResult.value.matrix,
                operations: parentResult.value.trace.operations
            ))
            state.trace.resultingMatrix = state.matrix
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

    private func transformState(
        sourceFrame: Double,
        path: JSONPath,
        anchor: TransformComponentEvaluation,
        position: TransformComponentEvaluation,
        scale: TransformComponentEvaluation,
        rotationZ: TransformComponentEvaluation,
        is3DLayer: Bool,
        scope: LottieTransformTraceScope
    ) -> LottieTransformState {
        var operations: [LottieTransformOperationTrace] = []
        var matrix = LottieTransformMatrix.identity

        appendOperation(.translateAnchor, values: anchor.trace.matrixValue, to: &matrix, operations: &operations)
        appendOperation(.scale, values: scale.trace.matrixValue, to: &matrix, operations: &operations)
        appendOperation(.rotateZ, values: rotationZ.trace.matrixValue, to: &matrix, operations: &operations)
        appendOperation(.translatePosition, values: position.trace.matrixValue, to: &matrix, operations: &operations)

        let trace = LottieTransformTrace(
            scope: scope,
            transformPath: path.description,
            sourceFrame: sourceFrame,
            components: [anchor.trace, position.trace, scale.trace, rotationZ.trace],
            operations: operations,
            resultingMatrix: matrix
        )
        return LottieTransformState(
            matrix: matrix,
            anchor: anchor.value,
            position: position.value,
            scale: scale.value,
            rotationZDegrees: rotationZ.value.component(0, default: 0),
            is3DLayer: is3DLayer,
            trace: trace
        )
    }

    private func appendOperation(
        _ kind: LottieTransformOperationKind,
        values: [Double],
        to matrix: inout LottieTransformMatrix,
        operations: inout [LottieTransformOperationTrace]
    ) {
        let operationMatrix: LottieTransformMatrix = switch kind {
        case .translateAnchor, .translatePosition:
            .translation(
                x: values.component(0, default: 0),
                y: values.component(1, default: 0),
                z: values.component(2, default: 0)
            )
        case .scale:
            .scale(
                x: values.component(0, default: 1),
                y: values.component(1, default: 1),
                z: values.component(2, default: 1)
            )
        case .rotateZ:
            .rotationZ(values.component(0, default: 0))
        }
        matrix = matrix.concatenating(operationMatrix)
        operations.append(LottieTransformOperationTrace(
            kind: kind,
            values: values,
            operationMatrix: operationMatrix,
            resultingMatrix: matrix
        ))
    }

    private func vectorComponent(
        _ name: LottieTransformComponentName,
        _ property: AnimatedVector?,
        at sourceFrame: Double,
        path: JSONPath,
        defaultValue: [Double],
        matrixValue: ([Double]) -> [Double],
        diagnostics: inout [ValidationError]
    ) -> TransformComponentEvaluation {
        guard let property else {
            return TransformComponentEvaluation(
                value: defaultValue,
                trace: componentTrace(name, path: path, rawValue: nil, value: defaultValue, matrixValue: matrixValue(defaultValue), defaultValue: defaultValue, propertyTrace: nil)
            )
        }
        let result = frameEvaluator.evaluate(property, at: sourceFrame, path: path)
        diagnostics.append(contentsOf: result.diagnostics)
        return TransformComponentEvaluation(
            value: result.value,
            trace: componentTrace(
                name,
                path: path,
                rawValue: property.initialValue,
                value: result.value,
                matrixValue: matrixValue(result.value),
                defaultValue: defaultValue,
                propertyTrace: result.trace
            )
        )
    }

    private func positionComponent(
        _ position: LottiePosition?,
        at sourceFrame: Double,
        path: JSONPath,
        defaultValue: [Double],
        diagnostics: inout [ValidationError]
    ) -> TransformComponentEvaluation {
        guard let position else {
            return TransformComponentEvaluation(
                value: defaultValue,
                trace: componentTrace(
                    .position,
                    path: path,
                    rawValue: nil,
                    value: defaultValue,
                    matrixValue: normalizedPosition(defaultValue),
                    defaultValue: defaultValue,
                    propertyTrace: nil
                )
            )
        }
        let result = frameEvaluator.evaluate(position, at: sourceFrame, path: path)
        diagnostics.append(contentsOf: result.diagnostics)
        return TransformComponentEvaluation(
            value: result.value,
            trace: componentTrace(
                .position,
                path: path,
                rawValue: position.initialValue,
                value: result.value,
                matrixValue: normalizedPosition(result.value),
                defaultValue: defaultValue,
                propertyTrace: result.trace
            )
        )
    }

    private func scalarComponent(
        _ name: LottieTransformComponentName,
        _ property: AnimatedDouble?,
        at sourceFrame: Double,
        path: JSONPath,
        defaultValue: Double,
        matrixValue: ([Double]) -> [Double],
        diagnostics: inout [ValidationError]
    ) -> TransformComponentEvaluation {
        let defaultVector = [defaultValue]
        guard let property else {
            return TransformComponentEvaluation(
                value: defaultVector,
                trace: componentTrace(
                    name,
                    path: path,
                    rawValue: nil,
                    value: defaultVector,
                    matrixValue: matrixValue(defaultVector),
                    defaultValue: defaultVector,
                    propertyTrace: nil
                )
            )
        }
        let result = frameEvaluator.evaluate(property, at: sourceFrame, path: path)
        diagnostics.append(contentsOf: result.diagnostics)
        let value = [result.value]
        return TransformComponentEvaluation(
            value: value,
            trace: componentTrace(
                name,
                path: path,
                rawValue: [property.initialValue],
                value: value,
                matrixValue: matrixValue(value),
                defaultValue: defaultVector,
                propertyTrace: result.trace
            )
        )
    }

    private func componentTrace(
        _ name: LottieTransformComponentName,
        path: JSONPath,
        rawValue: [Double]?,
        value: [Double],
        matrixValue: [Double],
        defaultValue: [Double],
        propertyTrace: LottiePropertyEvaluationTrace?
    ) -> LottieTransformComponentTrace {
        LottieTransformComponentTrace(
            name: name,
            propertyPath: path.description,
            rawValue: rawValue,
            evaluatedValue: value,
            matrixValue: matrixValue,
            defaultValue: defaultValue,
            usedDefault: rawValue == nil,
            propertyTrace: propertyTrace
        )
    }

    private func normalizedAnchor(_ value: [Double]) -> [Double] {
        [
            -value.component(0, default: 0),
            -value.component(1, default: 0),
            value.component(2, default: 0),
        ]
    }

    private func normalizedPosition(_ value: [Double]) -> [Double] {
        [
            value.component(0, default: 0),
            value.component(1, default: 0),
            -value.component(2, default: 0),
        ]
    }

    private func normalizedScale(_ value: [Double]) -> [Double] {
        [
            value.component(0, default: 100) / 100,
            value.component(1, default: 100) / 100,
            value.component(2, default: 100) / 100,
        ]
    }

    private func normalizedRotationZ(_ value: [Double]) -> [Double] {
        [-value.component(0, default: 0) * .pi / 180]
    }

    private func appendUnsupportedDiagnostics(for layer: LottieLayer, at path: JSONPath, diagnostics: inout [ValidationError]) {
        guard let transform = layer.transform else {
            for path in unsupported3DPaths(for: layer, transform: nil, at: path) {
                diagnostics.append(unsupported3DDiagnostic(at: path))
            }
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

        for path in unsupported3DPaths(for: layer, transform: transform, at: path) {
            diagnostics.append(unsupported3DDiagnostic(at: path))
        }

        if layer.isAutoOriented {
            diagnostics.append(autoOrientDiagnostic(at: path))
        }
    }

    private func unsupported3DPaths(for layer: LottieLayer, transform: LottieTransform?, at path: JSONPath) -> [JSONPath] {
        var paths: [JSONPath] = []
        if layer.is3D {
            paths.append(path.appending(.key("ddd")))
        }
        guard let transform else { return paths }
        if transform.rotationX?.hasEffect == true {
            paths.append(path.appending(.key("ks")).appending(.key("rx")))
        }
        if transform.rotationY?.hasEffect == true {
            paths.append(path.appending(.key("ks")).appending(.key("ry")))
        }
        if transform.rotationZ?.hasEffect == true {
            paths.append(path.appending(.key("ks")).appending(.key("rz")))
        }
        if transform.orientation?.hasEffect == true {
            paths.append(path.appending(.key("ks")).appending(.key("or")))
        }
        return paths
    }

    private func unsupported3DDiagnostic(at path: JSONPath) -> ValidationError {
        diagnostic(
            ruleID: "lottie.evaluation.transform.3d.unsupported",
            reason: "3D transform/orientation must be lowered into PureLayer 2.5D semantics before exact frame evaluation.",
            path: path,
            classification: .gap
        )
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

private struct TransformComponentEvaluation {
    var value: [Double]
    var trace: LottieTransformComponentTrace
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
        return defaultValue
    }
}
