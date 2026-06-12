import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie RenderIR")
struct LottieRenderIRTests {
    @Test("semantic frame emits evaluated RenderIR without PureLayer")
    func semanticFrameEmitsEvaluatedRenderIRWithoutPureLayer() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 10,
          "ip": 0,
          "op": 10,
          "w": 100,
          "h": 80,
          "layers": [
            {
              "ty": 4,
              "nm": "Shapes",
              "ind": 1,
              "ip": 0,
              "op": 10,
              "st": 0,
              "ks": {
                "p": { "a": 0, "k": [20, 30, 0] },
                "o": { "a": 0, "k": 50 }
              },
              "masksProperties": [{
                "nm": "Cut",
                "mode": "a",
                "inv": false,
                "o": { "a": 0, "k": 25 },
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
                {
                  "ty": "rc",
                  "nm": "Box",
                  "p": { "a": 1, "k": [{ "t": 0, "s": [10, 10] }, { "t": 10, "s": [30, 10] }] },
                  "s": { "a": 1, "k": [{ "t": 0, "s": [10, 10] }, { "t": 10, "s": [30, 10] }] },
                  "r": { "a": 0, "k": 0 }
                },
                {
                  "ty": "fl",
                  "nm": "Blend",
                  "c": { "a": 1, "k": [{ "t": 0, "s": [1, 0, 0, 1] }, { "t": 10, "s": [0, 0, 1, 1] }] },
                  "o": { "a": 0, "k": 100 },
                  "r": 1
                }
              ]
            },
            {
              "ty": 2,
              "nm": "Picture",
              "ind": 2,
              "refId": "img_0",
              "ip": 0,
              "op": 10,
              "st": 0,
              "ks": {}
            }
          ],
          "assets": [{ "id": "img_0", "nm": "Image Asset", "w": 64, "h": 32 }]
        }
        """)

        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 5)

        #expect(frame.diagnostics.isEmpty)
        #expect(frame.width == 100)
        #expect(frame.height == 80)
        #expect(frame.nodes.count == 2)

        let image = try #require(frame.nodes.first { $0.layerName == "Picture" })
        if case let .imagePlaceholder(asset) = image.kind {
            #expect(asset?.id == "img_0")
            #expect(asset?.width == 64)
            #expect(asset?.height == 32)
        } else {
            Issue.record("Expected an image placeholder node.")
        }

        let shapeNode = try #require(frame.nodes.first { $0.layerName == "Shapes" })
        #expect(shapeNode.trace.nodeID == shapeNode.id)
        #expect(shapeNode.trace.instruction == .emitRenderNode)
        #expect(shapeNode.trace.compositionStack == ["Root"])
        #expect(shapeNode.trace.layerStack == ["root > layer 'Shapes'"])
        #expect(shapeNode.source.jsonPath.description == "$.layers[0]")
        #expect(shapeNode.localFrame == 5)
        #expect(abs(shapeNode.opacity - 0.5) < 0.0001)
        #expect(abs(shapeNode.transform.worldMatrix.values[12] - 20) < 0.0001)
        #expect(abs(shapeNode.transform.worldMatrix.values[13] - 30) < 0.0001)
        #expect(shapeNode.masks.first?.source.sourcePath == "root > layer 'Shapes' > mask 'Cut'")
        #expect(shapeNode.masks.first?.source.jsonPath.description == "$.layers[0].masksProperties[0]")
        #expect(abs((shapeNode.masks.first?.opacity ?? 0) - 0.25) < 0.0001)

        guard case let .shape(shape) = shapeNode.kind else {
            Issue.record("Expected a shape RenderIR node.")
            return
        }
        let draw = try #require(shape.draws.first)
        #expect(draw.source.sourcePath == "root > layer 'Shapes' > fill 'Blend'")
        if case let .fill(fill) = draw.style {
            #expect(abs(fill.color[0] - 0.5) < 0.0001)
            #expect(abs(fill.color[2] - 0.5) < 0.0001)
            #expect(fill.isColorAnimated)
        } else {
            Issue.record("Expected an evaluated fill style.")
        }

        let fragment = try #require(draw.fragments.first)
        if case let .rectangle(center, size, roundness) = fragment.geometry {
            #expect(center == [20, 10])
            #expect(size == [20, 10])
            #expect(roundness == 0)
        } else {
            Issue.record("Expected an evaluated rectangle.")
        }
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }
}
