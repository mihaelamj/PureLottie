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
                  "o": { "a": 0, "k": 0 },
                  "m": 2
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

        #expect(findings.contains {
            $0.feature == "track matte mode 2 using root > layer 'MatteSource'"
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
        #expect(findings.contains {
            $0.feature == "individual trim (trimmed as one length)"
                && $0.path == "root > layer 'Shapes' > trim 'Individual Trim'"
        })

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
        #expect(strokeEvidence.renderNode?.nodeID == "render#1")
        #expect(strokeEvidence.renderNode?.kind == "shape")
        #expect(strokeEvidence.renderNode?.sourcePath == "root > layer 'Shapes'")
        #expect(strokeEvidence.vmTrace?.instruction == LottieVMInstruction.Kind.emitRenderNode.rawValue)
        #expect(strokeEvidence.renderTerm?.kind == "strokeStyle")
        #expect(strokeEvidence.renderTerm?.values["blendMode"] == "2")
        #expect(strokeEvidence.renderTerm?.values["dashCount"] == "1")

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
