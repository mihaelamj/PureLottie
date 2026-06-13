import Foundation
import LottieEvaluation
import Testing

@Suite("artifact frame timing")
struct LottieArtifactFrameTimingTests {
    @Test("APNG half-open window records exact count derivation")
    func apngHalfOpenWindowRecordsExactCountDerivation() throws {
        let timing = LottieArtifactFrameTiming.apngHalfOpenWindow(
            source: .init(frameRate: 10, inPoint: 100, outPoint: 110),
            requestedStartSeconds: 0,
            requestedExclusiveEndSeconds: 1,
            outputFPS: 5
        )

        try timing.validate()

        #expect(timing.policy == .apngHalfOpenWindow)
        #expect(timing.request.outputFrameIntervalSeconds == 0.2)
        #expect(timing.derivation.effectiveInclusiveEndSeconds == 0.8)
        #expect(timing.derivation.generatedFrameCount == 5)
        #expect(timing.samples.map(\.index) == [0, 1, 2, 3, 4])
        expectClose(timing.samples.map(\.timeSeconds), [0, 0.2, 0.4, 0.6, 0.8])
        expectClose(timing.samples.map(\.sourceFrame), [100, 102, 104, 106, 108])
        #expect(timing.derivation.countFormula.contains("effectiveInclusiveEndSeconds"))
        #expect(timing.derivation.rationale.contains("= 5"))
    }

    @Test("APNG zero-duration boundary still records one sample")
    func apngZeroDurationBoundaryStillRecordsOneSample() throws {
        let timing = LottieArtifactFrameTiming.apngHalfOpenWindow(
            source: .init(frameRate: 24, inPoint: 12, outPoint: 12),
            requestedStartSeconds: 2,
            requestedExclusiveEndSeconds: 2,
            outputFPS: 12
        )

        try timing.validate()

        #expect(timing.derivation.generatedFrameCount == 1)
        #expect(timing.derivation.effectiveInclusiveEndSeconds == 2)
        expectClose(timing.samples.map(\.timeSeconds), [2])
        expectClose(timing.samples.map(\.sourceFrame), [60])
        #expect(timing.derivation.rationale.contains("= 1"))
    }

    @Test("explicit source-frame list records source frame and time mapping")
    func explicitSourceFrameListRecordsSourceFrameAndTimeMapping() throws {
        let timing = LottieArtifactFrameTiming.explicitSourceFrameList(
            source: .init(frameRate: 10, inPoint: 100, outPoint: 110),
            sourceFrames: [100, 105, 109]
        )

        try timing.validate()

        #expect(timing.policy == .explicitSourceFrameList)
        #expect(timing.request.sourceFrames == [100, 105, 109])
        #expect(timing.derivation.generatedFrameCount == 3)
        expectClose(timing.samples.map(\.timeSeconds), [0, 0.5, 0.9])
        expectClose(timing.samples.map(\.sourceFrame), [100, 105, 109])
        #expect(timing.derivation.countFormula == "requestedSourceFrames.count")
        #expect(timing.derivation.rationale.contains("requestedSourceFrames.count = 3"))
    }

    @Test("invalid timing reports exact JSON paths")
    func invalidTimingReportsExactJSONPaths() {
        var timing = LottieArtifactFrameTiming.explicitSourceFrameList(
            source: .init(frameRate: 10, inPoint: 100, outPoint: 110),
            sourceFrames: [100, 105]
        )
        timing.source.durationSeconds = 99
        timing.derivation.generatedFrameCount = 99
        timing.samples[1].index = 4
        timing.samples[1].timeSeconds = 99
        timing.request.sourceFrames = [100, 105, 110]
        var invalidRateTiming = timing
        invalidRateTiming.source.frameRate = 0

        let validator = LottieArtifactFrameTimingValidator()
        let paths = Set((validator.collectErrors(in: timing) + validator.collectErrors(in: invalidRateTiming))
            .map(\.codingPath.description))

        #expect(paths.contains("$.source.frameRate"))
        #expect(paths.contains("$.source.durationSeconds"))
        #expect(paths.contains("$.derivation.generatedFrameCount"))
        #expect(paths.contains("$.samples[1].index"))
        #expect(paths.contains("$.request.sourceFrames"))
    }

    @Test("APNG timing validator catches intermediate time drift")
    func apngTimingValidatorCatchesIntermediateTimeDrift() {
        var timing = LottieArtifactFrameTiming.apngHalfOpenWindow(
            source: .init(frameRate: 10, inPoint: 100, outPoint: 110),
            requestedStartSeconds: 0,
            requestedExclusiveEndSeconds: 1,
            outputFPS: 5
        )
        timing.samples[1].timeSeconds = 0.25
        timing.samples[1].sourceFrame = 102.5

        let paths = Set(LottieArtifactFrameTimingValidator()
            .collectErrors(in: timing)
            .map(\.codingPath.description))

        #expect(paths.contains("$.samples[1].timeSeconds"))
    }

    @Test("APNG timing validator rejects non-finite request times")
    func apngTimingValidatorRejectsNonFiniteRequestTimes() {
        var timing = LottieArtifactFrameTiming.apngHalfOpenWindow(
            source: .init(frameRate: 10, inPoint: 100, outPoint: 110),
            requestedStartSeconds: 0,
            requestedExclusiveEndSeconds: 1,
            outputFPS: 5
        )
        timing.request.startSeconds = .nan
        timing.derivation.effectiveInclusiveEndSeconds = .infinity

        let paths = Set(LottieArtifactFrameTimingValidator()
            .collectErrors(in: timing)
            .map(\.codingPath.description))

        #expect(paths.contains("$.request.startSeconds"))
        #expect(paths.contains("$.derivation.effectiveInclusiveEndSeconds"))
    }

    @Test("default timing validation set is composable and documented")
    func defaultTimingValidationSetIsComposableAndDocumented() throws {
        var timing = LottieArtifactFrameTiming.explicitSourceFrameList(
            source: .init(frameRate: 10, inPoint: 100, outPoint: 110),
            sourceFrames: [100]
        )
        timing.derivation.generatedFrameCount = 9

        let countDescription = LottieArtifactFrameTimingBuiltinValidation
            .generatedFrameCountMatchesSamples
            .description

        #expect(
            LottieArtifactFrameTimingValidator()
                .collectErrors(in: timing)
                .contains { $0.codingPath.description == "$.derivation.generatedFrameCount" }
        )
        #expect(
            LottieArtifactFrameTimingValidator()
                .withoutValidating(countDescription)
                .collectErrors(in: timing)
                .contains { $0.codingPath.description == "$.derivation.generatedFrameCount" } == false
        )
        #expect(
            LottieArtifactFrameTimingValidator.blank
                .validating(\.generatedFrameCountMatchesSamples)
                .validationDescriptions == [countDescription]
        )

        let documentation = try String(contentsOf: repositoryRoot()
            .appendingPathComponent("docs/lottie-format/rendered-artifact-manifest.md"))
        for description in LottieArtifactFrameTimingValidator().validationDescriptions {
            #expect(documentation.contains(description), "Missing validation description: \(description)")
        }
    }

    private func expectClose(_ actual: [Double], _ expected: [Double], tolerance: Double = 0.000_001) {
        #expect(actual.count == expected.count)
        for index in actual.indices where expected.indices.contains(index) {
            #expect(abs(actual[index] - expected[index]) <= tolerance, "\(actual[index]) != \(expected[index])")
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
