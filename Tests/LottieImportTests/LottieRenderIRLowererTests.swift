import Foundation
import LottieEvaluation
@testable import LottieImport
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

    @Test("render path reports a transform expression instead of rendering statically")
    func renderPathReportsTransformExpression() throws {
        // The position carries an AfterEffects expression (`x`). The render path
        // evaluates only the base value, so without a report it would render a
        // static layer with zero findings: a render-or-report violation. This is
        // the path real fixtures (e.g. starfish) take, since they bypass the
        // importer-scene validation gate.
        let frame = try renderFrame(from: """
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
            "nm": "Bouncing",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "st": 0,
            "ks": {
              "p": { "a": 0, "k": [50, 50], "x": "var $bm_rt;\\n$bm_rt = loopOut('cycle');" },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": []
          }],
          "assets": []
        }
        """, at: 0)

        let tree = LottieRenderIRLowerer().lower(frame)

        let finding = try #require(tree.report.findings.first { $0.feature == "position expression" })
        #expect(finding.disposition == .skipped)
        #expect(!tree.report.isClean)
    }

    @Test("additive mask fixture lowers to PureLayer alpha mask")
    func additiveMaskFixtureLowersToPureLayerAlphaMask() throws {
        let frame = try renderFrame(fixture: "mask-add-rectangle.json", at: 5)
        let node = try #require(frame.nodes.first { !$0.masks.isEmpty })
        let expectedMask = try #require(node.masks.first)
        let expectedPath = try path(from: expectedMask)

        let tree = LottieRenderIRLowerer().lower(frame)

        #expect(tree.report.findings.allSatisfy { !$0.feature.contains("mask") })
        let layer = try #require(tree.root.sublayers.first { $0.name == node.id.description })
        let maskLayer = try #require(layer.mask as? ShapeLayer)
        let actualPath = try #require(maskLayer.path)
        assertBounds(actualPath.boundingBox, matches: expectedPath.boundingBox)
        #expect(abs((maskLayer.fillColor?.alpha ?? -1) - expectedMask.opacity) < 0.0001)
    }

    @Test("alpha matte fixture lowers to wrapper mask without drawing matte source")
    func alphaMatteFixtureLowersToWrapperMask() throws {
        let frame = try renderFrame(fixture: "alpha-matte-rectangle.json", at: 5)
        let target = try #require(frame.nodes.first { $0.matte?.mode == 1 })
        let sourceIndex = try #require(target.matte?.sourceLayerIndex)
        let source = try #require(frame.nodes.first { $0.layerIndex == sourceIndex })
        let expectedSourceBounds = try firstShapeBounds(in: source)

        let tree = LottieRenderIRLowerer().lower(frame)

        #expect(tree.report.findings.allSatisfy { !$0.feature.contains("track matte") })
        let wrapper = try #require(tree.root.sublayers.first { $0.name == target.id.description })
        #expect(tree.root.sublayers.allSatisfy { $0.name != source.id.description })
        let mask = try #require(wrapper.mask)
        let maskShape = try #require(allShapeLayers(in: mask).first)
        let maskBounds = try #require(maskShape.path?.boundingBox)
        assertBounds(maskBounds, matches: expectedSourceBounds)
        #expect(wrapper.sublayers.count == 1)
        #expect(wrapper.sublayers.first?.name == target.id.description)
    }

    @Test("Lottie st stroke style lowers cap/join/miter/dash onto ShapeLayer (PureLayer#157)")
    func strokeStyleLowersOntoShapeLayer() throws {
        // lc:2->round, lj:3->bevel, ml2:6 takes precedence over ml:4, dash d=4/g=3 with
        // offset o=1 -> lineDashPattern [4,3] phase 1. None of these are reported as gaps now.
        let frame = try renderFrame(from: """
        {"v":"5.7.4","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"nm":"L","ind":1,"ip":0,"op":10,"st":0,"ks":{},"shapes":[
          {"ty":"rc","nm":"Box","p":{"a":0,"k":[32,32]},"s":{"a":0,"k":[20,20]},"r":{"a":0,"k":0}},
          {"ty":"st","nm":"S","c":{"a":0,"k":[0,0,1,1]},"o":{"a":0,"k":100},"w":{"a":0,"k":3},
           "lc":2,"lj":3,"ml":4,"ml2":{"a":0,"k":6},
           "d":[{"n":"d","v":{"a":0,"k":4}},{"n":"g","v":{"a":0,"k":3}},{"n":"o","v":{"a":0,"k":1}}]}
        ]}]}
        """, at: 0)

        let tree = LottieRenderIRLowerer().lower(frame)

        let shape = try #require(allShapeLayers(in: tree.root).first { $0.strokeColor != nil })
        #expect(shape.lineCap == .round)
        #expect(shape.lineJoin == .bevel)
        #expect(abs(shape.miterLimit - 6) < 0.0001, "ml2 should win over ml")
        #expect(shape.lineDashPattern == [4, 3])
        #expect(abs(shape.lineDashPhase - 1) < 0.0001)
        #expect(abs(shape.lineWidth - 3) < 0.0001)
        // The style fields are rendered now, so none are reported as backend gaps.
        for gap in ["stroke line cap", "stroke line join", "stroke miter limit", "secondary stroke miter limit", "stroke dash pattern"] {
            #expect(!tree.report.findings.contains { $0.feature == gap }, "\(gap) must not be reported")
        }
    }

    @Test("Lottie st maps the other cap/join codes and falls back to ml without ml2")
    func strokeStyleMapsRemainingCodes() throws {
        // lc:3->square, lj:2->round, no ml2 so ml:7 is the miter limit, no dash -> solid.
        let frame = try renderFrame(from: """
        {"v":"5.7.4","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"nm":"L","ind":1,"ip":0,"op":10,"st":0,"ks":{},"shapes":[
          {"ty":"rc","nm":"Box","p":{"a":0,"k":[32,32]},"s":{"a":0,"k":[20,20]},"r":{"a":0,"k":0}},
          {"ty":"st","nm":"S","c":{"a":0,"k":[0,0,1,1]},"o":{"a":0,"k":100},"w":{"a":0,"k":2},"lc":3,"lj":2,"ml":7}
        ]}]}
        """, at: 0)

        let tree = LottieRenderIRLowerer().lower(frame)

        let shape = try #require(allShapeLayers(in: tree.root).first { $0.strokeColor != nil })
        #expect(shape.lineCap == .square)
        #expect(shape.lineJoin == .round)
        #expect(abs(shape.miterLimit - 7) < 0.0001)
        #expect(shape.lineDashPattern.isEmpty, "no dash -> solid line")
        #expect(abs(shape.lineDashPhase) < 0.0001)
    }

    @Test("legacy 0-255 fill colours normalize to 0-1 instead of clamping to white")
    func legacyByteRangeColorNormalizes() throws {
        // Legacy bodymovin (v4) encodes colours as 0...255: [255,0,0,255] is red. Without
        // normalization every channel >1 clamps to 1 and the layer renders white (the cause
        // of complex real-world Lotties rendering blank).
        let legacy = try renderFrame(from: """
        {"v":"4.0.0","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"nm":"L","ind":1,"ip":0,"op":10,"st":0,"ks":{},"shapes":[
          {"ty":"rc","p":{"a":0,"k":[32,32]},"s":{"a":0,"k":[20,20]},"r":{"a":0,"k":0}},
          {"ty":"fl","c":{"a":0,"k":[255,0,0,255]},"o":{"a":0,"k":100}}
        ]}]}
        """, at: 0)
        let legacyShape = try #require(allShapeLayers(in: LottieRenderIRLowerer().lower(legacy).root).first { $0.fillColor != nil })
        let red = try #require(legacyShape.fillColor)
        #expect(abs(red.red - 1) < 0.01 && red.green < 0.01 && red.blue < 0.01, "0-255 red gave (\(red.red),\(red.green),\(red.blue))")

        // A modern 0...1 colour is left unchanged (no false normalization).
        let modern = try renderFrame(from: """
        {"v":"5.7.4","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"nm":"L","ind":1,"ip":0,"op":10,"st":0,"ks":{},"shapes":[
          {"ty":"rc","p":{"a":0,"k":[32,32]},"s":{"a":0,"k":[20,20]},"r":{"a":0,"k":0}},
          {"ty":"fl","c":{"a":0,"k":[0.5,0,0,1]},"o":{"a":0,"k":100}}
        ]}]}
        """, at: 0)
        let modernShape = try #require(allShapeLayers(in: LottieRenderIRLowerer().lower(modern).root).first { $0.fillColor != nil })
        #expect(abs((modernShape.fillColor?.red ?? 0) - 0.5) < 0.01, "0-1 colour must pass through unchanged")
    }

    @Test("multiply fill blend (bm=1) is rendered via extended, not reported as a gap (#178)")
    func multiplyFillBlendModeIsRenderedNotReported() throws {
        // bm=1 (multiply) is the one blend mode the software backend renders exactly. It is
        // carried onto ShapeLayer.extended.blendMode and PureLottie exports with the extended
        // compositor, so it is no longer an ImportReport gap. Other modes (e.g. bm=2 screen)
        // still fall back to normal and stay reported.
        let multiply = try renderFrame(from: """
        {"v":"5.7.4","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"nm":"L","ind":1,"ip":0,"op":10,"st":0,"ks":{},"shapes":[
          {"ty":"rc","nm":"Box","p":{"a":0,"k":[32,32]},"s":{"a":0,"k":[20,20]},"r":{"a":0,"k":0}},
          {"ty":"fl","nm":"F","c":{"a":0,"k":[1,0,1,1]},"o":{"a":0,"k":100},"bm":1}
        ]}]}
        """, at: 0)
        let multiplyTree = LottieRenderIRLowerer().lower(multiply)
        #expect(!multiplyTree.report.findings.contains { $0.feature == "fill blend mode" }, "multiply must not be reported as a gap")
        let multiplyShape = try #require(allShapeLayers(in: multiplyTree.root).first { $0.fillColor != nil })
        #expect(multiplyShape.extended.blendMode == .multiply, "multiply must be carried onto the shape")

        // A non-exact mode (bm=2 screen) is still reported.
        let screen = try renderFrame(from: """
        {"v":"5.7.4","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"nm":"L","ind":1,"ip":0,"op":10,"st":0,"ks":{},"shapes":[
          {"ty":"rc","nm":"Box","p":{"a":0,"k":[32,32]},"s":{"a":0,"k":[20,20]},"r":{"a":0,"k":0}},
          {"ty":"fl","nm":"F","c":{"a":0,"k":[1,0,1,1]},"o":{"a":0,"k":100},"bm":2}
        ]}]}
        """, at: 0)
        let screenTree = LottieRenderIRLowerer().lower(screen)
        #expect(screenTree.report.findings.contains { $0.feature == "fill blend mode" }, "non-exact blend modes stay reported")
    }

    @Test("precomposition backend evidence preserves time remap frame mapping")
    func precompositionBackendEvidencePreservesTimeRemapFrameMapping() throws {
        let frame = try renderFrame(fixture: "time-remap-precomp-diagnosed.json", at: 0)
        let boundary = try #require(frame.nodes.first { node in
            if case .precompositionBoundary = node.kind { return true }
            return false
        })
        let child = try #require(frame.nodes.first {
            $0.source.sourcePath == "root > layer 'Time Remapped Precomp' > precomp 'box_precomp' > layer 'Precomp Box'"
        })

        let tree = LottieRenderIRLowerer().lower(frame)

        #expect(boundary.localFrame == 5)
        #expect(child.localFrame == 5)
        let finding = try #require(tree.report.findings.first {
            $0.feature == "precomposition boundary 'box_precomp' flattened into evaluated child nodes"
        })
        #expect(finding.disposition == .approximated)

        let evidence = try #require(finding.evidence)
        #expect(evidence.sourceFrame == 0)
        #expect(evidence.renderNode?.sourcePath == "root > layer 'Time Remapped Precomp'")
        #expect(evidence.renderNode?.localFrame == 5)

        let graph = try #require(evidence.layerGraphRecord)
        #expect(graph.sourcePath == "root > layer 'Time Remapped Precomp'")
        #expect(graph.participation == LottieLayerGraphParticipation.precompositionBoundary.rawValue)
        #expect(graph.timingMode == LottieLayerGraphTimingMode.timeRemapSeconds.rawValue)
        #expect(graph.timingInputFrame == 0)
        #expect(graph.timingStartTime == 0)
        #expect(graph.timingStretch == 1)
        #expect(graph.timingFrameRate == 10)
        #expect(graph.timingLocalFrame == 5)
        #expect(graph.timingTimeRemapSeconds == 0.5)
        #expect(graph.timingTimeRemapPropertyPath == "$.layers[0].tm")
        #expect(graph.precompositionAssetID == "box_precomp")
        #expect(graph.precompositionPath == "root > layer 'Time Remapped Precomp' > precomp 'box_precomp'")
        #expect(graph.precompositionLocalFrame == 5)
        #expect(graph.precompositionChildLayerCount == 1)
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
              "tt": 2,
              "bm": 3,
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
                },
                {
                  "ty": "tm",
                  "nm": "Individual Trim",
                  "s": { "a": 0, "k": 0 },
                  "e": { "a": 0, "k": 50 },
                  "o": { "a": 0, "k": 15 },
                  "m": 2
                }
              ]
            },
            {
              "ty": 4,
              "nm": "FillShapes",
              "ind": 3,
              "ip": 0,
              "op": 10,
              "st": 0,
              "ks": {},
              "shapes": [
                { "ty": "rc", "nm": "FillBox", "p": { "a": 0, "k": [30, 30] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
                {
                  "ty": "tm",
                  "nm": "Fill Trim",
                  "s": { "a": 0, "k": 0 },
                  "e": { "a": 0, "k": 50 },
                  "o": { "a": 0, "k": 0 },
                  "m": 1
                },
                {
                  "ty": "fl",
                  "nm": "BlendFill",
                  "c": { "a": 0, "k": [1, 0, 0, 1] },
                  "o": { "a": 0, "k": 100 },
                  "r": 2,
                  "bm": 4
                }
              ]
            }
          ],
          "assets": []
        }
        """, at: 0)

        let evidenceContext = LottieBackendEvidenceContext(
            sourceFixture: "Tests/Fixtures/LottieOracle/backend-gap.json",
            expectedLottieWebFrameArtifact: "reference/frame_0000.00.png",
            pureLayerFrameArtifact: "purelayer/frame_0000.00.png"
        )
        let tree = LottieRenderIRLowerer().lower(frame, evidenceContext: evidenceContext)
        let findings = tree.report.findings

        try assertFinding(findings, "layer blend mode 3", path: "root > layer 'Shapes'", owner: .backendCapability)
        try assertFinding(
            findings,
            "track matte mode 2 using root > layer 'MatteSource'",
            path: "root > layer 'Shapes'",
            owner: .backendCapability
        )
        try assertFinding(findings, "mask mode 's'", path: "root > layer 'Shapes' > mask 'Subtract'", owner: .backendCapability)
        // Stroke cap/join/miter/dash now render through ShapeLayer (PureLayer#157), so
        // they are no longer reported as gaps. Only the shape blend mode remains a gap
        // (the default standard compositor does not apply it; faithful Core Animation).
        try assertFinding(findings, "stroke blend mode", path: "root > layer 'Shapes' > stroke 'Fancy'", owner: .backendCapability)
        #expect(!findings.contains { $0.feature == "stroke line cap" }, "line cap renders, must not be reported")
        #expect(!findings.contains { $0.feature == "stroke line join" }, "line join renders, must not be reported")
        #expect(!findings.contains { $0.feature == "stroke miter limit" }, "miter limit renders, must not be reported")
        #expect(!findings.contains { $0.feature == "secondary stroke miter limit" }, "ml2 renders, must not be reported")
        #expect(!findings.contains { $0.feature == "stroke dash pattern" }, "dash renders, must not be reported")
        try assertFinding(findings, "trim offset", path: "root > layer 'Shapes' > trim 'Individual Trim'", owner: .backendCapability)
        try assertFinding(
            findings,
            "individual trim (trimmed as one length)",
            path: "root > layer 'Shapes' > trim 'Individual Trim'",
            owner: .intentionalApproximation
        )
        try assertFinding(findings, "fill blend mode", path: "root > layer 'FillShapes' > fill 'BlendFill'", owner: .backendCapability)
        try assertFinding(findings, "trimmed fill path", path: "root > layer 'FillShapes' > fill 'BlendFill'", owner: .backendCapability)

        let strokeBlend = try #require(findings.first { $0.feature == "stroke blend mode" })
        let strokeEvidence = try #require(strokeBlend.evidence)
        #expect(strokeEvidence.owner == .backendCapability)
        #expect(strokeEvidence.sourceFixture == "Tests/Fixtures/LottieOracle/backend-gap.json")
        #expect(strokeEvidence.sourceFrame == 0)
        #expect(strokeEvidence.frameRate == 10)
        #expect(strokeEvidence.expectedLottieWebFrameArtifact == "reference/frame_0000.00.png")
        #expect(strokeEvidence.pureLayerFrameArtifact == "purelayer/frame_0000.00.png")
        #expect(strokeEvidence.lottiePath == "root > layer 'Shapes' > stroke 'Fancy'")
        #expect(strokeEvidence.jsonPath == "$.layers[1].shapes[1]")
        #expect(strokeEvidence.renderNode?.kind == "shape")
        #expect(strokeEvidence.renderNode?.sourcePath == "root > layer 'Shapes'")
        #expect(strokeEvidence.vmTrace?.instruction == LottieVMInstruction.Kind.emitRenderNode.rawValue)
        #expect(strokeEvidence.renderTerm?.kind == "strokeStyle")
        #expect(strokeEvidence.renderTerm?.values["blendMode"] == "2")
        #expect(strokeEvidence.renderTerm?.values["dashCount"] == "1")
        #expect(strokeEvidence.renderTerm?.values["lineCap"] == "2")
        #expect(strokeEvidence.renderTerm?.values["lineJoin"] == "3")
        #expect(strokeEvidence.renderTerm?.values["miterLimit"] == "4.0")
        #expect(strokeEvidence.renderTerm?.values["secondaryMiterLimit"] == "6.0")

        let matteFinding = try #require(findings.first { $0.feature == "track matte mode 2 using root > layer 'MatteSource'" })
        let matteEvidence = try #require(matteFinding.evidence)
        #expect(matteEvidence.layerGraphRecord?.sourcePath == "root > layer 'Shapes'")
        #expect(matteEvidence.layerGraphRecord?.matteMode == 2)
        #expect(matteEvidence.layerGraphRecord?.matteSourcePath == "root > layer 'MatteSource'")
        #expect(matteEvidence.layerGraphRecord?.diagnosticRuleIDs.contains("lottie.evaluation.layer-graph.matte.edge") == true)

        let trimFinding = try #require(findings.first { $0.feature == "individual trim (trimmed as one length)" })
        let trimEvidence = try #require(trimFinding.evidence)
        #expect(trimEvidence.owner == .intentionalApproximation)
        #expect(trimEvidence.renderTerm?.kind == "trimPath")
        #expect(trimEvidence.renderTerm?.values["multiple"] == "2")
        #expect(trimEvidence.renderTerm?.values["offset"] == "15.0")

        let layerBlend = try #require(findings.first { $0.feature == "layer blend mode 3" })
        #expect(layerBlend.sourcePath == "$.layers[1].bm")
        #expect(layerBlend.evidence?.jsonPath == "$.layers[1].bm")
        #expect(layerBlend.evidence?.renderTerm?.kind == "layerCompositing")
        #expect(layerBlend.evidence?.renderTerm?.jsonPath == "$.layers[1].bm")
        #expect(layerBlend.evidence?.renderTerm?.values["blendMode"] == "3")

        let fillBlend = try #require(findings.first { $0.feature == "fill blend mode" })
        #expect(fillBlend.evidence?.renderTerm?.kind == "fillStyle")
        #expect(fillBlend.evidence?.renderTerm?.values["blendMode"] == "4")
        #expect(fillBlend.evidence?.renderTerm?.values["fillRule"] == "2")

        let trimmedFill = try #require(findings.first { $0.feature == "trimmed fill path" })
        #expect(trimmedFill.evidence?.renderTerm?.kind == "trimmedFill")
        #expect(trimmedFill.evidence?.renderTerm?.sourcePath == "root > layer 'FillShapes' > trim 'Fill Trim'")
        #expect(trimmedFill.evidence?.renderTerm?.values["end"] == "50.0")
    }

    @Test("exact fill rule and group opacity lower without backend findings")
    func exactFillRuleAndGroupOpacityLowerWithoutBackendFindings() throws {
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
            "ks": {},
            "shapes": [{
              "ty": "gr",
              "nm": "TransparentGroup",
              "it": [
                { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [20, 20] }, "s": { "a": 0, "k": [20, 20] }, "r": { "a": 0, "k": 0 } },
                { "ty": "fl", "nm": "EvenOdd", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 2 },
                {
                  "ty": "tr",
                  "p": { "a": 0, "k": [0, 0] },
                  "a": { "a": 0, "k": [0, 0] },
                  "s": { "a": 0, "k": [100, 100] },
                  "r": { "a": 0, "k": 0 },
                  "o": { "a": 0, "k": 50 }
                }
              ]
            }]
          }],
          "assets": []
        }
        """, at: 0)

        let tree = LottieRenderIRLowerer().lower(frame)

        #expect(tree.report.isClean)
        let node = try #require(frame.nodes.first)
        let layer = try #require(tree.root.sublayers.first { $0.name == node.id.description })
        let opacityLayer = try #require(layer.sublayers.first)
        #expect(abs(opacityLayer.opacity - 0.5) < 0.0001)
        let shapeLayer = try #require(allShapeLayers(in: opacityLayer).first)
        #expect(shapeLayer.fillRule.rawValue == "evenOdd")
    }

    @Test("multiple masks report every mask source path")
    func multipleMasksReportEveryMaskSourcePath() throws {
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
            "ks": {},
            "masksProperties": [
              {
                "nm": "Mask A",
                "mode": "a",
                "inv": false,
                "pt": { "a": 0, "k": { "c": true, "v": [[0, 0], [10, 0], [10, 10]], "i": [[0, 0], [0, 0], [0, 0]], "o": [[0, 0], [0, 0], [0, 0]] } }
              },
              {
                "nm": "Mask B",
                "mode": "a",
                "inv": false,
                "pt": { "a": 0, "k": { "c": true, "v": [[20, 0], [30, 0], [30, 10]], "i": [[0, 0], [0, 0], [0, 0]], "o": [[0, 0], [0, 0], [0, 0]] } }
              }
            ],
            "shapes": [
              { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "Fill", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 } }
            ]
          }],
          "assets": []
        }
        """, at: 0)

        let tree = LottieRenderIRLowerer().lower(frame)
        let maskFindings = tree.report.findings.filter { $0.feature == "multiple masks" }

        #expect(maskFindings.count == 2)
        #expect(maskFindings.contains { $0.path == "root > layer 'Shapes' > mask 'Mask A'" })
        #expect(maskFindings.contains { $0.path == "root > layer 'Shapes' > mask 'Mask B'" })
        #expect(maskFindings.allSatisfy { $0.evidence?.layerGraphRecord?.maskCount == 2 })
    }

    @Test("render path reports shape-property expressions, descending into groups")
    func renderPathReportsShapeExpressions() throws {
        // A grouped shape whose path and fill colour are expression-driven. The
        // render path evaluates base values, so without descending into the group
        // these would render statically with no finding.
        let frame = try renderFrame(from: """
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
            "ks": { "o": { "a": 0, "k": 100 } },
            "shapes": [{
              "ty": "gr",
              "nm": "Group",
              "it": [
                { "ty": "sh", "nm": "Path", "ks": { "a": 0, "k": { "i": [[0, 0]], "o": [[0, 0]], "v": [[0, 0]], "c": true }, "x": "var $bm_rt;\\n$bm_rt = value;" } },
                { "ty": "fl", "nm": "Fill", "c": { "a": 0, "k": [1, 0, 0, 1], "x": "var $bm_rt;\\n$bm_rt = value;" }, "o": { "a": 0, "k": 100 } }
              ]
            }]
          }],
          "assets": []
        }
        """, at: 0)

        let tree = LottieRenderIRLowerer().lower(frame)
        let features = Set(tree.report.findings.map(\.feature))
        #expect(features.contains("shape path expression"))
        #expect(features.contains("fill color expression"))
        #expect(tree.report.findings.filter { $0.feature.hasSuffix("expression") }.allSatisfy { $0.disposition == .skipped })
    }

    @Test("real starfish corpus fixture reports its position expressions on the render path")
    func starfishCorpusFixtureReportsPositionExpressions() throws {
        // starfish drives its layers with AfterEffects position expressions
        // (`ks.p.x`). It bypasses the importer-scene validation gate (it carries
        // effects), so the render path is the only place its expression gap can be
        // declared. Before this guard it rendered statically with zero render-path
        // findings.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/LottieCorpus/airbnb-lottie-web/test/animations/starfish.json")
        let animation = try LottieAnimation.decode(from: Data(contentsOf: url))
        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 0)

        let tree = LottieRenderIRLowerer().lower(frame)

        let positionExpressions = tree.report.findings.filter { $0.feature == "position expression" }
        #expect(!positionExpressions.isEmpty)
        #expect(positionExpressions.allSatisfy { $0.disposition == .skipped })
    }

    @Test("real worm corpus fixture reports its shape-path expressions inside a precomp")
    func wormCorpusFixtureReportsShapeExpressions() throws {
        // worm drives shape paths (`sh.ks.x`) with expressions, nested inside a
        // precomposition asset. The render path must descend through the precomp
        // and into shape groups to declare the gap.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/LottieCorpus/Samsung-rlottie/example/resource/worm.json")
        let animation = try LottieAnimation.decode(from: Data(contentsOf: url))
        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 0)

        let tree = LottieRenderIRLowerer().lower(frame)

        let shapeExpressions = tree.report.findings.filter { $0.feature == "shape path expression" }
        #expect(!shapeExpressions.isEmpty)
        #expect(shapeExpressions.allSatisfy { $0.disposition == .skipped })
    }

    private func renderFrame(from source: String, at frame: Double) throws -> LottieRenderFrame {
        let animation = try LottieAnimation.decode(from: Data(source.utf8))
        return LottieRenderIRBuilder(animation: animation).frame(at: frame)
    }

    private func renderFrame(fixture name: String, at frame: Double) throws -> LottieRenderFrame {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/LottieOracle", isDirectory: true)
            .appendingPathComponent(name)
        let animation = try LottieAnimation.decode(from: Data(contentsOf: url))
        return LottieRenderIRBuilder(animation: animation).frame(at: frame)
    }

    private func assertFinding(
        _ findings: [ImportReport.Finding],
        _ feature: String,
        path: String,
        owner: LottieBackendGapEvidence.Owner
    ) throws {
        let finding = try #require(findings.first { $0.feature == feature && $0.path == path })
        let evidence = try #require(finding.evidence)
        #expect(evidence.owner == owner)
        switch owner {
        case .backendCapability, .pureLottieSemantics:
            #expect(finding.disposition == .skipped)
        case .intentionalApproximation:
            #expect(finding.disposition == .approximated)
        }
        #expect(evidence.sourceFrame == 0)
        #expect(evidence.frameRate == 10)
        #expect(evidence.lottiePath == path)
        let jsonPath = try #require(evidence.jsonPath)
        #expect(!jsonPath.isEmpty)
        #expect(evidence.vmTrace != nil)
        #expect(evidence.renderNode != nil)
        #expect(evidence.renderTerm != nil)
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

    private func path(from mask: LottieRenderMask) throws -> Path {
        let bezier = try #require(mask.path)
        var path = Path()
        PathBuilder.path(from: bezier, into: &path)
        return path
    }

    private func firstShapeBounds(in node: LottieRenderNode) throws -> Rect {
        guard case let .shape(shape) = node.kind else {
            Issue.record("Expected shape node for \(node.layerName).")
            return Rect(x: 0, y: 0, width: 0, height: 0)
        }
        let draw = try #require(shape.draws.first)
        let fragment = try #require(draw.fragments.first)
        let path = try #require(pureDrawPath(for: fragment))
        return path.boundingBox
    }

    private func pureDrawPath(for fragment: LottieRenderGeometryFragment) -> Path? {
        var path = Path()
        PathBuilder.path(from: fragment.sourceGeometry.bezier, into: &path)
        guard !path.isEmpty else { return nil }
        return path.applying(affine(for: fragment.transformStack))
    }

    private func affine(for transformStack: [LottieRenderShapeTransform]) -> PureLayer.AffineTransform {
        transformStack.reduce(PureLayer.AffineTransform.identity) { result, transform in
            result.concatenating(affine(for: transform))
        }
    }

    private func affine(for transform: LottieRenderShapeTransform) -> PureLayer.AffineTransform {
        let anchor = PureLayer.AffineTransform.translation(
            x: -transform.anchor.scalar(0),
            y: -transform.anchor.scalar(1)
        )
        let scale = PureLayer.AffineTransform.scale(
            x: transform.scale.scalar(0, default: 100) / 100,
            y: transform.scale.scalar(1, default: 100) / 100
        )
        let rotation = PureLayer.AffineTransform.rotation(angle: transform.rotationDegrees * .pi / 180)
        let position = PureLayer.AffineTransform.translation(
            x: transform.position.scalar(0),
            y: transform.position.scalar(1)
        )
        return anchor.concatenating(scale).concatenating(rotation).concatenating(position)
    }

    private func assertBounds(_ actual: Rect, matches expected: Rect) {
        #expect(abs(actual.minX - expected.minX) < 0.0001)
        #expect(abs(actual.minY - expected.minY) < 0.0001)
        #expect(abs(actual.maxX - expected.maxX) < 0.0001)
        #expect(abs(actual.maxY - expected.maxY) < 0.0001)
    }
}

private extension [Double] {
    func scalar(_ index: Int, default defaultValue: Double = 0) -> Double {
        if indices.contains(index) { return self[index] }
        return last ?? defaultValue
    }
}
