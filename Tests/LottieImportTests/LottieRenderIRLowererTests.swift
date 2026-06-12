import Foundation
import LottieEvaluation
import LottieImport
import LottieModel
import PureLayer
import Testing

@Suite("Lottie RenderIR PureLayer lowering")
struct LottieRenderIRLowererTests {
    @Test("lowerer assigns evaluated frame values to PureLayer")
    func lowererAssignsEvaluatedFrameValuesToPureLayer() throws {
        let frame = try renderFrame(from: """
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 10,
          "ip": 0,
          "op": 10,
          "w": 100,
          "h": 80,
          "layers": [{
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
          }],
          "assets": []
        }
        """, at: 5)

        let tree = LottieRenderIRLowerer().lower(frame)

        #expect(tree.report.isClean)
        let renderNode = try #require(frame.nodes.first)
        let layer = try #require(tree.root.sublayers.first { $0.name == renderNode.id.description })
        #expect(abs(layer.opacity - 0.5) < 0.0001)
        #expect(abs(layer.transform.m41 - 20) < 0.0001)
        #expect(abs(layer.transform.m42 - 30) < 0.0001)

        let shapeLayer = try #require(allShapeLayers(in: tree.root).first)
        let color = try #require(shapeLayer.fillColor)
        #expect(abs(color.red - 0.5) < 0.0001)
        #expect(abs(color.blue - 0.5) < 0.0001)
        let box = try #require(shapeLayer.path?.boundingBox)
        #expect(abs(box.minX - 10) < 0.0001)
        #expect(abs(box.maxX - 30) < 0.0001)
    }

    @Test("backend gaps are reported with RenderIR source path")
    func backendGapsAreReportedWithRenderIRSourcePath() throws {
        let frame = try renderFrame(from: """
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
              "ty": 1,
              "nm": "MatteSource",
              "ind": 1,
              "ip": 0,
              "op": 10,
              "st": 0,
              "ks": {},
              "sc": "#ffffff",
              "sw": 100,
              "sh": 80
            },
            {
              "ty": 4,
              "nm": "Shapes",
              "ind": 2,
              "tt": 1,
              "ip": 0,
              "op": 10,
              "st": 0,
              "ks": {},
              "masksProperties": [{
                "nm": "Subtract",
                "mode": "s",
                "inv": false,
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
                {
                  "ty": "st",
                  "nm": "Fancy",
                  "c": { "a": 0, "k": [0, 0, 1, 1] },
                  "o": { "a": 0, "k": 100 },
                  "w": { "a": 0, "k": 2 },
                  "lc": 2,
                  "lj": 3,
                  "ml": 4,
                  "ml2": { "a": 0, "k": 6 },
                  "bm": 2,
                  "d": [{ "n": "d", "v": { "a": 0, "k": 4 } }]
                }
              ]
            }
          ],
          "assets": []
        }
        """, at: 0)

        let tree = LottieRenderIRLowerer().lower(frame)
        let findings = tree.report.findings

        #expect(findings.contains {
            $0.feature == "track matte mode 1 using root > layer 'MatteSource'"
                && $0.path == "root > layer 'Shapes'"
        })
        #expect(findings.contains {
            $0.feature == "mask mode 's'"
                && $0.path == "root > layer 'Shapes' > mask 'Subtract'"
        })
        #expect(findings.contains {
            $0.feature == "stroke blend mode"
                && $0.path == "root > layer 'Shapes' > stroke 'Fancy'"
        })
        #expect(findings.contains {
            $0.feature == "stroke line cap"
                && $0.path == "root > layer 'Shapes' > stroke 'Fancy'"
        })
        #expect(findings.contains {
            $0.feature == "stroke dash pattern"
                && $0.path == "root > layer 'Shapes' > stroke 'Fancy'"
        })
    }

    private func renderFrame(from source: String, at frame: Double) throws -> LottieRenderFrame {
        let animation = try LottieAnimation.decode(from: Data(source.utf8))
        return LottieRenderIRBuilder(animation: animation).frame(at: frame)
    }

    private func allShapeLayers(in layer: Layer) -> [ShapeLayer] {
        var result: [ShapeLayer] = []
        if let shape = layer as? ShapeLayer {
            result.append(shape)
        }
        for sublayer in layer.sublayers {
            result.append(contentsOf: allShapeLayers(in: sublayer))
        }
        return result
    }
}
