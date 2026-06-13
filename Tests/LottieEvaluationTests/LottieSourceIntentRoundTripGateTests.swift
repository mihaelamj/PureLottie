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

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
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
