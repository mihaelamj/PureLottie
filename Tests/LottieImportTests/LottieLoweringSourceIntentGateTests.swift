import Foundation
import LottieEvaluation
@testable import LottieImport
import LottieModel
import PureLayer
import Testing

@Suite("Lottie lowering source-intent gate")
struct LottieLoweringSourceIntentGateTests {
    @Test("curated corpus lowers PureLayer state only from measured source intent")
    func curatedCorpusLowersPureLayerStateOnlyFromMeasuredSourceIntent() throws {
        var matchedLayerCount = 0
        var matchedShapeCount = 0
        var evidenceFindingCount = 0
        var trimTraceCount = 0
        let tolerances = try loadTolerances()
        let manifest = try loadManifest()
        var reportFixtures: [CorpusLoweringGateReport.Fixture] = []

        for entry in manifest {
            let animation = try LottieAnimation.decode(from: Data(contentsOf: url(fromOracleRootPath: entry.lottie)))
            let intent = try LottieWebIntentTrace.decodeValidated(
                from: Data(contentsOf: url(fromOracleRootPath: entry.lottieWebIntent))
            )
            #expect(intent.frames.map(\.frame) == entry.frames.map(\.frame))
            let selectedFrameRationales = Dictionary(uniqueKeysWithValues: entry.frames.map { ($0.frame, $0.rationale) })
            let builder = LottieRenderIRBuilder(animation: animation)
            var reportFrames: [CorpusLoweringGateReport.Frame] = []

            for webFrame in intent.frames {
                let frameRationale = try #require(selectedFrameRationales[webFrame.frame])
                #expect(!frameRationale.isEmpty, "\(entry.id) frame \(webFrame.frame) has no selection rationale")
                let renderFrame = builder.frame(at: webFrame.frame)
                assertMeasuredSourceIntent(renderFrame, entry: entry)
                try assertReferenceFeatureFacts(
                    webFrame: webFrame,
                    frame: renderFrame,
                    entry: entry,
                    tolerances: tolerances
                )
                trimTraceCount += renderFrame.trimTraceCount

                let tree = LottieRenderIRLowerer().lower(
                    renderFrame,
                    evidenceContext: LottieBackendEvidenceContext(
                        sourceFixture: entry.lottie,
                        expectedLottieWebFrameArtifact: entry.lottieWebIntent,
                        pureLayerFrameArtifact: "unrendered/source-intent-frame-\(webFrame.frame).png"
                    )
                )

                evidenceFindingCount += assertStructuredEvidence(
                    tree.report.findings,
                    entry: entry,
                    frame: renderFrame
                )

                let comparison = try compareLoweredState(
                    tree: tree,
                    frame: renderFrame,
                    webFrame: webFrame,
                    entry: entry,
                    tolerances: tolerances
                )
                matchedLayerCount += comparison.layers
                matchedShapeCount += comparison.shapes
                if entry.semanticStatus == .diagnosed {
                    #expect(
                        !renderFrame.diagnostics.isEmpty || !tree.report.findings.isEmpty,
                        "\(entry.id) frame \(webFrame.frame) is diagnosed but has no diagnostics or backend findings"
                    )
                }
                reportFrames.append(.init(
                    frame: webFrame.frame,
                    rationale: frameRationale,
                    renderNodeCount: renderFrame.nodes.count,
                    shapeDrawCount: renderFrame.shapeDrawCount,
                    matchedLayerCount: comparison.layers,
                    matchedShapeCount: comparison.shapes,
                    diagnosticCount: renderFrame.diagnostics.count,
                    backendFindingCount: tree.report.findings.count,
                    trimTraceCount: renderFrame.trimTraceCount,
                    diagnostics: renderFrame.diagnostics.map(CorpusLoweringGateReport.Diagnostic.init(diagnostic:)).sorted(),
                    backendFindings: tree.report.findings.map(CorpusLoweringGateReport.BackendFinding.init(finding:)).sorted()
                ))
            }

            reportFixtures.append(.init(
                id: entry.id,
                semanticStatus: entry.semanticStatus.rawValue,
                lottie: entry.lottie,
                lottieWebIntent: entry.lottieWebIntent,
                coverage: entry.coverage.sorted(),
                selectedFrameCount: reportFrames.count,
                excluded: false,
                frames: reportFrames
            ))
        }

