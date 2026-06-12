import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie composition VM")
struct LottieCompositionVMTests {
    @Test("debug trace records authored source decisions and render nodes")
    func debugTraceRecordsSourceDecisionsAndRenderNodes() throws {
        let animation = try decode(shapeFixture)
        let result = LottieCompositionVM(animation: animation, checkpointInterval: 2)
            .run(at: 0, mode: .debug)

        #expect(result.diagnostics.isEmpty)
        #expect(result.trace.map(\.instruction.kind).contains(.enterComposition))
        #expect(result.trace.map(\.instruction.kind).contains(.evaluateLocalFrame))
        #expect(result.trace.map(\.instruction.kind).contains(.evaluateTransform))
        #expect(result.trace.map(\.instruction.kind).contains(.enterMatte))
        #expect(result.trace.map(\.instruction.kind).contains(.pushStyle))
        #expect(result.trace.map(\.instruction.kind).contains(.applyModifier))
        #expect(result.trace.map(\.instruction.kind).contains(.emitRenderNode))

        let mask = try #require(result.trace.first { $0.instruction.kind == .enterMatte })
        #expect(mask.sourcePath == "root > layer 'Shapes' > mask 'Cut'")
        #expect(mask.jsonPath.description == "$.layers[0].masksProperties[0]")
        #expect(mask.evaluatedValues["mode"] == "a")
        #expect(mask.evaluatedValues["inverted"] == "true")

        let style = try #require(result.trace.first { $0.instruction.kind == .pushStyle })
        #expect(style.sourcePath == "root > layer 'Shapes' > fill 'Red'")
        #expect(style.jsonPath.description == "$.layers[0].shapes[2]")
        #expect(style.evaluatedValues["fragments"] == "1")

        let modifier = try #require(result.trace.first { $0.instruction.kind == .applyModifier })
        #expect(modifier.sourcePath == "root > layer 'Shapes' > trim 'Half'")
        #expect(modifier.jsonPath.description == "$.layers[0].shapes[1]")
        #expect(modifier.evaluatedValues["target"] == "root > layer 'Shapes' > rectangle 'Box'")
        #expect(modifier.evaluatedValues["start"] == "10")
        #expect(modifier.evaluatedValues["end"] == "60")
        #expect(modifier.evaluatedValues["offset"] == "5")

        let render = try #require(result.trace.first { $0.instruction.kind == .emitRenderNode })
        #expect(render.renderNodeID == LottieRenderNodeID(rawValue: 1))
        #expect(render.jsonPath.description == "$.layers[0].shapes[2]")
        #expect(render.state.compositionStack == ["Root"])
        #expect(render.state.layerStack == ["root > layer 'Shapes'"])
        #expect(render.state.transformStack == ["root > layer 'Shapes' > transform"])
        #expect(result.renderNodeIDs == [LottieRenderNodeID(rawValue: 1)])
        #expect(result.readableTrace.contains("emitRenderNode"))
        #expect(result.state(after: render.step) == render.state)
        #expect(result.checkpoints.first?.step == 0)
        #expect(result.checkpoint(beforeOrAt: render.step) != nil)
    }

    @Test("fast trace removes debug-only evaluation records but preserves render sequence")
    func fastTracePreservesRenderSequence() throws {
        let animation = try decode(shapeFixture)
        let debug = LottieCompositionVM(animation: animation).run(at: 0, mode: .debug)
        let fast = LottieCompositionVM(animation: animation).run(at: 0, mode: .fast)

        #expect(debug.trace.count > fast.trace.count)
        #expect(!fast.trace.map(\.instruction.kind).contains(.evaluateLocalFrame))
        #expect(!fast.trace.map(\.instruction.kind).contains(.evaluateTransform))
        #expect(fast.trace.map(\.instruction.kind).contains(.applyModifier))
        #expect(fast.renderNodeIDs == debug.renderNodeIDs)
    }

    @Test("precompositions and skipped layers are explicit")
    func precompositionsAndSkippedLayersAreExplicit() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [
            {
              "ty": 4,
              "nm": "Outside",
              "ind": 1,
              "ip": 10,
              "op": 20,
              "st": 0,
              "ks": {},
              "shapes": [
                { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
                { "ty": "fl", "nm": "Red", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
              ]
            },
            {
              "ty": 0,
              "nm": "PrecompLayer",
              "ind": 2,
              "refId": "compA",
              "ip": 0,
              "op": 30,
              "st": 0,
              "ks": {}
            }
          ],
          "assets": [{
            "id": "compA",
            "layers": [{
              "ty": 1,
              "nm": "SolidChild",
              "ind": 1,
              "ip": 0,
              "op": 30,
              "st": 0,
              "ks": {},
              "sc": "#ff0000",
              "sw": 40,
              "sh": 20
            }]
          }]
        }
        """)

        let result = LottieCompositionVM(animation: animation).run(at: 0, mode: .debug)

        let precomp = try #require(result.trace.first { $0.instruction.kind == .enterPrecomposition })
        #expect(precomp.sourcePath == "root > layer 'PrecompLayer'")
        #expect(precomp.jsonPath.description == "$.layers[1]")

        let render = try #require(result.trace.first { $0.instruction.kind == .emitRenderNode })
        #expect(render.sourcePath == "root > layer 'PrecompLayer' > precomp 'compA' > layer 'SolidChild'")
        #expect(render.jsonPath.description == "$.assets[0].layers[0]")
        #expect(render.state.compositionStack == ["Root", "precomp:compA"])
        #expect(render.state.transformStack == [
            "root > layer 'PrecompLayer' > transform",
            "root > layer 'PrecompLayer' > precomp 'compA' > layer 'SolidChild' > transform",
        ])
        #expect(render.evaluatedValues["color"] == "#ff0000")

        let skipped = try #require(result.trace.first { $0.instruction.kind == .skipLayer })
        #expect(skipped.sourcePath == "root > layer 'Outside'")
        #expect(skipped.evaluatedValues["reason"] == "outsideFrameWindow")
        #expect(skipped.evaluatedValues["ip"] == "10")
        #expect(skipped.evaluatedValues["op"] == "20")
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }

    private var shapeFixture: String {
        """
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "nm": "Shapes",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "st": 0,
            "ks": {
              "p": { "a": 0, "k": [5, 6, 0] },
              "o": { "a": 0, "k": 100 }
            },
            "masksProperties": [{
              "nm": "Cut",
              "mode": "a",
              "inv": true,
              "pt": {
                "a": 0,
                "k": {
                  "c": true,
                  "v": [[0, 0], [10, 0], [10, 10]],
                  "i": [[0, 0], [0, 0], [0, 0]],
                  "o": [[0, 0], [0, 0], [0, 0]]
                }
              }
            }],
            "shapes": [
              { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "tm", "nm": "Half", "s": { "a": 0, "k": 10 }, "e": { "a": 0, "k": 60 }, "o": { "a": 0, "k": 5 }, "m": 1 },
              { "ty": "fl", "nm": "Red", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }]
        }
        """
    }
}
