import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie source-intent decompiler")
struct LottieSourceIntentDecompilerTests {
    @Test("RenderIR decompiles to source-intent facts with path-bearing provenance")
    func renderIRDecompilesToSourceIntentFactsWithPathBearingProvenance() throws {
        let frame = try LottieRenderIRBuilder(animation: decode(baseAnimation)).frame(at: 5)

        let intent = LottieSourceIntentDecompiler().decompile(
            frame: frame,
            source: LottieDecompiledSourceIntentSource(identity: "inline-shape-image", frameCount: 0)
        )

        try intent.validate()
        #expect(intent.schema.name == "purelottie.decompiled-source-intent")
        #expect(intent.schema.version == 1)
        #expect(intent.source.frameCount == 1)
        #expect(intent.composition.width == 100)
        #expect(intent.composition.height == 80)
        #expect(intent.composition.frameRate == 10)
        #expect(intent.roundTrip.laws.contains("source facts must retain sourcePath and jsonPath"))

        let decompiledFrame = try #require(intent.frames.first)
        #expect(decompiledFrame.sourceFrame == 5)
        #expect(decompiledFrame.localTimeSeconds == 0.5)
        #expect(decompiledFrame.losses.isEmpty)

        let shapeLayer = try #require(decompiledFrame.visibleLayers.first { $0.name == "Shapes" })
        #expect(shapeLayer.id == "render#2")
        #expect(shapeLayer.type == .shape)
        #expect(shapeLayer.localFrame == 5)
        #expect(abs(shapeLayer.opacity - 0.5) < 0.0001)
        #expect(shapeLayer.provenance.sourcePath == "root > layer 'Shapes'")
        #expect(shapeLayer.provenance.jsonPath == "$.layers[0]")
        #expect(shapeLayer.transform.provenance.jsonPath == "$.layers[0].ks")
        #expect(abs(shapeLayer.transform.matrix.values[12] - 20) < 0.0001)
        #expect(abs(shapeLayer.transform.matrix.values[13] - 30) < 0.0001)

        let geometry = try #require(shapeLayer.geometry.first)
        #expect(geometry.kind == .rectangle)
        #expect(geometry.primitive == "rc")
        #expect(geometry.parameters["center"] == [20, 10])
        #expect(geometry.parameters["size"] == [20, 10])
        #expect(geometry.provenance.jsonPath == "$.layers[0].shapes[0]")

        let style = try #require(shapeLayer.styles.first)
        #expect(style.kind == .fill)
        #expect(abs((style.color?[0] ?? 0) - 0.5) < 0.0001)
        #expect(abs((style.color?[2] ?? 0) - 0.5) < 0.0001)
        #expect(style.provenance.jsonPath == "$.layers[0].shapes[1]")

        let mask = try #require(shapeLayer.masks.first)
        #expect(mask.name == "Cut")
        #expect(mask.mode == "a")
        #expect(mask.opacity == 0.25)
        #expect(mask.provenance.jsonPath == "$.layers[0].masksProperties[0]")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(intent)
        let decoded = try LottieDecompiledSourceIntent.decodeValidated(from: encoded)
        #expect(decoded == intent)
    }

    @Test("missing provenance requires an explicit loss record at the same model path")
    func missingProvenanceRequiresExplicitLossRecordAtSameModelPath() throws {
        var intent = try validIntent()
        intent.frames[0].visibleLayers[0].provenance.sourcePath = ""

        let validator = LottieDecompiledSourceIntentValidator()
        let errors = validator.collectErrors(in: intent)
        #expect(errors.contains { $0.ruleID == "lottie.decompile.provenance.source-path" })

        intent.frames[0].losses.append(LottieDecompiledSourceIntentLoss(
            kind: .missingSourceFact,
            reconstructability: .notReconstructable,
            phase: "decompile",
            classification: "gap",
            modelPath: "$.frames[0].visibleLayers[0].provenance",
            sourcePath: "root > layer 'Picture'",
            jsonPath: "$.layers[1]",
            reason: "Synthetic test loss explicitly records the missing provenance fact."
        ))

        let repairedErrors = validator.collectErrors(in: intent)
        #expect(!repairedErrors.contains { $0.ruleID == "lottie.decompile.provenance.source-path" })
    }

    @Test("semantic diagnostics become decompiler loss records")
    func semanticDiagnosticsBecomeDecompilerLossRecords() throws {
        let frame = try LottieRenderIRBuilder(animation: decode(skewAnimation)).frame(at: 0)
        #expect(frame.diagnostics.contains { $0.ruleID == "lottie.evaluation.transform.skew.unsupported" })

        let intent = LottieSourceIntentDecompiler().decompile(
            frame: frame,
            source: LottieDecompiledSourceIntentSource(identity: "skew", frameCount: 0)
        )

        try intent.validate()
        let loss = try #require(intent.frames.first?.losses.first)
        #expect(loss.kind == .unsupported)
        #expect(loss.reconstructability == .notReconstructable)
        #expect(loss.ruleID == "lottie.evaluation.transform.skew.unsupported")
        #expect(loss.jsonPath == "$.layers[0].ks.sk")
        #expect(loss.reason.contains("Transform skew"))
    }

    @Test("shape transform matrices are reconstructed from evaluated components")
    func shapeTransformMatricesAreReconstructedFromEvaluatedComponents() throws {
        let frame = try LottieRenderIRBuilder(animation: decode(groupTransformAnimation)).frame(at: 0)

        let intent = LottieSourceIntentDecompiler().decompile(
            frame: frame,
            source: LottieDecompiledSourceIntentSource(identity: "group-transform", frameCount: 0)
        )

        try intent.validate()
        let layer = try #require(intent.frames.first?.visibleLayers.first)
        let transform = try #require(layer.geometry.first?.transformStack.first)
        #expect(transform.position == [12, 8, 0])
        #expect(transform.scale == [200, 100, 100])
        #expect(transform.matrix.values[0] == 2)
        #expect(transform.matrix.values[5] == 1)
        #expect(transform.matrix.values[12] == 12)
        #expect(transform.matrix.values[13] == 8)
    }