        let report = CorpusLoweringGateReport(fixtures: reportFixtures)
        try assertLoweringGateReport(
            report,
            manifestCount: manifest.count,
            selectedFrameCount: manifest.flatMap(\.frames).count
        )
        #expect(matchedLayerCount > 30)
        #expect(matchedShapeCount > 30)
        #expect(evidenceFindingCount > 0)
        #expect(trimTraceCount > 0)
        #expect(report.matchedLayerCount == matchedLayerCount)
        #expect(report.matchedShapeCount == matchedShapeCount)
        #expect(report.backendFindingCount == evidenceFindingCount)
        #expect(report.trimTraceCount == trimTraceCount)
    }

    @Test("trim source intent is measurable before PureLayer stroke fractions are asserted")
    func trimSourceIntentIsMeasurableBeforePureLayerStrokeFractionsAreAsserted() throws {
        let trimSegmentTolerance = try loadTolerances().threshold(id: "trim.segment.unit-interval.absolute")
        let animation = try LottieAnimation.decode(from: Data(contentsOf: fixture("trim-ellipse-quadrant.json")))
        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 5)
        let node = try #require(frame.nodes.first)

        guard case let .shape(shape) = node.kind else {
            Issue.record("Expected trim fixture to emit a shape node.")
            return
        }

        let draw = try #require(shape.draws.first)
        let trace = try #require(draw.trimTraces.first)

        #expect(trace.sourceFrame == 5)
        #expect(trace.authoredMultiple == 1)
        expectClose(trace.normalization.normalizedStartFraction, 0, tolerance: trimSegmentTolerance)
        expectClose(trace.normalization.normalizedEndFraction, 0.25, tolerance: trimSegmentTolerance)
        #expect(trace.inputPaths.isEmpty == false)
        #expect(trace.totalLength > 0)
        #expect(trace.selectedSegments.isEmpty == false)
        #expect(trace.resultPaths.isEmpty == false)

        let tree = LottieRenderIRLowerer().lower(frame)
        #expect(tree.report.findings.allSatisfy { $0.evidence != nil })
        let layer = try #require(tree.root.sublayers.first { $0.name == node.id.description })
        let shapeLayer = try #require(allShapeLayers(in: layer).first)

        expectClose(shapeLayer.strokeStart, trace.normalization.normalizedStartFraction, tolerance: trimSegmentTolerance)
        expectClose(shapeLayer.strokeEnd, trace.normalization.normalizedEndFraction, tolerance: trimSegmentTolerance)
    }

    private func assertReferenceFeatureFacts(
        webFrame: LottieWebIntentTrace.Frame,
        frame: LottieRenderFrame,
        entry: CorpusFixtureManifestEntry,
        tolerances: LottieOracleToleranceLedger
    ) throws {
        let coverage = Set(entry.coverage)
        if coverage.contains("mask") {
            try assertMaskReferenceFacts(webFrame: webFrame, frame: frame, tolerances: tolerances)
        }
        if coverage.contains("matte") {
            try assertMatteReferenceFacts(webFrame: webFrame, frame: frame)
        }
        if coverage.contains("precomp") {
            try assertPrecompositionReferenceFacts(webFrame: webFrame, frame: frame)
        }
        if coverage.contains("trim") {
            try assertTrimReferenceFacts(webFrame: webFrame, frame: frame, tolerances: tolerances)
        }
    }

    private func assertMaskReferenceFacts(
        webFrame: LottieWebIntentTrace.Frame,
        frame: LottieRenderFrame,
        tolerances: LottieOracleToleranceLedger
    ) throws {
        let opacityTolerance = try tolerances.threshold(id: "opacity.unit-interval.absolute")

        for webMask in webFrame.masks {
            let node = try #require(frame.nodes.first { $0.layerIndex == webMask.layerInd })
            let mask = try #require(node.masks.first { $0.name == webMask.name && $0.mode == webMask.mode })
            let path = try #require(mask.path)

            #expect(mask.isInverted == webMask.inverted)
            #expect(path.isClosed == webMask.closed)
            #expect(path.vertices.count == webMask.vertexCount)
            #expect(webMask.pathD?.isEmpty == false)
            expectClose(mask.opacity, webMask.opacity, tolerance: opacityTolerance, label: "mask opacity")
        }
    }

    private func assertMatteReferenceFacts(webFrame: LottieWebIntentTrace.Frame, frame: LottieRenderFrame) throws {
        for webMatte in webFrame.mattes {
            let target = try #require(frame.nodes.first { $0.layerIndex == webMatte.targetLayerInd })
            let matte = try #require(target.matte)

            #expect(matte.mode == webMatte.mode)
            #expect(matte.sourceLayerIndex == webMatte.sourceLayerInd)
            #expect(matte.isExplicitSource == (webMatte.explicitSourceLayerIndex != nil))
            if let sourceLayerName = webMatte.sourceLayerName {
                #expect(matte.sourcePath?.contains(sourceLayerName) == true)
            }
            if let sourceLayerInd = webMatte.sourceLayerInd {
                let source = try #require(frame.nodes.first { $0.layerIndex == sourceLayerInd })
                #expect((source.matteSourceMarker != nil) == webMatte.sourceIsMarker)
            }
        }
    }

    private func assertPrecompositionReferenceFacts(
        webFrame: LottieWebIntentTrace.Frame,
        frame: LottieRenderFrame
    ) throws {
        for webPrecomposition in webFrame.precompositions {
            let boundary = try #require(frame.nodes.first { node in
                guard node.layerIndex == webPrecomposition.layerInd else { return false }
                if case .precompositionBoundary = node.kind { return true }
                return false
            })
            guard case let .precompositionBoundary(precomposition) = boundary.kind else {
                Issue.record("Expected precomposition boundary for \(webPrecomposition.layerName).")
                return
            }

            #expect(precomposition.assetID == webPrecomposition.refId)
            #expect(webPrecomposition.childLayerCount >= 0)
            #expect(webPrecomposition.builtChildElementCount >= 0)
            let renderedFrame = try #require(webPrecomposition.renderedFrame)
            expectClose(
                renderedFrame,
                boundary.localFrame,
                label: "precomposition renderedFrame"
            )
        }
    }

    private func assertTrimReferenceFacts(
        webFrame: LottieWebIntentTrace.Frame,
        frame: LottieRenderFrame,
        tolerances: LottieOracleToleranceLedger
    ) throws {
        let trimTolerance = try tolerances.threshold(id: "trim.segment.unit-interval.absolute")

        for webTrim in webFrame.trims {
            let trimTrace = try #require(frame.trimTraces.first { $0.sourcePath.contains(webTrim.layerName) })

            #expect(trimTrace.authoredMultiple == webTrim.mode)
            expectClose(
                webTrim.startFraction,
                trimTrace.normalization.normalizedStartFraction,
                tolerance: trimTolerance,
                label: "trim startFraction"
            )
            expectClose(
                webTrim.endFraction,
                trimTrace.normalization.normalizedEndFraction,
                tolerance: trimTolerance,
                label: "trim endFraction"
            )
            expectClose(
                webTrim.offsetTurns,
                trimTrace.normalization.offsetTurns,
                tolerance: trimTolerance,
                label: "trim offsetTurns"
            )
            #expect(webTrim.shapeCount == trimTrace.inputPaths.count)
            #expect(webFrame.diagnostics.contains { diagnostic in
                diagnostic.feature == "trim.selectedSegments" && diagnostic.layerInd == webTrim.layerInd
            })
        }
    }

    private func assertMeasuredSourceIntent(_ frame: LottieRenderFrame, entry: CorpusFixtureManifestEntry) {
        #expect(frame.width > 0, "\(entry.id) has non-positive width")
        #expect(frame.height > 0, "\(entry.id) has non-positive height")
        #expect(frame.frameRate > 0, "\(entry.id) has non-positive frame rate")
        #expect(frame.nodes.isEmpty == false, "\(entry.id) frame \(frame.sourceFrame) has no RenderIR nodes")

        if entry.semanticStatus == .modeled {
            #expect(frame.diagnostics.isEmpty, "\(entry.id) frame \(frame.sourceFrame) emitted diagnostics")
        }

        for node in frame.nodes {
            #expect(node.source.sourcePath.isEmpty == false)
            #expect(node.source.jsonPath.description.isEmpty == false)
            #expect(node.localFrame.isFinite)
            #expect(node.opacity.isFinite)
            #expect(node.transform.worldMatrix.values.count == 16)
            let matrixValuesAreFinite = node.transform.worldMatrix.values.allSatisfy { value in
                value.isFinite
            }
            #expect(matrixValuesAreFinite)

            for mask in node.masks {
                #expect(mask.source.sourcePath.isEmpty == false)
                #expect(mask.source.jsonPath.description.isEmpty == false)
                #expect(mask.opacity.isFinite)
                if mask.mode == "a" {
                    #expect(mask.path != nil)
                }
            }

            if case let .shape(shape) = node.kind {
                #expect(shape.draws.isEmpty == false)
                for draw in shape.draws {
                    #expect(draw.source.sourcePath.isEmpty == false)
                    #expect(draw.fragments.isEmpty == false)
                    assertMeasuredShapeFragments(draw.fragments)
                    assertMeasuredTrimTraces(draw.trimTraces)
                }
            }
        }
    }

    private func assertMeasuredShapeFragments(_ fragments: [LottieRenderGeometryFragment]) {
        for fragment in fragments {
            #expect(fragment.source.sourcePath.isEmpty == false)
            #expect(fragment.source.jsonPath.description.isEmpty == false)
            #expect(fragment.sourceGeometry.bezier.vertices.isEmpty == false)
            #expect(fragment.sourceGeometry.bounds.minX.isFinite)
            #expect(fragment.sourceGeometry.bounds.minY.isFinite)
            #expect(fragment.sourceGeometry.bounds.maxX.isFinite)
            #expect(fragment.sourceGeometry.bounds.maxY.isFinite)
            assertPureDrawPathPreservesMeasuredBounds(fragment)
        }
    }

    private func assertPureDrawPathPreservesMeasuredBounds(_ fragment: LottieRenderGeometryFragment) {
        var path = Path()
        PathBuilder.path(from: fragment.sourceGeometry.bezier, into: &path)
        guard !path.isEmpty else {
            Issue.record("Measured source geometry did not produce a PureDraw path.")
            return
        }

        let actualBounds = path.boundingBox
        let expectedBounds = fragment.sourceGeometry.bounds
        expectClose(actualBounds.minX, expectedBounds.minX)
        expectClose(actualBounds.minY, expectedBounds.minY)
        expectClose(actualBounds.maxX, expectedBounds.maxX)
        expectClose(actualBounds.maxY, expectedBounds.maxY)
    }

    private func assertMeasuredTrimTraces(_ traces: [LottieSourceTrimTrace]) {
        for trace in traces {
            #expect(trace.sourcePath.isEmpty == false)
            #expect(trace.jsonPath.isEmpty == false)
            #expect(trace.sourceFrame.isFinite)
            #expect(trace.inputPaths.isEmpty == false)
            #expect(trace.totalLength.isFinite)
            #expect(trace.totalLength > 0)
            if !trace.normalization.isEmpty {
                #expect(trace.selectedSegments.isEmpty == false)
                #expect(trace.resultPaths.isEmpty == false)
            }
        }
    }

    private func assertStructuredEvidence(
        _ findings: [ImportReport.Finding],
        entry: CorpusFixtureManifestEntry,
        frame: LottieRenderFrame
    ) -> Int {
        for finding in findings {
            let evidence = finding.evidence
            #expect(evidence != nil, "\(entry.id) finding '\(finding.feature)' is missing lowering evidence")
            guard let evidence else { continue }

            #expect(evidence.sourceFixture == entry.lottie)
            expectClose(evidence.sourceFrame, frame.sourceFrame)
            expectClose(evidence.frameRate, frame.frameRate)
            #expect(evidence.lottiePath.isEmpty == false)
            #expect(evidence.jsonPath?.isEmpty == false)
            #expect(evidence.expectedLottieWebFrameArtifact == entry.lottieWebIntent)
            #expect(evidence.pureLayerFrameArtifact?.contains("source-intent-frame") == true)
            #expect(evidence.renderNode != nil || evidence.renderTerm != nil)
            if let term = evidence.renderTerm {
                #expect(term.kind.isEmpty == false)
                #expect(term.sourcePath.isEmpty == false)
                #expect(term.jsonPath.isEmpty == false)
                #expect(term.values.isEmpty == false)
            }
        }
        return findings.count
    }

    private func compareLoweredState(
        tree: LottieRenderLayerTree,
        frame: LottieRenderFrame,
        webFrame: LottieWebIntentTrace.Frame,
        entry: CorpusFixtureManifestEntry,
        tolerances: LottieOracleToleranceLedger
    ) throws -> (layers: Int, shapes: Int) {
        var matchedLayers = 0
        var matchedShapes = 0

        for node in frame.nodes {
            guard let layer = tree.root.sublayers.first(where: { $0.name == node.id.description }) else {
                continue
            }

            matchedLayers += 1
            expectClose(layer.opacity, node.opacity)
            assertTransform(layer.transform, matches: node.transform.worldMatrix.values, entry: entry, node: node)
            try assertDirectLottieWebTranslation(webFrame: webFrame, node: node, entry: entry, tolerances: tolerances)
            assertMaskState(layer: layer, node: node)

            if case let .shape(shape) = node.kind {
                let expected = expectedShapeSnapshots(for: shape)
                let actual = allShapeLayers(in: layer).map(ShapeLayerSnapshot.init(layer:))
                #expect(
                    actual.count == expected.count,
                    "\(entry.id) frame \(frame.sourceFrame) shape layer count differs from RenderIR draw runs"
                )
                for pair in zip(actual, expected) {
                    assertShape(pair.0, matches: pair.1, entry: entry, frame: frame)
                    matchedShapes += 1
                }
            }
        }

        return (matchedLayers, matchedShapes)
    }

    private func assertDirectLottieWebTranslation(
        webFrame: LottieWebIntentTrace.Frame,
        node: LottieRenderNode,
        entry: CorpusFixtureManifestEntry,
        tolerances: LottieOracleToleranceLedger
    ) throws {
        guard entry.hasDirectTranslationComparison else { return }
        guard let webLayer = webFrame.layers.first(where: { $0.name == node.layerName }) else { return }
        guard webLayer.matrix.indices.contains(13) else { return }

        let translationTolerance = try tolerances.threshold(id: "matrix.translation.css-pixel.absolute")
        expectClose(webLayer.matrix[12], node.transform.worldMatrix.values[12], tolerance: translationTolerance)
        expectClose(webLayer.matrix[13], node.transform.worldMatrix.values[13], tolerance: translationTolerance)
    }

    private func assertTransform(
        _ transform: Transform3D,
        matches expected: [Double],
        entry: CorpusFixtureManifestEntry,
        node: LottieRenderNode
    ) {
        let actual = [
            transform.m11, transform.m12, transform.m13, transform.m14,
            transform.m21, transform.m22, transform.m23, transform.m24,
            transform.m31, transform.m32, transform.m33, transform.m34,
            transform.m41, transform.m42, transform.m43, transform.m44,
        ]
        #expect(actual.count == expected.count)
        for (index, pair) in zip(actual, expected).enumerated() {
            #expect(
                abs(pair.0 - pair.1) <= 0.000_001,
                "\(entry.id) \(node.layerName) matrix[\(index)] lowered \(pair.0), expected \(pair.1)"
            )
        }
    }

    private func assertMaskState(layer: Layer, node: LottieRenderNode) {
        let additiveMasks = node.masks.filter { $0.mode == "a" && !$0.isInverted && $0.path != nil }
        guard !additiveMasks.isEmpty else { return }
        #expect(additiveMasks.count == 1)
        let expectedMask = additiveMasks[0]
        let maskLayer = layer.mask as? ShapeLayer
        #expect(maskLayer != nil)

        guard let bezier = expectedMask.path, let actualBounds = maskLayer?.path?.boundingBox else {
            return
        }
        var expectedPath = Path()
        PathBuilder.path(from: bezier, into: &expectedPath)
        let expectedBounds = expectedPath.boundingBox
        expectClose(actualBounds.minX, expectedBounds.minX)
        expectClose(actualBounds.minY, expectedBounds.minY)
        expectClose(actualBounds.maxX, expectedBounds.maxX)
        expectClose(actualBounds.maxY, expectedBounds.maxY)
    }

    private func assertShape(
        _ actual: ShapeLayerSnapshot,
        matches expected: ShapeLayerSnapshot,
        entry _: CorpusFixtureManifestEntry,
        frame _: LottieRenderFrame
    ) {
        guard let actualBounds = actual.bounds, let expectedBounds = expected.bounds else {
            #expect(actual.bounds == nil && expected.bounds == nil)
            return
        }
        expectClose(actualBounds.minX, expectedBounds.minX)
        expectClose(actualBounds.minY, expectedBounds.minY)
        expectClose(actualBounds.maxX, expectedBounds.maxX)
        expectClose(actualBounds.maxY, expectedBounds.maxY)
        expectClose(actual.lineWidth, expected.lineWidth)
        expectClose(actual.strokeStart, expected.strokeStart)
        expectClose(actual.strokeEnd, expected.strokeEnd)
        #expect(actual.fillRule == expected.fillRule)
        assertColor(actual.fillColor, matches: expected.fillColor)
        assertColor(actual.strokeColor, matches: expected.strokeColor)
    }

    private func expectedShapeSnapshots(for shape: LottieRenderShape) -> [ShapeLayerSnapshot] {
        shape.nodes.flatMap(expectedShapeSnapshots(for:))
    }

    private func expectedShapeSnapshots(for node: LottieRenderShapeNode) -> [ShapeLayerSnapshot] {
        switch node {
        case let .draw(draw):
            pathRuns(for: draw).map { run in
                ShapeLayerSnapshot(path: run.path, trim: run.trim, style: draw.style)
            }
        case let .transparencyGroup(group):
            group.nodes.flatMap(expectedShapeSnapshots(for:))
        }
    }

    private struct PathRun {
        var path: Path
        var trim: LottieRenderTrim?
    }

    private func pathRuns(for draw: LottieRenderShapeDraw) -> [PathRun] {
        var runs: [PathRun] = []
        for fragment in draw.fragments {
            guard let path = path(for: fragment), !path.isEmpty else { continue }
            let trim = trim(in: fragment.modifiers)
            if let last = runs.last, last.trim == trim {
                var merged = last.path
                merged.addPath(path)
                runs[runs.count - 1] = PathRun(path: merged, trim: trim)
            } else {
                runs.append(PathRun(path: path, trim: trim))
            }
        }
        return runs
    }

    private func path(for fragment: LottieRenderGeometryFragment) -> Path? {
        var path = Path()
        PathBuilder.path(from: fragment.sourceGeometry.bezier, into: &path)
        guard !path.isEmpty else { return nil }
        return path.applying(affine(for: fragment.transformStack))
    }

    private func trim(in modifiers: [LottieRenderShapeModifier]) -> LottieRenderTrim? {
        modifiers.compactMap { modifier in
            if case let .trim(trim) = modifier {
                return trim
            }
            return nil
        }.last
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

    private func assertColor(_ actual: ColorSnapshot?, matches expected: ColorSnapshot?) {
        switch (actual, expected) {
        case (nil, nil):
            return
        case let (actual?, expected?):
            expectClose(actual.red, expected.red)
            expectClose(actual.green, expected.green)
            expectClose(actual.blue, expected.blue)
            expectClose(actual.alpha, expected.alpha)
        default:
            Issue.record("Color mismatch: actual \(String(describing: actual)), expected \(String(describing: expected)).")
        }
    }

    private func loadManifest() throws -> [CorpusFixtureManifestEntry] {
        try JSONDecoder().decode(
            [CorpusFixtureManifestEntry].self,
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/oracle-fixtures.json"))
        )
    }

    private func loadTolerances() throws -> LottieOracleToleranceLedger {
        try LottieOracleToleranceLedger.decodeValidated(
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/oracle-tolerances.json"))
        )
    }

    private func assertLoweringGateReport(
        _ report: CorpusLoweringGateReport,
        manifestCount: Int,
        selectedFrameCount: Int
    ) throws {
        #expect(report.schema.name == "purelottie.renderir-purelayer-lowering-gate")
        #expect(report.schema.version == 1)
        #expect(report.fixtureCount == manifestCount)
        #expect(report.fixtureCount >= 31)
        #expect(report.selectedFrameCount == selectedFrameCount)
        #expect(report.excludedFixtureCount == 0)
        #expect(report.excludedFixtures.isEmpty)
        #expect(report.fixtures.allSatisfy { !$0.frames.isEmpty })
        #expect(report.fixtures.allSatisfy { fixture in
            fixture.frames.allSatisfy { !$0.rationale.isEmpty }
        })

        let encoded = try encoded(report)
        let snapshotURL = repositoryRoot()
            .appendingPathComponent("Tests/Fixtures/LottieOracle/lowering-gate/report.json")
        if ProcessInfo.processInfo.environment["PURELOTTIE_UPDATE_LOWERING_GATE_REPORT"] == "1" {
            try encoded.write(to: snapshotURL, options: .atomic)
            return
        }

        let expected = try Data(contentsOf: snapshotURL)
        #expect(
            String(data: encoded, encoding: .utf8) == String(data: expected, encoding: .utf8),
            "Regenerate with PURELOTTIE_UPDATE_LOWERING_GATE_REPORT=1 swift test --filter LottieLoweringSourceIntentGateTests"
        )
    }

    private func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func url(fromOracleRootPath path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: repositoryRoot().appendingPathComponent("Tools/LottieOracle", isDirectory: true))
            .standardizedFileURL
    }

    private func fixture(_ name: String) -> URL {
        repositoryRoot()
            .appendingPathComponent("Tests/Fixtures/LottieOracle", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func expectClose(
        _ actual: Double,
        _ expected: Double,
        tolerance: Double = 0.000_001,
        label: String = ""
    ) {
        #expect(abs(actual - expected) <= tolerance, "\(label): actual \(actual), expected \(expected)")
    }
}

private struct ShapeLayerSnapshot {
    var bounds: Rect?
    var fillColor: ColorSnapshot?
    var fillRule: String
    var strokeColor: ColorSnapshot?
    var lineWidth: Double
    var strokeStart: Double
    var strokeEnd: Double

    init(layer: ShapeLayer) {
        bounds = layer.path?.boundingBox
        fillColor = layer.fillColor.map(ColorSnapshot.init(color:))
        fillRule = layer.fillRule.rawValue
        strokeColor = layer.strokeColor.map(ColorSnapshot.init(color:))
        lineWidth = layer.lineWidth
        strokeStart = layer.strokeStart
        strokeEnd = layer.strokeEnd
    }

    init(path: Path, trim: LottieRenderTrim?, style: LottieRenderShapeStyle) {
        bounds = path.boundingBox
        fillRule = "winding"
        strokeColor = nil
        lineWidth = 1
        strokeStart = 0
        strokeEnd = 1

        switch style {
        case let .fill(fill):
            fillColor = ColorSnapshot(components: fill.color, opacity: fill.opacity)
            fillRule = fill.fillRule == 2 ? "evenOdd" : "winding"
        case let .stroke(stroke):
            fillColor = nil
            strokeColor = ColorSnapshot(components: stroke.color, opacity: stroke.opacity)
            lineWidth = stroke.width
            if let trim {
                strokeStart = Self.fraction(trim.start)
                strokeEnd = Self.fraction(trim.end)
            }
        }
    }

    private static func fraction(_ percent: Double) -> Double {
        min(max(percent / 100, 0), 1)
    }
}

private struct ColorSnapshot: CustomStringConvertible {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(color: Color) {
        red = color.red
        green = color.green
        blue = color.blue
        alpha = color.alpha
    }

    init(components: [Double], opacity: Double) {
        red = components.scalar(0)
        green = components.scalar(1)
        blue = components.scalar(2)
        alpha = (components.count > 3 ? components[3] : 1) * opacity
    }

    var description: String {
        "rgba(\(red), \(green), \(blue), \(alpha))"
    }
}

private struct CorpusLoweringGateReport: Codable, Equatable {
    var schema = Schema()
    var fixtureCount: Int
    var selectedFrameCount: Int
    var excludedFixtureCount: Int
    var matchedLayerCount: Int
    var matchedShapeCount: Int
    var shapeDrawCount: Int
    var diagnosticCount: Int
    var backendFindingCount: Int
    var trimTraceCount: Int
    var excludedFixtures: [Exclusion]
    var fixtures: [Fixture]

    init(fixtures: [Fixture], excludedFixtures: [Exclusion] = []) {
        self.fixtures = fixtures.sorted { $0.id < $1.id }
        self.excludedFixtures = excludedFixtures.sorted()
        fixtureCount = self.fixtures.count
        selectedFrameCount = self.fixtures.flatMap(\.frames).count
        excludedFixtureCount = self.excludedFixtures.count
        matchedLayerCount = self.fixtures.flatMap(\.frames).map(\.matchedLayerCount).reduce(0, +)
        matchedShapeCount = self.fixtures.flatMap(\.frames).map(\.matchedShapeCount).reduce(0, +)
        shapeDrawCount = self.fixtures.flatMap(\.frames).map(\.shapeDrawCount).reduce(0, +)
        diagnosticCount = self.fixtures.flatMap(\.frames).map(\.diagnosticCount).reduce(0, +)
        backendFindingCount = self.fixtures.flatMap(\.frames).map(\.backendFindingCount).reduce(0, +)
        trimTraceCount = self.fixtures.flatMap(\.frames).map(\.trimTraceCount).reduce(0, +)
    }

    struct Schema: Codable, Equatable {
        var name = "purelottie.renderir-purelayer-lowering-gate"
        var version = 1
    }

    struct Exclusion: Codable, Equatable, Comparable {
        var id: String
        var lottie: String
        var reason: String

        static func < (lhs: Exclusion, rhs: Exclusion) -> Bool {
            (lhs.id, lhs.lottie, lhs.reason) < (rhs.id, rhs.lottie, rhs.reason)
        }
    }

    struct Fixture: Codable, Equatable {
        var id: String
        var semanticStatus: String
        var lottie: String
        var lottieWebIntent: String
        var coverage: [String]
        var selectedFrameCount: Int
        var excluded: Bool
        var frames: [Frame]
    }

    struct Frame: Codable, Equatable {
        var frame: Double
        var rationale: String
        var renderNodeCount: Int
        var shapeDrawCount: Int
        var matchedLayerCount: Int
        var matchedShapeCount: Int
        var diagnosticCount: Int
        var backendFindingCount: Int
        var trimTraceCount: Int
        var diagnostics: [Diagnostic]
        var backendFindings: [BackendFinding]
    }

    struct Diagnostic: Codable, Equatable, Comparable {
        var ruleID: String
        var severity: String
        var classification: String
        var phase: String
        var path: String
        var reason: String

        init(diagnostic: ValidationError) {
            ruleID = diagnostic.ruleID
            severity = diagnostic.severity.rawValue
            classification = diagnostic.classification.rawValue
            phase = diagnostic.phase.rawValue
            path = diagnostic.codingPath.description
            reason = diagnostic.reason
        }

        static func < (lhs: Diagnostic, rhs: Diagnostic) -> Bool {
            (lhs.path, lhs.ruleID, lhs.reason) < (rhs.path, rhs.ruleID, rhs.reason)
        }
    }

    struct BackendFinding: Codable, Equatable, Comparable {
        var feature: String
        var disposition: String
        var path: String
        var sourcePath: String
        var owner: String
        var evidenceJSONPath: String
        var renderTermKind: String
        var renderTermJSONPath: String

        init(finding: ImportReport.Finding) {
            feature = finding.feature
            disposition = finding.disposition.rawValue
            path = finding.path
            sourcePath = finding.sourcePath ?? ""
            owner = finding.evidence?.owner.rawValue ?? ""
            evidenceJSONPath = finding.evidence?.jsonPath ?? ""
            renderTermKind = finding.evidence?.renderTerm?.kind ?? ""
            renderTermJSONPath = finding.evidence?.renderTerm?.jsonPath ?? ""
        }

        static func < (lhs: BackendFinding, rhs: BackendFinding) -> Bool {
            (lhs.path, lhs.feature, lhs.sourcePath) < (rhs.path, rhs.feature, rhs.sourcePath)
        }
    }
}

private struct CorpusFixtureManifestEntry: Decodable {
    var id: String
    var coverage: [String]
    var semanticStatus: SemanticStatus
    var lottie: String
    var lottieWebIntent: String
    var frames: [Frame]

    struct Frame: Decodable {
        var frame: Double
        var rationale: String
    }

    enum SemanticStatus: String, Decodable {
        case modeled
        case diagnosed
    }

    var hasDirectTranslationComparison: Bool {
        let coverageSet = Set(coverage)
        guard coverageSet.contains("animated-position") || coverageSet.contains("split-position") else {
            return false
        }
        return coverageSet.isDisjoint(with: [
            "anchor",
            "rotation",
            "parent-transform",
            "precomp",
            "shape-transform",
            "time-remap",
        ])
    }
}

private extension LottieRenderFrame {
    var trimTraces: [LottieSourceTrimTrace] {
        nodes.flatMap { node -> [LottieSourceTrimTrace] in
            guard case let .shape(shape) = node.kind else { return [] }
            return shape.draws.flatMap(\.trimTraces)
        }
    }

    var trimTraceCount: Int {
        trimTraces.count
    }

    var shapeDrawCount: Int {
        nodes.reduce(0) { count, node in
            guard case let .shape(shape) = node.kind else { return count }
            return count + shape.draws.count
        }
    }
}

private extension [Double] {
    func scalar(_ index: Int, default defaultValue: Double = 0) -> Double {
        if indices.contains(index) { return self[index] }
        return last ?? defaultValue
    }
}
