import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("lottie-web intent trace validation")
struct LottieWebIntentTraceValidationTests {
    @Test("committed lottie-web intent traces decode through shared model")
    func committedLottieWebIntentTracesDecodeThroughSharedModel() throws {
        let intentDirectory = repositoryRoot()
            .appendingPathComponent("Tests/Fixtures/LottieOracle/lottie-web-intent", isDirectory: true)
        let traces = try FileManager.default.contentsOfDirectory(
            at: intentDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        #expect(traces.count >= 30)

        for traceURL in traces {
            let trace = try LottieWebIntentTrace.decodeValidated(from: Data(contentsOf: traceURL))
            #expect(trace.schema.name == "purelottie.lottie-web-intent", "\(traceURL.lastPathComponent)")
            #expect(trace.lottieWeb.version == "5.13.0", "\(traceURL.lastPathComponent)")
            #expect(trace.frames.isEmpty == false, "\(traceURL.lastPathComponent)")
        }
    }

    @Test("committed feature traces expose mask matte precomp and trim facts")
    func committedFeatureTracesExposeMaskMattePrecompAndTrimFacts() throws {
        let maskFrame = try intentFrame("mask-add-rectangle", sourceFrame: 5)
        #expect(maskFrame.maskCount == 1)
        let mask = try #require(maskFrame.masks.first)
        #expect(mask.layerName == "Masked Box")
        #expect(mask.mode == "a")
        #expect(mask.inverted == false)
        #expect(mask.closed == true)
        #expect(mask.vertexCount == 4)
        expectClose(mask.opacity, 1)
        expectClose(mask.localBBox.minX, 3)
        expectClose(mask.localBBox.maxX, 34)
        #expect(mask.pathD.isEmpty == false)

        let matteFrame = try intentFrame("alpha-matte-rectangle", sourceFrame: 5)
        #expect(matteFrame.matteCount == 1)
        let matte = try #require(matteFrame.mattes.first)
        #expect(matte.targetLayerName == "Matted Box")
        #expect(matte.sourceLayerName == "Matte Circle")
        #expect(matte.mode == 1)
        #expect(matte.sourceRenderElementIndex == 0)
        #expect(matte.targetRenderElementIndex == 1)
        #expect(matte.sourceResolved == true)
        #expect(matte.sourceIsMarker == true)

        let staticPrecomp = try intentTrace("precomp-static-child")
        let staticRenderedFrames: [Double?] = [0, 5, 9]
        #expect(staticPrecomp.frames.map { $0.precompositions.first?.renderedFrame } == staticRenderedFrames)
        let staticMiddle = try #require(staticPrecomp.frames.first { $0.frame == 5 }?.precompositions.first)
        #expect(staticMiddle.refId == "box_precomp")
        #expect(staticMiddle.layerName == "Precomp Layer")
        #expect(staticMiddle.timeRemapped == false)
        #expect(staticMiddle.childLayerCount == 1)
        #expect(staticMiddle.builtChildElementCount == 1)

        let timeRemapPrecomp = try intentTrace("time-remap-precomp-diagnosed")
        let remappedRenderedFrames: [Double?] = [5, 5, 5]
        #expect(timeRemapPrecomp.frames.map { $0.precompositions.first?.renderedFrame } == remappedRenderedFrames)
        for frame in timeRemapPrecomp.frames {
            let precomposition = try #require(frame.precompositions.first)
            #expect(precomposition.timeRemapped == true)
            expectClose(precomposition.timeRemapValue ?? -1, 5)
        }

        let trimFrame = try intentFrame("trim-rectangle-half", sourceFrame: 5)
        #expect(trimFrame.trimCount == 1)
        let trim = try #require(trimFrame.trims.first)
        #expect(trim.layerName == "Trimmed Rectangle")
        expectClose(trim.startFraction, 0)
        expectClose(trim.endFraction, 0.5)
        expectClose(trim.offsetTurns, 0)
        #expect(trim.mode == 1)
        #expect(trim.shapeCount == 1)
        #expect(trimFrame.diagnostics.contains { $0.feature == "trim.selectedSegments" })

        let animatedTrim = try intentTrace("animated-trim-path")
        let animatedEnds = try animatedTrim.frames.map { frame in
            try #require(frame.trims.first?.endFraction)
        }
        expectClose(animatedEnds[0], 0)
        expectClose(animatedEnds[1], 5.0 / 9.0)
        expectClose(animatedEnds[2], 1)
        #expect(animatedTrim.frames.allSatisfy { frame in
            frame.diagnostics.contains { $0.feature == "trim.selectedSegments" }
        })
    }

    @Test("invalid lottie-web intent trace reports exact JSON paths")
    func invalidLottieWebIntentTraceReportsExactJSONPaths() throws {
        var trace = try LottieWebIntentTrace.decodeValidated(from: eligibleIntentData())
        trace.schema.version = 2
        trace.frames[0].pathCount = 99
        trace.frames[0].layers[0].matrix = [1, 0]
        trace.frames[0].paths[0].d = ""
        trace.frames[0].paths[0].style.fill = ""

        let errors = LottieWebIntentTraceValidator().collectErrors(in: trace)
        let paths = Set(errors.map(\.codingPath.description))

        #expect(paths.contains("$.schema.version"))
        #expect(paths.contains("$.frames[0].pathCount"))
        #expect(paths.contains("$.frames[0].layers[0].matrix"))
        #expect(paths.contains("$.frames[0].paths[0].d"))
        #expect(paths.contains("$.frames[0].paths[0].style.fill"))

        var maskTrace = try intentTrace("mask-add-rectangle")
        maskTrace.frames[0].maskCount = 99
        maskTrace.frames[0].masks[0].pathD = ""
        let maskPaths = Set(LottieWebIntentTraceValidator()
            .collectErrors(in: maskTrace)
            .map(\.codingPath.description))
        #expect(maskPaths.contains("$.frames[0].maskCount"))
        #expect(maskPaths.contains("$.frames[0].masks[0].pathD"))

        var precompositionTrace = try intentTrace("precomp-static-child")
        precompositionTrace.frames[0].precompositions[0].builtChildElementCount = -1
        let precompositionPaths = Set(LottieWebIntentTraceValidator()
            .collectErrors(in: precompositionTrace)
            .map(\.codingPath.description))
        #expect(precompositionPaths.contains("$.frames[0].precompositions[0].builtChildElementCount"))

        var trimTrace = try intentTrace("trim-rectangle-half")
        trimTrace.frames[0].trimCount = 99
        trimTrace.frames[0].trims[0].renderElementIndex = -1
        trimTrace.frames[0].trims[0].layerInd = -1
        trimTrace.frames[0].trims[0].trimIndex = -1
        trimTrace.frames[0].trims[0].endFraction = 1.5
        trimTrace.frames[0].trims[0].mode = 0
        trimTrace.frames[0].trims[0].shapeCount = 0
        trimTrace.frames[0].diagnostics[0].reason = ""
        let trimPaths = Set(LottieWebIntentTraceValidator()
            .collectErrors(in: trimTrace)
            .map(\.codingPath.description))
        #expect(trimPaths.contains("$.frames[0].trimCount"))
        #expect(trimPaths.contains("$.frames[0].trims[0].renderElementIndex"))
        #expect(trimPaths.contains("$.frames[0].trims[0].layerInd"))
        #expect(trimPaths.contains("$.frames[0].trims[0].trimIndex"))
        #expect(trimPaths.contains("$.frames[0].trims[0].endFraction"))
        #expect(trimPaths.contains("$.frames[0].trims[0].mode"))
        #expect(trimPaths.contains("$.frames[0].trims[0].shapeCount"))
        #expect(trimPaths.contains("$.frames[0].diagnostics[0].reason"))
    }

    @Test("missing lottie-web intent keys decode as validation errors with paths")
    func missingLottieWebIntentKeysDecodeAsValidationErrorsWithPaths() throws {
        let source = #"{"schema":{"name":"purelottie.lottie-web-intent","version":1}}"#

        do {
            _ = try LottieWebIntentTrace.decodeValidated(from: Data(source.utf8))
            Issue.record("Expected missing source key to fail decode validation.")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.first?.codingPath.description == "$.source")
            #expect(errors.values.first?.phase == .parse)
        } catch {
            Issue.record("Expected ValidationErrorCollection, got \(error).")
        }
    }

    @Test("default lottie-web intent validator is composable and removable")
    func defaultLottieWebIntentValidatorIsComposableAndRemovable() throws {
        var trace = try LottieWebIntentTrace.decodeValidated(from: eligibleIntentData())
        trace.schema.version = 2

        let strictErrors = LottieWebIntentTraceValidator().collectErrors(in: trace)
        #expect(strictErrors.contains { $0.codingPath.description == "$.schema.version" })

        let relaxedErrors = LottieWebIntentTraceValidator()
            .withoutValidating(\.schemaNameAndVersionAreSupported)
            .collectErrors(in: trace)
        #expect(relaxedErrors.contains { $0.codingPath.description == "$.schema.version" } == false)

        let custom = Validation<LottieWebIntentTrace, LottieWebIntentTrace>(
            ruleID: "test.trace.source-suffix",
            description: "Trace source path ends with .lottie.json",
            phase: .source
        ) { context in
            context.subject.source.hasSuffix(".lottie.json")
        }
        let customErrors = LottieWebIntentTraceValidator.blank
            .validating(custom)
            .collectErrors(in: trace)
        #expect(customErrors.map(\.codingPath.description) == ["$"])
    }

    private func eligibleIntentData() throws -> Data {
        try intentData("eligible-shape-position")
    }

    private func intentFrame(_ name: String, sourceFrame: Double) throws -> LottieWebIntentTrace.Frame {
        let trace = try intentTrace(name)
        return try #require(trace.frames.first { $0.frame == sourceFrame })
    }

    private func intentTrace(_ name: String) throws -> LottieWebIntentTrace {
        try LottieWebIntentTrace.decodeValidated(from: intentData(name))
    }

    private func intentData(_ name: String) throws -> Data {
        try Data(contentsOf: repositoryRoot()
            .appendingPathComponent(
                "Tests/Fixtures/LottieOracle/lottie-web-intent/\(name).json"
            ))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 0.000_001) {
        #expect(abs(actual - expected) <= tolerance)
    }
}
