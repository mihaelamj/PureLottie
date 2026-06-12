import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie transform evaluator")
struct LottieTransformEvaluatorTests {
    @Test("transform matrices encode round trip and reject malformed payloads")
    func transformMatrixCodablePreservesInvariant() throws {
        let matrix = LottieTransformMatrix.translation(x: 1, y: 2, z: 3)
        let encoded = try JSONEncoder().encode(matrix)
        let decoded = try JSONDecoder().decode(LottieTransformMatrix.self, from: encoded)

        #expect(decoded == matrix)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LottieTransformMatrix.self, from: Data(#"{"values":[1,2,3]}"#.utf8))
        }
    }

    @Test("local matrix follows lottie-web anchor scale rotation position order")
    func localMatrixOrderMatchesLottieWeb() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "a": { "a": 0, "k": [10, 20, 0] },
              "p": { "a": 0, "k": [100, 50, 0] },
              "s": { "a": 0, "k": [200, 50, 100] },
              "r": { "a": 0, "k": 90 }
            },
            "shapes": []
          }]
        }
        """)

        let layer = try #require(animation.layers.first)
        let result = LottieTransformEvaluator(animation: animation).localTransform(
            for: layer,
            at: 0,
            path: JSONPath([.key("layers"), .index(0)])
        )

        #expect(result.diagnostics.isEmpty)
        expectMatrix(
            result.value.matrix.values,
            equals: [
                0, 2, 0, 0,
                -0.5, 0, 0, 0,
                0, 0, 1, 0,
                110, 30, 0, 1,
            ]
        )
        #expect(result.value.trace.scope == .local)
        #expect(result.value.trace.transformPath == "$.layers[0].ks")
        #expect(result.value.trace.sourceFrame == 0)
        #expect(result.value.trace.matrixConvention == .lottieWebRowVector4x4)
        #expect(result.value.trace.resultingMatrix == result.value.matrix)
        #expect(result.value.trace.components.map(\.name) == [.anchor, .position, .scale, .rotationZ])
        #expect(result.value.trace.operations.map(\.kind) == [.translateAnchor, .scale, .rotateZ, .translatePosition])
        #expect(try component(.anchor, in: result.value.trace).propertyPath == "$.layers[0].ks.a")
        #expect(try component(.anchor, in: result.value.trace).rawValue == [10, 20, 0])
        #expect(try component(.anchor, in: result.value.trace).matrixValue == [-10, -20, 0])
        #expect(try component(.position, in: result.value.trace).propertyPath == "$.layers[0].ks.p")
        #expect(try component(.position, in: result.value.trace).matrixValue == [100, 50, 0])
        #expect(try component(.scale, in: result.value.trace).matrixValue == [2, 0.5, 1])
        try expectVector(component(.rotationZ, in: result.value.trace).matrixValue, equals: [-.pi / 2])
        expectVector(result.value.matrix.applying(to: [10, 20, 0]), equals: [100, 50, 0])
    }

    @Test("2D anchor and position vectors default z to zero")
    func twoDimensionalVectorsDoNotInventZFromY() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "a": { "a": 0, "k": [10, 20] },
              "p": { "a": 0, "k": [100, 50] }
            },
            "shapes": []
          }]
        }
        """)

        let result = try LottieTransformEvaluator(animation: animation).localTransform(
            for: #require(animation.layers.first),
            at: 0,
            path: JSONPath([.key("layers"), .index(0)])
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.value.anchor == [10, 20])
        #expect(result.value.position == [100, 50])
        #expect(result.value.matrix.values[14] == 0)
        #expect(try component(.anchor, in: result.value.trace).matrixValue == [-10, -20, 0])
        #expect(try component(.position, in: result.value.trace).matrixValue == [100, 50, 0])
        expectVector(result.value.matrix.applying(to: [10, 20]), equals: [100, 50, 0])
    }

    @Test("animated transform component trace preserves authored initial and sampled values")
    func componentTraceSeparatesAuthoredInitialAndEvaluatedValues() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "p": {
                "a": 1,
                "k": [
                  { "t": 0, "s": [0, 0, 0], "e": [100, 0, 0], "i": { "x": 0.833, "y": 0.833 }, "o": { "x": 0.167, "y": 0.167 } },
                  { "t": 10, "s": [100, 0, 0] }
                ]
              }
            },
            "shapes": []
          }]
        }
        """)

        let result = try LottieTransformEvaluator(animation: animation).localTransform(
            for: #require(animation.layers.first),
            at: 5,
            path: JSONPath([.key("layers"), .index(0)])
        )

        #expect(result.diagnostics.isEmpty)
        let position = try component(.position, in: result.value.trace)
        #expect(position.rawValue == [0, 0, 0])
        expectVector(position.evaluatedValue, equals: [50, 0, 0])
        expectVector(position.matrixValue, equals: [50, 0, 0])
        #expect(position.propertyTrace?.mode == .keyframeSpan)
    }

    @Test("hidden parent layers still participate in transform world matrix")
    func hiddenParentParticipatesInWorldMatrix() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [
            {
              "ty": 3,
              "ind": 1,
              "nm": "hidden parent",
              "hd": true,
              "ip": 0,
              "op": 20,
              "ks": { "s": { "a": 0, "k": [200, 200, 100] } }
            },
            {
              "ty": 4,
              "ind": 2,
              "parent": 1,
              "ip": 0,
              "op": 20,
              "ks": { "p": { "a": 0, "k": [5, 0, 0] } },
              "shapes": []
            }
          ]
        }
        """)

        let child = animation.layers[1]
        let result = LottieTransformEvaluator(animation: animation).worldTransform(
            for: child,
            in: animation.layers,
            at: 0,
            path: JSONPath([.key("layers"), .index(1)])
        )

        #expect(result.diagnostics.isEmpty)
        #expect(abs(result.value.matrix.values[12] - 10) < 0.000001)
    }

    @Test("parent world matrix records chain and applies points in lottie-web order")
    func parentWorldMatrixAppliesPointsInLottieWebOrder() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [
            {
              "ty": 3,
              "ind": 1,
              "ip": 0,
              "op": 20,
              "ks": {
                "p": { "a": 0, "k": [100, 50, 0] },
                "r": { "a": 0, "k": 90 }
              }
            },
            {
              "ty": 4,
              "ind": 2,
              "parent": 1,
              "ip": 0,
              "op": 20,
              "ks": { "p": { "a": 0, "k": [10, 0, 0] } },
              "shapes": []
            }
          ]
        }
        """)

        let result = LottieTransformEvaluator(animation: animation).worldTransform(
            for: animation.layers[1],
            in: animation.layers,
            at: 0,
            path: JSONPath([.key("layers"), .index(1)])
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.value.trace.scope == .world)
        #expect(result.value.trace.parentChain.count == 1)
        let parent = try #require(result.value.trace.parentChain.first)
        #expect(parent.layerIndex == 1)
        #expect(parent.layerPath == "$.layers[0]")
        #expect(parent.matrixConvention == .lottieWebRowVector4x4)
        #expect(try component(.position, in: parent.components).rawValue == [100, 50, 0])
        try expectVector(component(.rotationZ, in: parent.components).matrixValue, equals: [-.pi / 2])
        #expect(result.value.trace.resultingMatrix == result.value.matrix)
        expectVector(result.value.matrix.applying(to: [0, 0, 0]), equals: [100, 60, 0])
        expectVector(
            result.value.matrix.applying(to: [3, 4, 0]),
            equals: applyLottieWebPointFormula(point: [3, 4, 0], matrix: result.value.matrix)
        )
    }

    @Test("group transforms use shape transform paths and lottie-web operation order")
    func groupTransformUsesShapeTransformPaths() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {},
            "shapes": [{
              "ty": "gr",
              "nm": "Group",
              "it": [
                { "ty": "rc", "p": { "a": 0, "k": [5, 0] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
                { "ty": "tr", "a": { "a": 0, "k": [5, 0] }, "p": { "a": 0, "k": [20, 10] }, "s": { "a": 0, "k": [100, 100] }, "r": { "a": 0, "k": 0 }, "o": { "a": 0, "k": 100 } }
              ]
            }]
          }]
        }
        """)

        let group = try shapeGroup(in: animation)
        let transform = try groupTransform(in: group)
        let result = LottieTransformEvaluator(animation: animation).groupTransform(
            for: transform,
            at: 0,
            path: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0), .key("it"), .index(1)])
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.value.trace.transformPath == "$.layers[0].shapes[0].it[1]")
        #expect(result.value.trace.operations.map(\.kind) == [.translateAnchor, .scale, .rotateZ, .translatePosition])
        #expect(try component(.anchor, in: result.value.trace).propertyPath == "$.layers[0].shapes[0].it[1].a")
        #expect(try component(.position, in: result.value.trace).propertyPath == "$.layers[0].shapes[0].it[1].p")
        expectVector(result.value.matrix.applying(to: [5, 0, 0]), equals: [20, 10, 0])
    }

    @Test("split position z is preserved in source-frame transform state")
    func splitPositionZIsEvaluated() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "p": {
                "s": true,
                "x": { "a": 0, "k": 10 },
                "y": { "a": 0, "k": 20 },
                "z": { "a": 0, "k": 30 }
              }
            },
            "shapes": []
          }]
        }
        """)

        let result = try LottieTransformEvaluator(animation: animation).localTransform(
            for: #require(animation.layers.first),
            at: 0
        )

        #expect(result.value.position == [10, 20, 30])
        #expect(result.value.matrix.values[14] == -30)
    }

    @Test("unsupported transform features produce structured diagnostics")
    func unsupportedTransformDiagnostics() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ddd": 1,
            "ao": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "sk": { "a": 0, "k": 20 },
              "sa": { "a": 0, "k": 30 },
              "rx": { "a": 0, "k": 10 },
              "ry": { "a": 0, "k": 0 },
              "rz": { "a": 0, "k": 0 },
              "or": { "a": 0, "k": [0, 0, 0] }
            },
            "shapes": []
          }]
        }
        """)

        let result = try LottieTransformEvaluator(animation: animation).localTransform(
            for: #require(animation.layers.first),
            at: 0,
            path: JSONPath([.key("layers"), .index(0)])
        )

        #expect(result.diagnostics.map(\.ruleID) == [
            "lottie.evaluation.transform.skew.unsupported",
            "lottie.evaluation.transform.3d.unsupported",
            "lottie.evaluation.transform.3d.unsupported",
            "lottie.evaluation.transform.auto-orient.unsupported",
        ])
        #expect(result.diagnostics.map(\.codingPath.description) == [
            "$.layers[0].ks.sk",
            "$.layers[0].ddd",
            "$.layers[0].ks.rx",
            "$.layers[0].ao",
        ])
    }

    @Test("3D layer flag reports even when ks is absent")
    func threeDLayerFlagReportsWithoutTransform() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 3,
            "ind": 1,
            "ddd": 1,
            "ip": 0,
            "op": 20
          }]
        }
        """)

        let result = try LottieTransformEvaluator(animation: animation).localTransform(
            for: #require(animation.layers.first),
            at: 0,
            path: JSONPath([.key("layers"), .index(0)])
        )

        #expect(result.diagnostics.map(\.ruleID) == [
            "lottie.evaluation.transform.3d.unsupported",
        ])
        #expect(result.diagnostics.map(\.codingPath.description) == [
            "$.layers[0].ddd",
        ])
    }

    @Test("3D transform fields report their exact key path")
    func threeDTransformFieldsUseExactPath() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "rx": { "a": 0, "k": 15 }
            },
            "shapes": []
          }]
        }
        """)

        let result = try LottieTransformEvaluator(animation: animation).localTransform(
            for: #require(animation.layers.first),
            at: 0,
            path: JSONPath([.key("layers"), .index(0)])
        )

        #expect(result.diagnostics.map(\.codingPath.description) == [
            "$.layers[0].ks.rx",
        ])
    }

    @Test("parent diagnostics use sibling array path instead of parent id")
    func parentDiagnosticsUseSiblingArrayPath() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [
            {
              "ty": 3,
              "ind": 42,
              "ip": 0,
              "op": 20,
              "ks": { "sk": { "a": 0, "k": 15 } }
            },
            {
              "ty": 4,
              "ind": 7,
              "parent": 42,
              "ip": 0,
              "op": 20,
              "ks": { "p": { "a": 0, "k": [5, 0, 0] } },
              "shapes": []
            }
          ]
        }
        """)

        let result = LottieTransformEvaluator(animation: animation).worldTransform(
            for: animation.layers[1],
            in: animation.layers,
            at: 0,
            path: JSONPath([.key("layers"), .index(1)])
        )

        #expect(result.diagnostics.map(\.codingPath.description) == [
            "$.layers[0].ks.sk",
        ])
    }

    @Test("parent depth guard reports instead of silently truncating")
    func parentDepthGuardReports() throws {
        let layers = (1 ... 67).map { index in
            let parent = index < 67 ? #""parent": \#(index + 1),"# : ""
            let shapeFields = index == 1 ? #""shapes": [],"# : ""
            return """
            {
              "ty": \(index == 1 ? 4 : 3),
              "ind": \(index),
              \(parent)
              "ip": 0,
              "op": 20,
              "ks": { "p": { "a": 0, "k": [0, 0, 0] } },
              \(shapeFields)
              "st": 0
            }
            """
        }.joined(separator: ",")
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [\(layers)]
        }
        """)

        let result = LottieTransformEvaluator(animation: animation).worldTransform(
            for: animation.layers[0],
            in: animation.layers,
            at: 0,
            path: JSONPath([.key("layers"), .index(0)])
        )

        #expect(result.diagnostics.map(\.ruleID).contains("lottie.evaluation.transform.parent-depth"))
        #expect(result.diagnostics.last?.codingPath.description == "$.layers[0].parent")
    }

    @Test("skew axis diagnostics point at sa when skew amount is absent")
    func skewAxisOnlyDiagnosticsUseSkewAxisPath() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "sa": { "a": 0, "k": 30 }
            },
            "shapes": []
          }]
        }
        """)

        let result = try LottieTransformEvaluator(animation: animation).localTransform(
            for: #require(animation.layers.first),
            at: 0,
            path: JSONPath([.key("layers"), .index(0)])
        )

        #expect(result.diagnostics.map(\.codingPath.description) == [
            "$.layers[0].ks.sa",
        ])
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }

    private func expectMatrix(_ actual: [Double], equals expected: [Double]) {
        #expect(actual.count == expected.count)
        for index in actual.indices {
            #expect(abs(actual[index] - expected[index]) < 0.000001)
        }
    }

    private func expectVector(_ actual: [Double], equals expected: [Double]) {
        expectMatrix(actual, equals: expected)
    }

    private func component(
        _ name: LottieTransformComponentName,
        in trace: LottieTransformTrace
    ) throws -> LottieTransformComponentTrace {
        try component(name, in: trace.components)
    }

    private func component(
        _ name: LottieTransformComponentName,
        in components: [LottieTransformComponentTrace]
    ) throws -> LottieTransformComponentTrace {
        try #require(components.first { $0.name == name })
    }

    private func shapeGroup(in animation: LottieAnimation) throws -> ShapeGroup {
        let layer = try #require(animation.layers.first)
        let shape = try #require(layer.shapes?.first)
        guard case let .group(group) = shape else {
            Issue.record("Expected first shape to decode as a group.")
            throw TestSupportError.unexpectedShape
        }
        return group
    }

    private func groupTransform(in group: ShapeGroup) throws -> ShapeTransform {
        for item in group.items.reversed() {
            if case let .transform(transform) = item {
                return transform
            }
        }
        Issue.record("Expected group to contain a shape transform.")
        throw TestSupportError.unexpectedShape
    }

    private func applyLottieWebPointFormula(point: [Double], matrix: LottieTransformMatrix) -> [Double] {
        let x = pointValue(point, at: 0)
        let y = pointValue(point, at: 1)
        let z = pointValue(point, at: 2)
        let values = matrix.values
        return [
            x * values[0] + y * values[4] + z * values[8] + values[12],
            x * values[1] + y * values[5] + z * values[9] + values[13],
            x * values[2] + y * values[6] + z * values[10] + values[14],
        ]
    }

    private func pointValue(_ point: [Double], at index: Int) -> Double {
        point.indices.contains(index) ? point[index] : 0
    }

    private enum TestSupportError: Error {
        case unexpectedShape
    }
}
