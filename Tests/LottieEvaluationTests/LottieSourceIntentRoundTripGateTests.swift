import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie source-intent round-trip gate")
struct LottieSourceIntentRoundTripGateTests {
    @Test("transform and timing facts round trip before rendering")
    func transformAndTimingFactsRoundTripBeforeRendering() throws {
        let report = try LottieSourceIntentTransformTimingRoundTripGate().report(
            animation: decode(transformTimingAnimation),
            source: LottieDecompiledSourceIntentSource(identity: "transform-timing", frameCount: 0),
            selectedFrames: [
                LottieSourceIntentRoundTripSelection(
                    frame: 8,
                    rationale: "Frame 8 proves layer start-time/stretch local frame mapping and static transform preservation."
                ),
            ]
        )

        try report.validate()
        #expect(report.frameCount == 1)
        #expect(report.findingCount == 0)
        #expect(report.lossCount == 0)

        let frame = try #require(report.frames.first)
        #expect(frame.sourceFrame == 8)
        #expect(frame.rationale.contains("start-time/stretch"))
        let layer = try #require(frame.layers.first)
        #expect(layer.timingMode == "startTimeAndStretch")
        #expect(layer.localFrame == 3)
        #expect(layer.decompiledLocalFrame == 3)
        #expect(layer.position == [20, 30, 0])
        #expect(layer.decompiledPosition == [20, 30, 0])
        #expect(layer.scale == [150, 50, 100])
        #expect(layer.decompiledScale == [150, 50, 100])
        #expect(layer.rotationZDegrees == 10)
        #expect(layer.decompiledRotationZDegrees == 10)
        #expect(layer.matrix.count == 16)
        #expect(layer.matrix == layer.decompiledMatrix)
        #expect(layer.matrixTranslation == layer.decompiledMatrixTranslation)
    }

    @Test("time remap is reported as decompiler timing loss")
    func timeRemapIsReportedAsDecompilerTimingLoss() throws {
        let report = try LottieSourceIntentTransformTimingRoundTripGate().report(
            animation: decode(timeRemapAnimation),
            source: LottieDecompiledSourceIntentSource(identity: "time-remap", frameCount: 0),
            selectedFrames: [
                LottieSourceIntentRoundTripSelection(
                    frame: 20,
                    rationale: "Frame 20 exercises authored `tm` seconds mapped to child local source frames."
                ),
            ]
        )

        try report.validate()
        #expect(report.findingCount == 0)
        #expect(report.lossCount == 1)
        let frame = try #require(report.frames.first)
        let precomp = try #require(frame.layers.first { $0.name == "Remapped Precomp" })
        #expect(precomp.timingMode == "timeRemapSeconds")
        let loss = try #require(frame.losses.first)
        #expect(loss.ruleID == "lottie.decompile.timing.time-remap-loss")
        #expect(loss.jsonPath == "$.layers[0].tm")
        #expect(loss.sourcePath == "root > layer 'Remapped Precomp'")
    }

