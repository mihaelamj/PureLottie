import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie frame evaluator")
struct LottieFrameEvaluatorTests {
    @Test("composition and layer windows use inclusive ip and exclusive op")
    func frameWindowBoundaries() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 10,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{ "ty": 4, "ind": 1, "ip": 12, "op": 15, "ks": {}, "shapes": [] }]
        }
        """)
        let evaluator = LottieFrameEvaluator(animation: animation)
        let layer = try #require(animation.layers.first)

        #expect(!evaluator.containsCompositionFrame(9))
        #expect(evaluator.containsCompositionFrame(10))
        #expect(evaluator.containsCompositionFrame(19))
        #expect(!evaluator.containsCompositionFrame(20))
        #expect(!evaluator.isLayerVisible(layer, at: 11))
        #expect(evaluator.isLayerVisible(layer, at: 12))
        #expect(evaluator.isLayerVisible(layer, at: 14))
        #expect(!evaluator.isLayerVisible(layer, at: 15))
    }

    @Test("hold keyframes hold until the next key time")
    func holdKeyframes() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "o": { "k": [
                { "t": 0, "s": [0], "e": [100], "h": 1 },
                { "t": 10, "s": [100] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let opacity = try #require(animation.layers.first?.transform?.opacity)
        let evaluator = LottieFrameEvaluator(animation: animation)

        #expect(evaluator.evaluate(opacity, at: 5).value == 0)
        #expect(evaluator.evaluate(opacity, at: 10).value == 100)
    }

    @Test("scalar easing matches lottie-web BezierEaser for a selected fixture curve")
    func scalarEasingMatchesLottieWebBezierEaser() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "o": { "k": [
                { "t": 0, "s": [0], "e": [100], "o": { "x": 0.333, "y": 0 }, "i": { "x": 0.667, "y": 1 } },
                { "t": 10, "s": [100] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let opacity = try #require(animation.layers.first?.transform?.opacity)
        let result = LottieFrameEvaluator(animation: animation).evaluate(opacity, at: 2.5)

        #expect(result.diagnostics.isEmpty)
        #expect(abs(result.value - 15.635546873187725) < 0.000001)
    }

    @Test("vector easing matches lottie-web BezierEaser for shared component handles")
    func vectorEasingMatchesLottieWebBezierEaser() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "p": { "k": [
                { "t": 0, "s": [10, 20], "e": [110, 220], "o": { "x": 0.333, "y": 0 }, "i": { "x": 0.667, "y": 1 } },
                { "t": 10, "s": [110, 220] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let position = try #require(animation.layers.first?.transform?.position)
        let result = LottieFrameEvaluator(animation: animation).evaluate(position, at: 2.5)

        #expect(result.diagnostics.isEmpty)
        #expect(abs(result.value[0] - 25.635546873187725) < 0.000001)
        #expect(abs(result.value[1] - 51.27109374637545) < 0.000001)
    }

    @Test("vector easing uses lottie-web per-component handle arrays")
    func vectorEasingUsesPerComponentHandles() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "p": { "k": [
                {
                  "t": 0,
                  "s": [0, 0],
                  "e": [100, 100],
                  "o": { "x": [0, 0.333], "y": [0, 0] },
                  "i": { "x": [1, 0.667], "y": [1, 1] }
                },
                { "t": 10, "s": [100, 100] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let position = try #require(animation.layers.first?.transform?.position)
        let result = LottieFrameEvaluator(animation: animation).evaluate(position, at: 2.5)

        #expect(result.diagnostics.isEmpty)
        #expect(abs(result.value[0] - 25) < 0.000001)
        #expect(abs(result.value[1] - 15.635546873187725) < 0.000001)
    }

    @Test("keyframe evaluation trace records source frame span timing and final value")
    func keyframeEvaluationTraceRecordsMeasuredFacts() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "o": { "k": [
                { "t": 0, "s": [0], "e": [100], "o": { "x": 0.333, "y": 0 }, "i": { "x": 0.667, "y": 1 } },
                { "t": 10, "s": [100] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let opacity = try #require(animation.layers.first?.transform?.opacity)
        let result = LottieFrameEvaluator(animation: animation).evaluate(
            opacity,
            at: 2.5,
            path: JSONPath([.key("layers"), .index(0), .key("ks"), .key("o")])
        )

        let trace = try #require(result.trace)
        let span = try #require(trace.span)
        let timing = try #require(span.timingCurves.first)

        #expect(trace.propertyPath == "$.layers[0].ks.o")
        #expect(trace.sourceFrame == 2.5)
        #expect(trace.localFrame == 2.5)
        #expect(trace.mode == .keyframeSpan)
        #expect(trace.finalValue.count == 1)
        #expect(abs(trace.finalValue[0] - 15.635546873187725) < 0.000001)
        #expect(span.keyframeIndex == 0)
        #expect(span.authoredStartFrame == 0)
        #expect(span.authoredEndFrame == 10)
        #expect(span.evaluatedStartFrame == 0)
        #expect(span.evaluatedEndFrame == 10)
        #expect(span.startValue == [0])
        #expect(span.endValue == [100])
        #expect(span.linearProgress == 0.25)
        #expect(abs((span.timingProgress.first ?? 0) - 0.15635546873187725) < 0.000001)
        #expect(span.interpolationSpace == .value)
        #expect(timing.component == 0)
        #expect(timing.outX == 0.333)
        #expect(timing.outY == 0)
        #expect(timing.inX == 0.667)
        #expect(timing.inY == 1)
        #expect(abs(timing.result - 0.15635546873187725) < 0.000001)
    }

    @Test("lottie-web banner fixture opacity evaluates to the selected reference value")
    func fixtureEasingMatchesLottieWeb() throws {
        let animation = try decodeFixture("airbnb-lottie-web/test/animations/banner.json")
        let asset = try #require(animation.assets.first { $0.id == "comp_13" })
        let layer = try #require(asset.layers?.first { $0.name == "codepen_logo Outlines 7" })
        let opacity = try #require(layer.transform?.opacity)
        let result = LottieFrameEvaluator(animation: animation).evaluate(opacity, at: 74.75)

        #expect(result.diagnostics.isEmpty)
        #expect(abs(result.value - 15.635546873187725) < 0.000001)
    }

    @Test("spatial position interpolation matches lottie-web sampled arc length")
    func spatialInterpolationMatchesLottieWebArcLength() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "p": { "k": [
                { "t": 0, "s": [0, 0], "e": [100, 0], "to": [50, 50], "ti": [-50, -50], "o": { "x": 0.333, "y": 0 }, "i": { "x": 0.667, "y": 1 } },
                { "t": 10, "s": [100, 0] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let position = try #require(animation.layers.first?.transform?.position)
        let result = LottieFrameEvaluator(animation: animation).evaluate(
            position,
            at: 2.5,
            path: JSONPath([.key("layers"), .index(0), .key("ks"), .key("p")])
        )
        let trace = try #require(result.trace)
        let span = try #require(trace.span)
        let spatial = try #require(span.spatial)

        #expect(result.diagnostics.isEmpty)
        #expect(abs(result.value[0] - 14.581792026784122) < 0.000001)
        #expect(abs(result.value[1] - 11.330778706034625) < 0.000001)
        #expect(span.interpolationSpace == .spatialArcLength)
        #expect(abs((span.timingProgress.first ?? 0) - 0.15635546873187725) < 0.000001)
        #expect(spatial.outTangent == [50, 50])
        #expect(spatial.inTangent == [-50, -50])
        #expect(spatial.controlPoint1 == [50, 50])
        #expect(spatial.controlPoint2 == [50, -50])
        #expect(spatial.curveSegments == 150)
        #expect(abs(spatial.segmentLength - 118.54689118804974) < 0.000001)
        #expect(abs(spatial.distance - 18.535454738414366) < 0.000001)
        #expect(spatial.pointIndex == 16)
        #expect(abs((spatial.pointSegmentProgress ?? 0) - 0.09925002924447593) < 0.000001)
    }

    @Test("spatial position with incomplete tangents reports a semantic gap")
    func incompleteSpatialTangentsReportGap() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "p": { "k": [
                { "t": 0, "s": [0, 0], "e": [100, 0], "to": [50, 50], "o": { "x": 0.333, "y": 0 }, "i": { "x": 0.667, "y": 1 } },
                { "t": 10, "s": [100, 0] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let position = try #require(animation.layers.first?.transform?.position)
        let result = LottieFrameEvaluator(animation: animation).evaluate(
            position,
            at: 5,
            path: JSONPath([.key("layers"), .index(0), .key("ks"), .key("p")])
        )

        #expect(result.value == [50, 0])
        #expect(result.diagnostics.map(\.ruleID) == ["lottie.evaluation.spatial-interpolation.tangents-complete"])
        #expect(result.diagnostics.first?.codingPath.description == "$.layers[0].ks.p")
        #expect(result.trace?.span?.interpolationSpace == .value)
    }

    @Test("collinear spatial tangents are exact lottie-web linear segments")
    func collinearSpatialTangentsAreExact() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "p": { "k": [
                { "t": 0, "s": [0, 0], "e": [100, 0], "to": [50, 0], "ti": [-50, 0], "o": { "x": [0], "y": [0] }, "i": { "x": [1], "y": [1] } },
                { "t": 10, "s": [100, 0] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let position = try #require(animation.layers.first?.transform?.position)
        let result = LottieFrameEvaluator(animation: animation).evaluate(position, at: 5)

        #expect(result.value == [50, 0])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("collinear 3D spatial tangents are exact lottie-web linear segments")
    func collinear3DSpatialTangentsAreExact() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "ddd": 1,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ddd": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "p": { "k": [
                { "t": 0, "s": [0, 0, 0], "e": [0, 100, 100], "to": [0, 25, 25], "ti": [0, -25, -25], "o": { "x": [0], "y": [0] }, "i": { "x": [1], "y": [1] } },
                { "t": 10, "s": [0, 100, 100] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let position = try #require(animation.layers.first?.transform?.position)
        let result = LottieFrameEvaluator(animation: animation).evaluate(position, at: 5)

        #expect(result.value == [0, 50, 50])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("missing non-hold timing handles report a semantic gap")
    func missingTimingHandlesReportGap() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {
              "o": { "k": [
                { "t": 0, "s": [0], "e": [100] },
                { "t": 10, "s": [100] }
              ]}
            },
            "shapes": []
          }]
        }
        """)
        let opacity = try #require(animation.layers.first?.transform?.opacity)
        let result = LottieFrameEvaluator(animation: animation).evaluate(
            opacity,
            at: 5,
            path: JSONPath([.key("layers"), .index(0), .key("ks"), .key("o")])
        )

        #expect(result.value == 50)
        #expect(result.diagnostics.map(\.ruleID) == ["lottie.evaluation.keyframe-timing.handles-complete"])
        #expect(result.diagnostics.first?.codingPath.description == "$.layers[0].ks.o")
        #expect(result.trace?.span?.timingProgress == [0.5])
        #expect(result.trace?.span?.timingCurves.isEmpty == true)
    }

    @Test("animated Bezier path morphing is diagnosed")
    func pathMorphDiagnostic() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {},
            "shapes": [{
              "ty": "sh",
              "nm": "Morph",
              "ks": { "k": [
                { "t": 0, "s": [{ "i": [[0, 0]], "o": [[0, 0]], "v": [[0, 0]], "c": false }], "e": [{ "i": [[0, 0]], "o": [[0, 0]], "v": [[10, 10]], "c": false }] },
                { "t": 10, "s": [{ "i": [[0, 0]], "o": [[0, 0]], "v": [[10, 10]], "c": false }] }
              ]}
            }]
          }]
        }
        """)
        guard case let .path(path)? = animation.layers.first?.shapes?.first else {
            Issue.record("Expected first shape to be a path.")
            return
        }

        let result = LottieFrameEvaluator(animation: animation).evaluate(
            path.shape,
            at: 5,
            path: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0), .key("ks")])
        )

        #expect(result.value?.vertices == [[0, 0]])
        #expect(result.diagnostics.map(\.ruleID) == ["lottie.evaluation.path-morph.unsupported"])
    }

    @Test("stretch and time remap produce local source frames before lowering")
    func layerLocalFrameEvaluation() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 100,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 0, "ind": 1, "refId": "plain", "ip": 0, "op": 100, "st": 4, "sr": 2, "ks": {} },
            { "ty": 0, "ind": 2, "refId": "remapped", "ip": 0, "op": 60, "st": 4, "sr": 2, "tm": { "k": 2 }, "ks": {} }
          ],
          "assets": [
            { "id": "plain", "layers": [] },
            { "id": "remapped", "layers": [] }
          ]
        }
        """)
        let evaluator = LottieFrameEvaluator(animation: animation)
        let stretched = evaluator.localFrame(for: animation.layers[0], at: 10)
        let remapped = evaluator.localFrame(for: animation.layers[1], at: 10)

        #expect(stretched.value == 3)
        #expect(stretched.diagnostics.isEmpty)
        #expect(remapped.value == 59)
        #expect(remapped.diagnostics.isEmpty)
    }

    @Test("zero stretch is a structured diagnostic")
    func zeroStretchDiagnostic() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{ "ty": 4, "ind": 1, "ip": 0, "op": 20, "st": 0, "sr": 0, "ks": {}, "shapes": [] }]
        }
        """)
        let result = LottieFrameEvaluator(animation: animation).localFrame(
            for: animation.layers[0],
            at: 10,
            path: JSONPath([.key("layers"), .index(0)])
        )

        #expect(result.value == 0)
        #expect(result.diagnostics.map(\.ruleID) == ["lottie.evaluation.layer-stretch.nonzero"])
        #expect(result.diagnostics.first?.codingPath.description == "$.layers[0].sr")
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }

    private func decodeFixture(_ relativePath: String) throws -> LottieAnimation {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieCorpus", isDirectory: true)
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        return try LottieAnimation.decode(from: data)
    }
}
