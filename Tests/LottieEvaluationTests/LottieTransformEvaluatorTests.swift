import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie transform evaluator")
struct LottieTransformEvaluatorTests {
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
            "lottie.evaluation.transform.auto-orient.unsupported",
        ])
        #expect(result.diagnostics.map(\.codingPath.description) == [
            "$.layers[0].ks.sk",
            "$.layers[0].ddd",
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
}