    @Test("unsupported layer nodes are represented as decompiler losses")
    func unsupportedLayerNodesAreRepresentedAsDecompilerLosses() throws {
        let frame = try LottieRenderIRBuilder(animation: decode(unsupportedLayerAnimation)).frame(at: 0)

        let intent = LottieSourceIntentDecompiler().decompile(
            frame: frame,
            source: LottieDecompiledSourceIntentSource(identity: "unsupported-layer", frameCount: 0)
        )

        try intent.validate()
        let layer = try #require(intent.frames.first?.visibleLayers.first)
        #expect(layer.type == .unsupported)
        #expect(layer.diagnostics.first?.ruleID == "lottie.decompile.layer.unsupported-type")

        let loss = try #require(intent.frames.first?.losses.first)
        #expect(loss.kind == .unsupported)
        #expect(loss.ruleID == "lottie.decompile.layer.unsupported-type")
        #expect(loss.modelPath == "$.frames[0].visibleLayers[0]")
        #expect(loss.jsonPath == "$.layers[0].ty")
    }

    private func validIntent() throws -> LottieDecompiledSourceIntent {
        let frame = try LottieRenderIRBuilder(animation: decode(baseAnimation)).frame(at: 5)
        return LottieSourceIntentDecompiler().decompile(
            frame: frame,
            source: LottieDecompiledSourceIntentSource(identity: "inline-shape-image", frameCount: 0)
        )
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }

    private var baseAnimation: String {
        """
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
                  "p": { "a": 1, "k": [{ "t": 0, "s": [10, 10], "o": { "x": [0, 0], "y": [0, 0] }, "i": { "x": [1, 1], "y": [1, 1] } }, { "t": 10, "s": [30, 10] }] },
                  "s": { "a": 1, "k": [{ "t": 0, "s": [10, 10], "o": { "x": [0, 0], "y": [0, 0] }, "i": { "x": [1, 1], "y": [1, 1] } }, { "t": 10, "s": [30, 10] }] },
                  "r": { "a": 0, "k": 0 }
                },
                {
                  "ty": "fl",
                  "nm": "Blend",
                  "c": { "a": 1, "k": [{ "t": 0, "s": [1, 0, 0, 1], "o": { "x": [0, 0, 0, 0], "y": [0, 0, 0, 0] }, "i": { "x": [1, 1, 1, 1], "y": [1, 1, 1, 1] } }, { "t": 10, "s": [0, 0, 1, 1] }] },
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
        """
    }

    private var skewAnimation: String {
        """
        {
          "v": "5.7.4",
          "nm": "Skew",
          "fr": 10,
          "ip": 0,
          "op": 10,
          "w": 64,
          "h": 64,
          "layers": [
            {
              "ty": 4,
              "nm": "Skewed",
              "ind": 1,
              "ip": 0,
              "op": 10,
              "st": 0,
              "ks": {
                "sk": { "a": 0, "k": 15 },
                "sa": { "a": 0, "k": 0 }
              },
              "shapes": [
                {
                  "ty": "rc",
                  "nm": "Box",
                  "p": { "a": 0, "k": [32, 32] },
                  "s": { "a": 0, "k": [20, 20] },
                  "r": { "a": 0, "k": 0 }
                },
                {
                  "ty": "fl",
                  "nm": "Fill",
                  "c": { "a": 0, "k": [1, 0, 0, 1] },
                  "o": { "a": 0, "k": 100 }
                }
              ]
            }
          ]
        }
        """
    }

    private var groupTransformAnimation: String {
        """
        {
          "v": "5.7.4",
          "nm": "Group Transform",
          "fr": 10,
          "ip": 0,
          "op": 10,
          "w": 64,
          "h": 64,
          "layers": [
            {
              "ty": 4,
              "nm": "Grouped",
              "ind": 1,
              "ip": 0,
              "op": 10,
              "st": 0,
              "ks": {},
              "shapes": [
                {
                  "ty": "gr",
                  "nm": "Group",
                  "it": [
                    {
                      "ty": "rc",
                      "nm": "Box",
                      "p": { "a": 0, "k": [10, 10] },
                      "s": { "a": 0, "k": [20, 20] },
                      "r": { "a": 0, "k": 0 }
                    },
                    {
                      "ty": "fl",
                      "nm": "Fill",
                      "c": { "a": 0, "k": [0, 0, 1, 1] },
                      "o": { "a": 0, "k": 100 }
                    },
                    {
                      "ty": "tr",
                      "nm": "Group Transform",
                      "a": { "a": 0, "k": [0, 0, 0] },
                      "p": { "a": 0, "k": [12, 8, 0] },
                      "s": { "a": 0, "k": [200, 100, 100] },
                      "r": { "a": 0, "k": 0 },
                      "o": { "a": 0, "k": 100 }
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
    }

    private var unsupportedLayerAnimation: String {
        """
        {
          "v": "5.7.4",
          "nm": "Unsupported",
          "fr": 10,
          "ip": 0,
          "op": 10,
          "w": 64,
          "h": 64,
          "layers": [
            {
              "ty": 99,
              "nm": "Unsupported Layer",
              "ind": 1,
              "ip": 0,
              "op": 10,
              "st": 0,
              "ks": {}
            }
          ]
        }
        """
    }
}