    @Test("round trip report validation rejects missing frame rationale")
    func roundTripReportValidationRejectsMissingFrameRationale() {
        #expect(LottieSourceIntentRoundTripReportValidator().validationDescriptions.contains(
            "Round-trip report contains unique selected frames with rationales"
        ))

        let report = LottieSourceIntentRoundTripReport(
            source: LottieDecompiledSourceIntentSource(identity: "bad", frameCount: 1),
            frames: [
                LottieSourceIntentRoundTripFrame(
                    sourceFrame: 0,
                    rationale: "",
                    localTimeSeconds: 0,
                    layers: []
                ),
            ]
        )

        let errors = LottieSourceIntentRoundTripReportValidator().collectErrors(in: report)
        #expect(errors.contains { $0.ruleID == "lottie.round-trip.frame.rationale" })

        let validatorWithoutRationale = LottieSourceIntentRoundTripReportValidator()
            .withoutValidating("Round-trip report contains unique selected frames with rationales")
        #expect(!validatorWithoutRationale.validationDescriptions.contains(
            "Round-trip report contains unique selected frames with rationales"
        ))
        #expect(validatorWithoutRationale.collectErrors(in: report).isEmpty)
    }

    @Test("round trip report validation rejects pathless embedded losses")
    func roundTripReportValidationRejectsPathlessEmbeddedLosses() {
        #expect(LottieSourceIntentRoundTripReportValidator().validationDescriptions.contains(
            "Round-trip embedded decompiler losses contain rule id model path source/json path and reason"
        ))

        let report = LottieSourceIntentRoundTripReport(
            source: LottieDecompiledSourceIntentSource(identity: "bad-loss", frameCount: 1),
            frames: [
                LottieSourceIntentRoundTripFrame(
                    sourceFrame: 0,
                    rationale: "Path-bearing loss validation fixture.",
                    localTimeSeconds: 0,
                    layers: [],
                    losses: [
                        LottieDecompiledSourceIntentLoss(
                            kind: .missingSourceFact,
                            reconstructability: .notReconstructable,
                            phase: "decompile",
                            classification: "gap",
                            modelPath: "",
                            reason: ""
                        ),
                    ]
                ),
            ]
        )

        let errors = LottieSourceIntentRoundTripReportValidator().collectErrors(in: report)
        #expect(errors.contains { $0.ruleID == "lottie.round-trip.loss.rule-id" })
        #expect(errors.contains { $0.ruleID == "lottie.round-trip.loss.model-path" })
        #expect(errors.contains { $0.ruleID == "lottie.round-trip.loss.source-path" })
        #expect(errors.contains { $0.ruleID == "lottie.round-trip.loss.json-path" })
        #expect(errors.contains { $0.ruleID == "lottie.round-trip.loss.reason" })
    }

    @Test("path style trim mask and matte facts round trip from curated fixtures")
    func pathStyleTrimMaskAndMatteFactsRoundTripFromCuratedFixtures() throws {
        let fillRule = try roundTripReport(fixture: "fill-rule-evenodd.json")
        try fillRule.validate()
        #expect(fillRule.findingCount == 0)
        let fillLayer = try #require(fillRule.frames.first?.layers.first)
        #expect(fillLayer.geometryCount == fillLayer.decompiledGeometryCount)
        #expect(fillLayer.styleCount == fillLayer.decompiledStyleCount)

        let fillIntent = try decompiledIntent(fixture: "fill-rule-evenodd.json")
        let fillStyle = try #require(fillIntent.frames.first?.visibleLayers.first?.styles.first)
        #expect(fillStyle.fillRule == 2)

        let trim = try roundTripReport(fixture: "trim-ellipse-quadrant.json")
        try trim.validate()
        #expect(trim.findingCount == 0)
        let trimLayer = try #require(trim.frames.first?.layers.first)
        #expect(trimLayer.trimTraceCount == 1)
        #expect(trimLayer.trimTraceCount == trimLayer.decompiledTrimTraceCount)
        let trimIntent = try decompiledIntent(fixture: "trim-ellipse-quadrant.json")
        let trimTrace = try #require(trimIntent.frames.first?.visibleLayers.first?.trimTraces?.first)
        #expect(trimTrace.normalization.normalizedStartFraction == 0)
        #expect(trimTrace.normalization.normalizedEndFraction == 0.25)
        #expect(trimTrace.selectedSegments.count == 1)

        let mask = try roundTripReport(fixture: "mask-add-rectangle.json")
        try mask.validate()
        #expect(mask.findingCount == 0)
        let maskLayer = try #require(mask.frames.first?.layers.first)
        #expect(maskLayer.maskCount == 1)
        #expect(maskLayer.maskCount == maskLayer.decompiledMaskCount)

        let matte = try roundTripReport(fixture: "alpha-matte-rectangle.json")
        try matte.validate()
        #expect(matte.findingCount == 0)
        #expect(matte.frames.first?.layers.contains { $0.hasMatte && $0.decompiledHasMatte } == true)
    }

    @Test("backend approximate style and trim facts produce path-bearing losses")
    func backendApproximateStyleAndTrimFactsProducePathBearingLosses() throws {
        let trim = try roundTripReport(fixture: "trim-ellipse-quadrant.json")
        try trim.validate()
        #expect(trim.lossCount > 0)
        #expect(trim.frames.flatMap(\.losses).contains { loss in
            loss.ruleID == "lottie.round-trip.trim.approximation"
                && loss.sourcePath?.contains("Trim") == true
                && loss.jsonPath?.contains(".shapes") == true
        })

        let stroke = try roundTripReport(fixture: "stroke-dash.json")
        try stroke.validate()
        #expect(stroke.findingCount == 0)
        let losses = stroke.frames.flatMap(\.losses)
        #expect(losses.contains { $0.ruleID == "lottie.round-trip.style.stroke-dash-loss" && $0.sourcePath?.contains("stroke") == true })
        #expect(losses.allSatisfy { loss in
            !(loss.modelPath.isEmpty)
                && loss.sourcePath?.isEmpty == false
                && loss.jsonPath?.isEmpty == false
                && loss.reason.isEmpty == false
        })
    }

    @Test("round trip report validation rejects negative feature counts")
    func roundTripReportValidationRejectsNegativeFeatureCounts() throws {
        #expect(LottieSourceIntentRoundTripReportValidator().validationDescriptions.contains(
            "Round-trip layer feature-family counts are nonnegative"
        ))

        var report = try roundTripReport(fixture: "fill-rule-evenodd.json")
        report.frames[0].layers[0].geometryCount = -1

        let errors = LottieSourceIntentRoundTripReportValidator().collectErrors(in: report)
        #expect(errors.contains { $0.ruleID == "lottie.round-trip.layer.feature-count" })
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }

    private func roundTripReport(fixture name: String, frame: Double = 0) throws -> LottieSourceIntentRoundTripReport {
        let animation = try decodeFixture(name)
        return LottieSourceIntentTransformTimingRoundTripGate().report(
            animation: animation,
            source: LottieDecompiledSourceIntentSource(identity: name, path: fixture(name).path, frameCount: 0),
            selectedFrames: [
                LottieSourceIntentRoundTripSelection(
                    frame: frame,
                    rationale: "Curated fixture \(name) checks source-intent feature round trip before rendering."
                ),
            ]
        )
    }

    private func decompiledIntent(fixture name: String, frame: Double = 0) throws -> LottieDecompiledSourceIntent {
        let animation = try decodeFixture(name)
        let renderFrame = LottieRenderIRBuilder(animation: animation).frame(at: frame)
        let intent = LottieSourceIntentDecompiler().decompile(
            frame: renderFrame,
            source: LottieDecompiledSourceIntentSource(identity: name, path: fixture(name).path, frameCount: 0)
        )
        try intent.validate()
        return intent
    }

    private func decodeFixture(_ name: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(contentsOf: fixture(name)))
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieOracle", isDirectory: true)
            .appendingPathComponent(name)
    }

    private var transformTimingAnimation: String {
        """
        {
          "v": "5.7.4",
          "nm": "Transform Timing",
          "fr": 10,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Moved",
            "ind": 1,
            "ip": 0,
            "op": 20,
            "st": 2,
            "sr": 2,
            "ks": {
              "p": { "a": 0, "k": [20, 30, 0] },
              "s": { "a": 0, "k": [150, 50, 100] },
              "r": { "a": 0, "k": 10 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": []
          }]
        }
        """
    }

    private var timeRemapAnimation: String {
        """
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
        """
    }
}
