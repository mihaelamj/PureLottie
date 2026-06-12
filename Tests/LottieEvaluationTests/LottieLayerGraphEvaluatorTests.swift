import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie layer graph evaluator")
struct LottieLayerGraphEvaluatorTests {
    @Test("trace records render order and op-exclusive layer boundaries")
    func traceRecordsRenderOrderAndOpExclusiveBoundaries() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 30,
          "ip": 0,
          "op": 10,
          "w": 100,
          "h": 100,
          "layers": [
            { "ty": 4, "nm": "Top", "ind": 1, "ip": 0, "op": 5, "st": 0, "ks": {}, "shapes": [] },
            { "ty": 1, "nm": "Bottom", "ind": 2, "ip": 0, "op": 10, "st": 0, "ks": {}, "sc": "#0000ff", "sw": 20, "sh": 20 }
          ]
        }
        """)

        let evaluator = LottieLayerGraphEvaluator(animation: animation)
        let frameFour = evaluator.trace(at: 4)

        #expect(frameFour.frameWindow.containsSelectedFrame)
        #expect(frameFour.frameWindow.referenceSemantics.contains {
            $0.engine == "lottie-web" && $0.statement.contains("strictly less than `op`")
        })
        #expect(frameFour.frameWindow.referenceSemantics.contains {
            $0.engine == "CoreAnimation/PureLayer lowering"
                && $0.divergence == "CoreAnimation duration APIs are not used as source-frame truth."
        })
        #expect(frameFour.participatingSourcePaths == [
            "root > layer 'Bottom'",
            "root > layer 'Top'",
        ])
        #expect(try record("Bottom", in: frameFour).renderOrder == 0)
        #expect(try record("Top", in: frameFour).renderOrder == 1)
        #expect(try record("Top", in: frameFour).visibility.windowRule == "ip <= frame < op")
        #expect(try record("Top", in: frameFour).visibility.ordinaryContentVisible)

        let frameFive = evaluator.trace(at: 5)
        let top = try record("Top", in: frameFive)
        #expect(top.participation == .skippedOutsideFrame)
        #expect(!top.visibility.containsFrame)
        #expect(top.renderOrder == nil)
        #expect(frameFive.participatingSourcePaths == ["root > layer 'Bottom'"])
    }

    @Test("hidden parent layers are retained as transform participants")
    func hiddenParentLayersAreRetainedAsTransformParticipants() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 100,
          "h": 100,
          "layers": [
            { "ty": 3, "nm": "Hidden Parent", "ind": 1, "hd": true, "ip": 0, "op": 20, "st": 0, "ks": { "p": { "a": 0, "k": [10, 0, 0] } } },
            { "ty": 4, "nm": "Child", "ind": 2, "parent": 1, "ip": 0, "op": 20, "st": 0, "ks": {}, "shapes": [] }
          ]
        }
        """)

        let trace = LottieLayerGraphEvaluator(animation: animation).trace(at: 0)
        let parent = try record("Hidden Parent", in: trace)
        let child = try record("Child", in: trace)

        #expect(parent.participation == .hiddenParent)
        #expect(parent.visibility.isHidden)
        #expect(parent.renderOrder != nil)
        #expect(child.parentChain.count == 1)
        #expect(child.parentChain.first?.sourcePath == "root > layer 'Hidden Parent'")
        #expect(child.parentChain.first?.isHidden == true)
    }

    @Test("precomposition layers record local frame and time remap seconds")
    func precompositionLayersRecordLocalFrameAndTimeRemapSeconds() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 10,
          "ip": 0,
          "op": 40,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 0,
            "nm": "Remapped Precomp",
            "ind": 1,
            "refId": "compA",
            "ip": 0,
            "op": 40,
            "st": 5,
            "tm": { "a": 0, "k": 1.5 },
            "ks": {}
          }],
          "assets": [{
            "id": "compA",
            "w": 50,
            "h": 40,
            "layers": [
              { "ty": 1, "nm": "Child Solid", "ind": 1, "ip": 10, "op": 20, "st": 0, "ks": {}, "sc": "#ff0000", "sw": 10, "sh": 10 }
            ]
          }]
        }
        """)

        let trace = LottieLayerGraphEvaluator(animation: animation).trace(at: 20)
        let precomp = try record("Remapped Precomp", in: trace)
        let child = try record("Child Solid", in: trace)

        #expect(precomp.participation == .precompositionBoundary)
        #expect(precomp.timing.mode == .timeRemapSeconds)
        #expect(precomp.timing.inputFrame == 20)
        #expect(precomp.timing.startTime == 5)
        #expect(precomp.timing.timeRemapSeconds == 1.5)
        #expect(precomp.timing.localFrame == 15)
        #expect(precomp.timing.timeRemapPropertyTrace?.propertyPath == "$.layers[0].tm")
        #expect(precomp.precomposition?.assetID == "compA")
        #expect(precomp.precomposition?.assetJsonPath == "$.assets[0]")
        #expect(precomp.precomposition?.localFrame == 15)
        #expect(precomp.precomposition?.childLayerCount == 1)

        #expect(child.compositionStack == ["Root", "precomp:compA"])
        #expect(child.compositionPath == "root > layer 'Remapped Precomp' > precomp 'compA'")
        #expect(child.visibility.selectedFrame == 15)
        #expect(child.participation == .content)
    }

    @Test("mask diagnostics identify mask source and target layer paths")
    func maskDiagnosticsIdentifySourceAndTargetLayerPaths() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 30,
          "ip": 0,
          "op": 10,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "nm": "Masked",
            "ind": 1,
            "ip": 0,
            "op": 10,
            "st": 0,
            "ks": {},
            "masksProperties": [{
              "nm": "Subtract",
              "mode": "s",
              "inv": true,
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
            "shapes": []
          }]
        }
        """)

        let trace = LottieLayerGraphEvaluator(animation: animation).trace(at: 0)
        let layer = try record("Masked", in: trace)
        let mask = try #require(layer.masks.first)

        #expect(mask.sourcePath == "root > layer 'Masked' > mask 'Subtract'")
        #expect(mask.targetLayerPath == "root > layer 'Masked'")
        #expect(mask.opacity == 0.25)
        #expect(mask.mode == "s")
        #expect(mask.inverted)
        #expect(mask.path?.vertices.count == 3)
        #expect(mask.diagnostics.contains {
            $0.ruleID == "lottie.evaluation.layer-graph.mask.edge"
                && $0.sourcePath == mask.sourcePath
                && $0.targetPath == "root > layer 'Masked'"
        })
        #expect(mask.diagnostics.contains { $0.ruleID == "lottie.evaluation.layer-graph.mask.mode" })
        #expect(mask.diagnostics.contains { $0.ruleID == "lottie.evaluation.layer-graph.mask.inverted" })
    }

    @Test("matte diagnostics identify hidden source and target layer paths")
    func matteDiagnosticsIdentifyHiddenSourceAndTargetLayerPaths() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 30,
          "ip": 0,
          "op": 10,
          "w": 100,
          "h": 100,
          "layers": [
            { "ty": 4, "nm": "Matte", "ind": 1, "hd": true, "ip": 0, "op": 10, "st": 0, "ks": {}, "shapes": [] },
            { "ty": 4, "nm": "Target", "ind": 2, "tt": 1, "ip": 0, "op": 10, "st": 0, "ks": {}, "shapes": [] }
          ]
        }
        """)

        let trace = LottieLayerGraphEvaluator(animation: animation).trace(at: 0)
        let matte = try record("Matte", in: trace)
        let target = try record("Target", in: trace)

        #expect(matte.participation == .hiddenMatteSource)
        #expect(matte.visibility.isHidden)
        #expect(target.matte?.mode == 1)
        #expect(target.matte?.sourceLayerIndex == 1)
        #expect(target.matte?.sourceLayerPath == "root > layer 'Matte'")
        #expect(target.matte?.sourceLayerJsonPath == "$.layers[0]")
        #expect(target.matte?.targetLayerPath == "root > layer 'Target'")
        #expect(target.matte?.explicitSource == false)
        #expect(target.matte?.sourceResolved == true)
        #expect(target.matte?.diagnostics.contains {
            $0.ruleID == "lottie.evaluation.layer-graph.matte.edge"
                && $0.sourcePath == "root > layer 'Matte'"
                && $0.targetPath == "root > layer 'Target'"
        } == true)
    }

    @Test("explicit track matte source resolves by layer index")
    func explicitTrackMatteSourceResolvesByLayerIndex() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 30,
          "ip": 0,
          "op": 10,
          "w": 100,
          "h": 100,
          "layers": [
            { "ty": 4, "nm": "Unrelated", "ind": 1, "ip": 0, "op": 10, "st": 0, "ks": {}, "shapes": [] },
            { "ty": 4, "nm": "Explicit Matte", "ind": 7, "ip": 0, "op": 10, "st": 0, "ks": {}, "shapes": [] },
            { "ty": 4, "nm": "Target", "ind": 2, "tt": 1, "tp": 7, "ip": 0, "op": 10, "st": 0, "ks": {}, "shapes": [] }
          ]
        }
        """)

        let trace = LottieLayerGraphEvaluator(animation: animation).trace(at: 0)
        let source = try record("Explicit Matte", in: trace)
        let target = try record("Target", in: trace)

        #expect(source.participation == .matteSource)
        #expect(target.matte?.explicitSource == true)
        #expect(target.matte?.sourceLayerIndex == 7)
        #expect(target.matte?.sourceLayerPath == "root > layer 'Explicit Matte'")
        #expect(target.matte?.sourceLayerJsonPath == "$.layers[1]")
        #expect(target.matte?.sourceResolved == true)
    }

    @Test("RenderIR frames carry the measured layer graph trace")
    func renderIRFramesCarryMeasuredLayerGraphTrace() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "nm": "Root",
          "fr": 30,
          "ip": 0,
          "op": 10,
          "w": 100,
          "h": 100,
          "layers": [
            { "ty": 4, "nm": "Shape", "ind": 1, "ip": 0, "op": 10, "st": 0, "ks": {}, "shapes": [] }
          ]
        }
        """)

        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 0)
        let encoded = try JSONEncoder().encode(frame.layerGraph)
        let decoded = try JSONDecoder().decode(LottieLayerGraphTrace.self, from: encoded)

        #expect(decoded == frame.layerGraph)
        #expect(frame.layerGraph.sourceFrame == 0)
        #expect(frame.layerGraph.participatingSourcePaths == ["root > layer 'Shape'"])
    }

    private func record(_ name: String, in trace: LottieLayerGraphTrace) throws -> LottieLayerGraphLayerTrace {
        try #require(trace.records.first { $0.name == name })
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }
}
